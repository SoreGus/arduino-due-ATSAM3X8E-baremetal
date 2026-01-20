// I2C.swift — Arduino Due TWI (I2C) support (Master + Slave)
// Target: ATSAM3X8E (Arduino Due), default bus = Wire (pins 20/21 => TWI1)
//
// Depends on: MMIO.swift (U32, read32/write32), ATSAM3X8E.swift, Timer.swift

public final class I2C {
    public enum Bus {
        /// Arduino Due "Wire"  -> TWI1 -> pins 20(SDA)/21(SCL)
        case wire
        /// Arduino Due "Wire1" -> TWI0 -> pins SDA1/SCL1 (near AREF)
        case wire1
    }

    // Arduino Wire-style error codes:
    // 0 = success
    // 1 = data too long (buffer)
    // 2 = NACK on address
    // 3 = NACK on data
    // 4 = other error / timeout
    public static let BUFFER_LENGTH: Int = 32

    public typealias OnReceive = (_ count: Int) -> Void
    public typealias OnRequest = () -> Void

    private enum Mode {
        case idle
        case master
        case slave(address7: UInt8)
    }

    private enum SlaveState {
        case idle
        case receiving
        case transmitting
    }

    private let bus: Bus
    private let timer: Timer
    private let mckHz: U32

    // Selected peripheral regs (absolute addresses provided by ATSAM3X8E.swift)
    private let REG_CR: U32
    private let REG_MMR: U32
    private let REG_SMR: U32
    private let REG_IADR: U32
    private let REG_CWGR: U32
    private let REG_SR: U32
    private let REG_RHR: U32
    private let REG_THR: U32

    // PDC (DMA) control
    private let REG_PTCR: U32
    private static let PTCR_RXTDIS: U32 = (U32(1) << 1)
    private static let PTCR_TXTDIS: U32 = (U32(1) << 9)

    private var mode: Mode = .idle

    // ---------- Master TX state ----------
    private var masterTxAddress: UInt8 = 0
    private var masterTxBuf: [UInt8] = Array(repeating: 0, count: BUFFER_LENGTH)
    private var masterTxLen: Int = 0

    // ---------- Shared RX state (master requestFrom OR slave receive) ----------
    private var rxBuf: [UInt8] = Array(repeating: 0, count: BUFFER_LENGTH)
    private var rxIndex: Int = 0
    private var rxLen: Int = 0

    // ---------- Slave TX state (filled by onRequest via write()) ----------
    private var slaveTxBuf: [UInt8] = Array(repeating: 0, count: BUFFER_LENGTH)
    private var slaveTxIndex: Int = 0
    private var slaveTxLen: Int = 0

    private var slaveState: SlaveState = .idle
    private var inSlaveRequestCallback: Bool = false

    private var onReceiveCb: OnReceive? = nil
    private var onRequestCb: OnRequest? = nil

    // SMR SADR field (SAM3X TWI_SMR.SADR is 7-bit)
    private static let SMR_SADR_SHIFT: U32 = 16
    private static let SMR_SADR_MASK: U32  = 0x7F << SMR_SADR_SHIFT

    public init(mckHz: U32, timer: Timer, bus: Bus = .wire) {
        self.bus = bus
        self.timer = timer
        self.mckHz = mckHz

        switch bus {
        case .wire: // TWI1 (pins 20/21)
            REG_CR   = ATSAM3X8E.TWI.TWI1.CR
            REG_MMR  = ATSAM3X8E.TWI.TWI1.MMR
            REG_SMR  = ATSAM3X8E.TWI.TWI1.SMR
            REG_IADR = ATSAM3X8E.TWI.TWI1.IADR
            REG_CWGR = ATSAM3X8E.TWI.TWI1.CWGR
            REG_SR   = ATSAM3X8E.TWI.TWI1.SR
            REG_RHR  = ATSAM3X8E.TWI.TWI1.RHR
            REG_THR  = ATSAM3X8E.TWI.TWI1.THR
            REG_PTCR = ATSAM3X8E.TWI.TWI1.PTCR

        case .wire1: // TWI0 (SDA1/SCL1)
            REG_CR   = ATSAM3X8E.TWI.TWI0.CR
            REG_MMR  = ATSAM3X8E.TWI.TWI0.MMR
            REG_SMR  = ATSAM3X8E.TWI.TWI0.SMR
            REG_IADR = ATSAM3X8E.TWI.TWI0.IADR
            REG_CWGR = ATSAM3X8E.TWI.TWI0.CWGR
            REG_SR   = ATSAM3X8E.TWI.TWI0.SR
            REG_RHR  = ATSAM3X8E.TWI.TWI0.RHR
            REG_THR  = ATSAM3X8E.TWI.TWI0.THR
            REG_PTCR = ATSAM3X8E.TWI.TWI0.PTCR
        }
    }

