// I2C.swift — Minimal I2C Master for Arduino Due (ATSAM3X8E / TWI1 on pins 20/21)
// Depends on: MMIO.swift (U32, read32/write32, bm_dsb/bm_isb), ATSAM3X8E.swift, Timer.swift

public final class I2C {
    public enum Bus {
        /// Arduino Due "Wire"  -> TWI1 -> pins 20(SDA)/21(SCL)
        case wire
        /// Arduino Due "Wire1" -> TWI0 -> pins SDA1/SCL1 (near AREF)
        case wire1
    }

    // Error codes aligned with Arduino Wire style:
    // 0 = success
    // 1 = data too long (buffer)
    // 2 = NACK on address
    // 3 = NACK on data
    // 4 = other error / timeout
    public static let BUFFER_LENGTH: Int = 32

    private let bus: Bus
    private let timer: Timer
    private let mckHz: U32

    // Selected peripheral base (absolute regs are in ATSAM3X8E.TWI.TWI0/TWI1)
    private let REG_CR: U32
    private let REG_MMR: U32
    private let REG_IADR: U32
    private let REG_CWGR: U32
    private let REG_SR: U32
    private let REG_RHR: U32
    private let REG_THR: U32

    // TX state
    private var txAddress: UInt8 = 0
    private var txBuf: [UInt8] = Array(repeating: 0, count: BUFFER_LENGTH)
    private var txLen: Int = 0

    // RX state
    private var rxBuf: [UInt8] = Array(repeating: 0, count: BUFFER_LENGTH)
    private var rxIndex: Int = 0
    private var rxLen: Int = 0

    public init(mckHz: U32, timer: Timer, bus: Bus = .wire) {
        self.bus = bus
        self.timer = timer
        self.mckHz = mckHz

        switch bus {
        case .wire: // TWI1 (pins 20/21)
            REG_CR   = ATSAM3X8E.TWI.TWI1.CR
            REG_MMR  = ATSAM3X8E.TWI.TWI1.MMR
            REG_IADR = ATSAM3X8E.TWI.TWI1.IADR
            REG_CWGR = ATSAM3X8E.TWI.TWI1.CWGR
            REG_SR   = ATSAM3X8E.TWI.TWI1.SR
            REG_RHR  = ATSAM3X8E.TWI.TWI1.RHR
            REG_THR  = ATSAM3X8E.TWI.TWI1.THR

        case .wire1: // TWI0 (SDA1/SCL1)
            REG_CR   = ATSAM3X8E.TWI.TWI0.CR
            REG_MMR  = ATSAM3X8E.TWI.TWI0.MMR
            REG_IADR = ATSAM3X8E.TWI.TWI0.IADR
            REG_CWGR = ATSAM3X8E.TWI.TWI0.CWGR
            REG_SR   = ATSAM3X8E.TWI.TWI0.SR
            REG_RHR  = ATSAM3X8E.TWI.TWI0.RHR
            REG_THR  = ATSAM3X8E.TWI.TWI0.THR
        }
    }

    // MARK: - Public API

    /// Master begin (config pins + enable clock + master mode)
    public func begin() {
        // Enable clocks needed to configure pins + TWI peripheral
        // PIOB is needed to switch PB12/PB13 into peripheral mode for Wire (TWI1).
        // (Safe even if bus is wire1; leaving as-is is harmless.)
        pmcEnable(peripheralID: ATSAM3X8E.ID.PIOB)

        switch bus {
        case .wire:
            // Wire pins 20/21 are on PIOB: PB12 (SDA), PB13 (SCL), Peripheral A
            configureWirePins_TWI1_PB12_PB13()
            pmcEnable(peripheralID: ATSAM3X8E.ID.TWI1)

        case .wire1:
            // Wire1 pins (SDA1/SCL1) are NOT PB12/PB13.
            // If you want Wire1 later, we add the correct pin mux here.
            // For now we at least enable the peripheral clock.
            pmcEnable(peripheralID: ATSAM3X8E.ID.TWI0)
        }

        // Reset
        write32(REG_CR, ATSAM3X8E.TWI.CR_SWRST)
        _ = read32(REG_RHR) // dummy read per datasheet/common drivers

        // Disable both, then enable master
        write32(REG_CR, ATSAM3X8E.TWI.CR_SVDIS | ATSAM3X8E.TWI.CR_MSDIS)
        write32(REG_CR, ATSAM3X8E.TWI.CR_MSEN)

        // Default 100kHz
        setClock(100_000)
    }

