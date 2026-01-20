// PIN.swift — SAM3X / Arduino Due GPIO wrapper (PIO)

public struct PIN {
    private let pioBase: U32
    private let pioID:   U32
    private let mask:    U32

    private let pioBase2: U32?
    private let pioID2:   U32?
    private let mask2:    U32?

    public init(_ digitalPin: U32) {
        guard let d = ArduinoDue.digital(digitalPin) else {
            while true { bm_nop() }
        }

        self.pioBase = d.pioBase
        self.pioID   = d.pioID
        self.mask    = d.mask

        self.pioBase2 = d.pioBase2
        self.pioID2   = d.pioID2
        self.mask2    = d.mask2

        // 1) Enable peripheral clock for the PIO controller(s)
        enablePIOClock(pioID)
        if let pioID2 { enablePIOClock(pioID2) }

        // 2) GPIO mode: PIO controls the pin
        write32(pioBase + ATSAM3X8E.PIO.PER_OFFSET, mask)
        if let pioBase2, let mask2 { write32(pioBase2 + ATSAM3X8E.PIO.PER_OFFSET, mask2) }

        // 3) Safe defaults
        write32(pioBase + ATSAM3X8E.PIO.IDR_OFFSET, mask)
        if let pioBase2, let mask2 { write32(pioBase2 + ATSAM3X8E.PIO.IDR_OFFSET, mask2) }

        write32(pioBase + ATSAM3X8E.PIOX.PUDR_OFFSET, mask)
        if let pioBase2, let mask2 { write32(pioBase2 + ATSAM3X8E.PIOX.PUDR_OFFSET, mask2) }

        write32(pioBase + ATSAM3X8E.PIO.MDDR_OFFSET, mask)
        if let pioBase2, let mask2 { write32(pioBase2 + ATSAM3X8E.PIO.MDDR_OFFSET, mask2) }

        write32(pioBase + ATSAM3X8E.PIO.IFDR_OFFSET, mask)
        if let pioBase2, let mask2 { write32(pioBase2 + ATSAM3X8E.PIO.IFDR_OFFSET, mask2) }
    }

    // MARK: - Modes

    @inline(__always)
    public func output(initialHigh: Bool = false) {
        write(initialHigh)
        write32(pioBase + ATSAM3X8E.PIO.OER_OFFSET, mask)
        if let pioBase2, let mask2 { write32(pioBase2 + ATSAM3X8E.PIO.OER_OFFSET, mask2) }
    }

    @inline(__always)
    public func input() {
        write32(pioBase + ATSAM3X8E.PIO.ODR_OFFSET, mask)
        if let pioBase2, let mask2 { write32(pioBase2 + ATSAM3X8E.PIO.ODR_OFFSET, mask2) }
    }

    @inline(__always)
    public func pullUp(_ enable: Bool) {
        if enable {
            write32(pioBase + ATSAM3X8E.PIOX.PUER_OFFSET, mask)
            if let pioBase2, let mask2 { write32(pioBase2 + ATSAM3X8E.PIOX.PUER_OFFSET, mask2) }
        } else {
            write32(pioBase + ATSAM3X8E.PIOX.PUDR_OFFSET, mask)
            if let pioBase2, let mask2 { write32(pioBase2 + ATSAM3X8E.PIOX.PUDR_OFFSET, mask2) }
        }
    }

    /// Input + pull-up (botão ativo em LOW)
    @inline(__always)
    public func inputPullup() {
        input()
        pullUp(true)
    }

    // MARK: - Read helpers

    /// Nivel físico do pino (PDSR). true = HIGH, false = LOW
    @inline(__always)
    public func read() -> Bool {
        let v1 = (read32(pioBase + ATSAM3X8E.PIO.PDSR_OFFSET) & mask) != 0
        if let pioBase2, let mask2 {
            let v2 = (read32(pioBase2 + ATSAM3X8E.PIO.PDSR_OFFSET) & mask2) != 0
            return v1 || v2
        }
        return v1
    }

    @inline(__always) public func isHigh() -> Bool { read() }
    @inline(__always) public func isLow()  -> Bool { !read() }

    // MARK: - Write

    @inline(__always)
    public func write(_ high: Bool) {
        if high {
            write32(pioBase + ATSAM3X8E.PIO.SODR_OFFSET, mask)
            if let pioBase2, let mask2 { write32(pioBase2 + ATSAM3X8E.PIO.SODR_OFFSET, mask2) }
        } else {
            write32(pioBase + ATSAM3X8E.PIO.CODR_OFFSET, mask)
            if let pioBase2, let mask2 { write32(pioBase2 + ATSAM3X8E.PIO.CODR_OFFSET, mask2) }
        }
    }

    @inline(__always) public func on()  { write(true) }
    @inline(__always) public func off() { write(false) }

    /// Estado latched de saída (ODSR). Melhor para toggle de LED.
    @inline(__always)
    public func readOutputLatch() -> Bool {
        let v1 = (read32(pioBase + ATSAM3X8E.PIO.ODSR_OFFSET) & mask) != 0
        if let pioBase2, let mask2 {
            let v2 = (read32(pioBase2 + ATSAM3X8E.PIO.ODSR_OFFSET) & mask2) != 0
            return v1 || v2
        }
        return v1
    }

    @inline(__always)
    public func toggle() {
        write(!readOutputLatch())
    }

    // MARK: - Extras

    @inline(__always)
    public func openDrain(_ enable: Bool) {
        if enable {
            write32(pioBase + ATSAM3X8E.PIO.MDER_OFFSET, mask)
            if let pioBase2, let mask2 { write32(pioBase2 + ATSAM3X8E.PIO.MDER_OFFSET, mask2) }
        } else {
            write32(pioBase + ATSAM3X8E.PIO.MDDR_OFFSET, mask)
            if let pioBase2, let mask2 { write32(pioBase2 + ATSAM3X8E.PIO.MDDR_OFFSET, mask2) }
        }
    }

    @inline(__always)
    public func inputFilter(_ enable: Bool) {
        if enable {
            write32(pioBase + ATSAM3X8E.PIO.IFER_OFFSET, mask)
            if let pioBase2, let mask2 { write32(pioBase2 + ATSAM3X8E.PIO.IFER_OFFSET, mask2) }
        } else {
            write32(pioBase + ATSAM3X8E.PIO.IFDR_OFFSET, mask)
            if let pioBase2, let mask2 { write32(pioBase2 + ATSAM3X8E.PIO.IFDR_OFFSET, mask2) }
        }
    }

    // MARK: - Clock enable

    @inline(__always)
    private func enablePIOClock(_ id: U32) {
        write32(ATSAM3X8E.PMC.PCER0, U32(1) << id)
    }
}