    // MARK: - Public API (Wire-like)

    /// Master begin (config pins + enable clock + master mode)
    public func begin() {
        configurePinsAndClock()

        // Disable PDC channels (ArduinoCore does this)
        write32(REG_PTCR, Self.PTCR_RXTDIS | Self.PTCR_TXTDIS)

        // Reset sequence
        write32(REG_CR, ATSAM3X8E.TWI.CR_SWRST)
        _ = read32(REG_RHR)
        timer.sleepFor(ms: 2)

        // Disable both, then enable master
        write32(REG_CR, ATSAM3X8E.TWI.CR_SVDIS | ATSAM3X8E.TWI.CR_MSDIS)
        write32(REG_CR, ATSAM3X8E.TWI.CR_MSEN)

        mode = .master
        slaveState = .idle

        // Default 100kHz
        setClock(100_000)
    }

    /// Slave begin (config pins + enable clock + slave mode + set address)
    public func begin(_ address7: UInt8) {
        configurePinsAndClock()

        // Disable PDC channels (ArduinoCore does this)
        write32(REG_PTCR, Self.PTCR_RXTDIS | Self.PTCR_TXTDIS)

        // Reset + disable both
        write32(REG_CR, ATSAM3X8E.TWI.CR_SWRST)
        _ = read32(REG_RHR)
        timer.sleepFor(ms: 2)
        write32(REG_CR, ATSAM3X8E.TWI.CR_SVDIS | ATSAM3X8E.TWI.CR_MSDIS)

        // Program slave address (7-bit)
        let addr = U32(address7 & 0x7F)
        write32(REG_SMR, (addr << Self.SMR_SADR_SHIFT) & Self.SMR_SADR_MASK)

        // Enable slave
        write32(REG_CR, ATSAM3X8E.TWI.CR_SVEN)
        timer.sleepFor(ms: 2)

        // Clear stale flags
        _ = read32(REG_SR)
        _ = read32(REG_RHR)

        mode = .slave(address7: address7 & 0x7F)
        slaveState = .idle

        rxIndex = 0
        rxLen = 0
        slaveTxIndex = 0
        slaveTxLen = 0
    }