    public func setClock(_ hz: U32) {
        // Mirrors the logic of the C driver you pasted:
        // cldiv = ((mck/(2*twck)) - 4) / 2^ckdiv  (find ckdiv such that cldiv <= 255)
        if hz == 0 { return }

        var ckdiv: U32 = 0
        var cldiv: U32 = 0

        while true {
            let denom = U32(1) << ckdiv
            // Avoid underflow if someone passes huge hz
            let base = (mckHz / (2 * hz))
            if base > 4 {
                cldiv = (base - 4) / denom
            } else {
                cldiv = 0
            }

            if cldiv <= 255 { break }
            ckdiv &+= 1
            if ckdiv >= 8 { break }
        }

        let cwgr = (ckdiv << 16) | (cldiv << 8) | cldiv
        write32(REG_CWGR, cwgr)
    }

    public func beginTransmission(_ address7: UInt8) {
        txAddress = address7 & 0x7F
        txLen = 0
    }

    @discardableResult
    public func write(_ b: UInt8) -> Int {
        if txLen >= Self.BUFFER_LENGTH { return 0 }
        txBuf[txLen] = b
        txLen += 1
        return 1
    }

    @discardableResult
    public func write(_ data: [UInt8]) -> Int {
        var written = 0
        for b in data {
            if write(b) == 0 { break }
            written += 1
        }
        return written
    }

    public func endTransmission(_ sendStop: Bool = true) -> UInt8 {
        if txLen == 0 { return 0 }

        // Master write: MMR = DADR + IADRSZ_NONE + MREAD=0
        let dadr = (U32(txAddress) << ATSAM3X8E.TWI.MMR_DADR_SHIFT) & ATSAM3X8E.TWI.MMR_DADR_MASK
        write32(REG_MMR, ATSAM3X8E.TWI.MMR_IADRSZ_NONE | dadr)
        write32(REG_IADR, 0)

        // Send first byte
        write32(REG_THR, U32(txBuf[0]))
        if !waitTXRDY(timeoutMs: 20) {
            return nackOrTimeoutCode()
        }

        // Remaining bytes
        if txLen > 1 {
            var i = 1
            while i < txLen {
                write32(REG_THR, U32(txBuf[i]))
                if !waitTXRDY(timeoutMs: 20) {
                    return nackOrTimeoutCode(dataPhase: true)
                }
                i += 1
            }
        }

        if sendStop {
            // Send STOP then wait TXCOMP
            write32(REG_CR, ATSAM3X8E.TWI.CR_STOP)
            if !waitTXCOMP(timeoutMs: 20) {
                return nackOrTimeoutCode()
            }
        }

        txLen = 0
        return 0
    }