    /// Set bus speed (Master only)
    public func setClock(_ hz: U32) {
        if hz == 0 { return }

        var ckdiv: U32 = 0
        var cldiv: U32 = 0

        while true {
            let denom = U32(1) << ckdiv
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

    // ---------- Master write ----------

    public func beginTransmission(_ address7: UInt8) {
        masterTxAddress = address7 & 0x7F
        masterTxLen = 0
    }

    @discardableResult
    public func write(_ b: UInt8) -> Int {
        switch mode {
        case .master:
            if masterTxLen >= Self.BUFFER_LENGTH { return 0 }
            masterTxBuf[masterTxLen] = b
            masterTxLen += 1
            return 1

        case .slave:
            if !inSlaveRequestCallback { return 0 }
            if slaveTxLen >= Self.BUFFER_LENGTH { return 0 }
            slaveTxBuf[slaveTxLen] = b
            slaveTxLen += 1
            return 1

        case .idle:
            return 0
        }
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
        guard case .master = mode else { return 4 }
        if masterTxLen == 0 { return 0 }

        let dadr = (U32(masterTxAddress) << ATSAM3X8E.TWI.MMR_DADR_SHIFT) & ATSAM3X8E.TWI.MMR_DADR_MASK
        write32(REG_MMR, ATSAM3X8E.TWI.MMR_IADRSZ_NONE | dadr)
        write32(REG_IADR, 0)

        write32(REG_THR, U32(masterTxBuf[0]))
        if !waitTXRDY(timeoutMs: 20) { return nackOrTimeoutCode() }

        if masterTxLen > 1 {
            var i = 1
            while i < masterTxLen {
                write32(REG_THR, U32(masterTxBuf[i]))
                if !waitTXRDY(timeoutMs: 20) { return nackOrTimeoutCode(dataPhase: true) }
                i += 1
            }
        }

        if sendStop {
            write32(REG_CR, ATSAM3X8E.TWI.CR_STOP)
            if !waitTXCOMP(timeoutMs: 20) { return nackOrTimeoutCode() }
        }

        masterTxLen = 0
        return 0
    }

    // ---------- Master read ----------

    public func requestFrom(_ address7: UInt8, _ quantity: Int, _ sendStop: Bool = true) -> Int {
        guard case .master = mode else { return 0 }

        var q = quantity
        if q > Self.BUFFER_LENGTH { q = Self.BUFFER_LENGTH }
        if q <= 0 { return 0 }

        rxIndex = 0
        rxLen = 0

        let addr = UInt8(address7 & 0x7F)
        let dadr = (U32(addr) << ATSAM3X8E.TWI.MMR_DADR_SHIFT) & ATSAM3X8E.TWI.MMR_DADR_MASK
        write32(REG_MMR, ATSAM3X8E.TWI.MMR_IADRSZ_NONE | ATSAM3X8E.TWI.MMR_MREAD | dadr)
        write32(REG_IADR, 0)

        if q == 1 && sendStop {
            write32(REG_CR, ATSAM3X8E.TWI.CR_START | ATSAM3X8E.TWI.CR_STOP)
        } else {
            write32(REG_CR, ATSAM3X8E.TWI.CR_START)
        }

        var i = 0
        while i < q {
            if sendStop && (i == q - 1) && (q > 1) {
                write32(REG_CR, ATSAM3X8E.TWI.CR_STOP)
            }

            if !waitRXRDY(timeoutMs: 20) { return 0 }

            let b = UInt8(truncatingIfNeeded: read32(REG_RHR) & 0xFF)
            rxBuf[i] = b
            i += 1
        }

        if sendStop { _ = waitTXCOMP(timeoutMs: 20) }

        rxLen = q
        return q
    }

    // ---------- Shared read API (Master + Slave receive) ----------

    public func available() -> Int { rxLen - rxIndex }

    public func read() -> Int {
        if rxIndex >= rxLen { return -1 }
        let b = rxBuf[rxIndex]
        rxIndex += 1
        return Int(b)
    }

    // ---------- Slave callbacks ----------

    public func onReceive(_ cb: @escaping OnReceive) { onReceiveCb = cb }
    public func onRequest(_ cb: @escaping OnRequest) { onRequestCb = cb }

    /// Slave polling — call in a tight loop.
    public func poll() {
        guard case .slave = mode else { return }

        let s = sr()
        if (s & ATSAM3X8E.TWI.SR_SVACC) == 0 {
            return
        }

        // Direction: 1 = master reads from us
        if (s & ATSAM3X8E.TWI.SR_SVREAD) != 0 {
            if slaveState != .transmitting {
                // If we were receiving and master did repeated-start to read, finalize receive now
                if slaveState == .receiving, rxLen > 0 {
                    rxIndex = 0
                    onReceiveCb?(rxLen)
                }
                slaveState = .transmitting
                beginSlaveTransmit()
            }
            serviceSlaveTransmit()
            return
        }

        // master writes to us
        if slaveState != .receiving {
            slaveState = .receiving
            beginSlaveReceive()
        }
        serviceSlaveReceive()
    }

    // MARK: - Internals

    private func serviceSlaveReceive() {
        while true {
            let s = sr()

            if (s & ATSAM3X8E.TWI.SR_OVRE) != 0 {
                _ = read32(REG_RHR)
            }

            if (s & ATSAM3X8E.TWI.SR_RXRDY) != 0 {
                let b = UInt8(truncatingIfNeeded: read32(REG_RHR) & 0xFF)
                if rxLen < Self.BUFFER_LENGTH {
                    rxBuf[rxLen] = b
                    rxLen += 1
                }
                continue
            }

            if (s & ATSAM3X8E.TWI.SR_EOSACC) != 0 {
                if rxLen > 0 {
                    rxIndex = 0
                    onReceiveCb?(rxLen)
                }
                rearmSlavePeripheral()
                slaveState = .idle
                return
            }

            return
        }
    }

    private func serviceSlaveTransmit() {
        while true {
            let s = sr()

            // End of access OR master NACK -> finish
            if (s & ATSAM3X8E.TWI.SR_EOSACC) != 0 || (s & ATSAM3X8E.TWI.SR_NACK) != 0 {
                rearmSlavePeripheral()
                slaveState = .idle
                return
            }

            if (s & ATSAM3X8E.TWI.SR_TXRDY) != 0 {
                let out: UInt8
                if slaveTxIndex < slaveTxLen {
                    out = slaveTxBuf[slaveTxIndex]
                    slaveTxIndex += 1
                } else {
                    out = 0
                }
                write32(REG_THR, U32(out))
                continue
            }

            return
        }
    }

    @inline(__always)
    private func configurePinsAndClock() {
        pmcEnable(peripheralID: ATSAM3X8E.ID.PIOA)
        pmcEnable(peripheralID: ATSAM3X8E.ID.PIOB)

        switch bus {
        case .wire:
            configureWirePins_TWI1_PB12_PB13()
            pmcEnable(peripheralID: ATSAM3X8E.ID.TWI1)
        case .wire1:
            pmcEnable(peripheralID: ATSAM3X8E.ID.TWI0)
        }
    }

    @inline(__always)
    private func pmcEnable(peripheralID: U32) {
        write32(ATSAM3X8E.PMC.PCER0, U32(1) << peripheralID)
    }

    private func configureWirePins_TWI1_PB12_PB13() {
        let pioB = ATSAM3X8E.PIOB_BASE

        let sdaMask: U32 = U32(1) << 12
        let sclMask: U32 = U32(1) << 13
        let mask = sdaMask | sclMask

        let PIO_MDER_OFFSET: U32 = 0x0050 // Multi-driver Enable

        write32(pioB + ATSAM3X8E.PIOX.PUER_OFFSET, mask)
        write32(pioB + PIO_MDER_OFFSET, mask)

        let absrAddr = pioB + ATSAM3X8E.PIOX.ABSR_OFFSET
        write32(absrAddr, read32(absrAddr) & ~mask)

        write32(pioB + ATSAM3X8E.PIOX.PDR_OFFSET, mask)
    }

    @inline(__always)
    private func sr() -> U32 { read32(REG_SR) }

    private func nackOrTimeoutCode(dataPhase: Bool = false) -> UInt8 {
        let s = sr()
        if (s & ATSAM3X8E.TWI.SR_NACK) != 0 { return dataPhase ? 3 : 2 }
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

    // This is the key difference: re-arm the peripheral, not only buffers.
    @inline(__always)
    private func rearmSlavePeripheral() {
        // ArduinoCore-style: disable slave, enable slave, clear flags
        write32(REG_CR, ATSAM3X8E.TWI.CR_SVDIS)
        write32(REG_CR, ATSAM3X8E.TWI.CR_SVEN)
        _ = read32(REG_SR)
        _ = read32(REG_RHR)

        // Reset buffers for next access
        rxIndex = 0
        rxLen = 0
        slaveTxIndex = 0
        slaveTxLen = 0
    }

    private func beginSlaveReceive() {
        rxIndex = 0
        rxLen = 0
    }

    private func beginSlaveTransmit() {
        slaveTxIndex = 0
        slaveTxLen = 0

        inSlaveRequestCallback = true
        onRequestCb?()
        inSlaveRequestCallback = false

        // If user forgot to write anything, at least send a 0
        if slaveTxLen == 0 {
            inSlaveRequestCallback = true
            _ = write(UInt8(0))
            inSlaveRequestCallback = false
        }
    }
}