    public func requestFrom(_ address7: UInt8, _ quantity: Int, _ sendStop: Bool = true) -> Int {
        var q = quantity
        if q > Self.BUFFER_LENGTH { q = Self.BUFFER_LENGTH }
        if q <= 0 { return 0 }

        rxIndex = 0
        rxLen = 0

        let addr = UInt8(address7 & 0x7F)

        // Master read: MMR = DADR + IADRSZ_NONE + MREAD
        let dadr = (U32(addr) << ATSAM3X8E.TWI.MMR_DADR_SHIFT) & ATSAM3X8E.TWI.MMR_DADR_MASK
        write32(REG_MMR, ATSAM3X8E.TWI.MMR_IADRSZ_NONE | ATSAM3X8E.TWI.MMR_MREAD | dadr)
        write32(REG_IADR, 0)

        // For single-byte read: STOP must be set immediately after START (common Atmel pattern)
        if q == 1 && sendStop {
            write32(REG_CR, ATSAM3X8E.TWI.CR_START | ATSAM3X8E.TWI.CR_STOP)
        } else {
            write32(REG_CR, ATSAM3X8E.TWI.CR_START)
        }

        var i = 0
        while i < q {
            // Before receiving the last byte, request STOP (multi-byte)
            if sendStop && (i == q - 1) && (q > 1) {
                write32(REG_CR, ATSAM3X8E.TWI.CR_STOP)
            }

            if !waitRXRDY(timeoutMs: 20) {
                // NACK or timeout
                return 0
            }

            let b = UInt8(truncatingIfNeeded: read32(REG_RHR) & 0xFF)
            rxBuf[i] = b
            i += 1
        }

        // Wait TXCOMP for end of transfer when STOP is used
        if sendStop {
            _ = waitTXCOMP(timeoutMs: 20)
        }

        rxLen = q
        return q
    }

    public func available() -> Int {
        return rxLen - rxIndex
    }

    /// Returns next byte as Int (Arduino-style), or -1 if none.
    public func read() -> Int {
        if rxIndex >= rxLen { return -1 }
        let b = rxBuf[rxIndex]
        rxIndex += 1
        return Int(b)
    }

    // MARK: - Internals

    @inline(__always)
    private func pmcEnable(peripheralID: U32) {
        // PMC_PCER0 bit = 1 << pid
        let mask = U32(1) << peripheralID
        write32(ATSAM3X8E.PMC.PCER0, mask)
    }

    /// Configure PB12/PB13 as Peripheral A (TWI1) + pullups.
    private func configureWirePins_TWI1_PB12_PB13() {
        let pioB = ATSAM3X8E.PIOB_BASE

        let sdaMask: U32 = U32(1) << 12 // PB12
        let sclMask: U32 = U32(1) << 13 // PB13
        let mask = sdaMask | sclMask

        // Enable pull-ups
        write32(pioB + ATSAM3X8E.PIOX.PUER_OFFSET, mask)

        // Select Peripheral A: clear bits in ABSR for these pins
        let absrAddr = pioB + ATSAM3X8E.PIOX.ABSR_OFFSET
        let absr = read32(absrAddr)
        write32(absrAddr, absr & ~mask)

        // Disable PIO (hand control to peripheral)
        write32(pioB + ATSAM3X8E.PIOX.PDR_OFFSET, mask)
    }

    @inline(__always)
    private func sr() -> U32 { read32(REG_SR) }

    private func nackOrTimeoutCode(dataPhase: Bool = false) -> UInt8 {
        let s = sr()
        if (s & ATSAM3X8E.TWI.SR_NACK) != 0 {
            return dataPhase ? 3 : 2
        }
        return 4
    }

    private func waitTXRDY(timeoutMs: U32) -> Bool {
        let start = timer.millis()
        while true {
            let s = sr()
            if (s & ATSAM3X8E.TWI.SR_NACK) != 0 { return false }
            if (s & ATSAM3X8E.TWI.SR_TXRDY) != 0 { return true }
            if (timer.millis() &- start) >= timeoutMs { return false }
        }
    }

    private func waitRXRDY(timeoutMs: U32) -> Bool {
        let start = timer.millis()
        while true {
            let s = sr()
            if (s & ATSAM3X8E.TWI.SR_NACK) != 0 { return false }
            if (s & ATSAM3X8E.TWI.SR_RXRDY) != 0 { return true }
            if (timer.millis() &- start) >= timeoutMs { return false }
        }
    }

    private func waitTXCOMP(timeoutMs: U32) -> Bool {
        let start = timer.millis()
        while true {
            let s = sr()
            if (s & ATSAM3X8E.TWI.SR_NACK) != 0 { return false }
            if (s & ATSAM3X8E.TWI.SR_TXCOMP) != 0 { return true }
            if (timer.millis() &- start) >= timeoutMs { return false }
        }
    }
}