// PIN.swift — Generic GPIO wrapper for Arduino Due digital pins D0...D53.
// No heap, no strings.
// Depends on: ArduinoDue.swift mapping + ATSAM3X8E.swift + MMIO.swift

public struct PIN {
    private let pioBase: U32
    private let pioID: U32
    private let mask: U32

    private let pioBase2: U32?
    private let pioID2: U32?
    private let mask2: U32?

    public init(_ digitalPin: U32) {
        guard let d = ArduinoDue.digital(digitalPin) else {
            while true { bm_nop() }
        }

        self.pioBase = d.pioBase
        self.pioID = d.pioID
        self.mask = d.mask

        self.pioBase2 = d.pioBase2
        self.pioID2 = d.pioID2
        self.mask2 = d.mask2

        // Enable clocks (safe even if PCER0 behaves like "write-1-to-enable")
        write32(ATSAM3X8E.PMC.PCER0, U32(1) << pioID)
        if let pioID2 { write32(ATSAM3X8E.PMC.PCER0, U32(1) << pioID2) }

        // Take PIO control (GPIO). Use RMW to avoid clobber if register is RW in your environment.
        rmw_or(pioBase + ATSAM3X8E.PIO.PER_OFFSET, mask)
        if let pioBase2, let mask2 {
            rmw_or(pioBase2 + ATSAM3X8E.PIO.PER_OFFSET, mask2)
        }
    }

    @inline(__always)
    public func output() {
        // Preferred (SAM3X style): write-1-to-enable output
        write32(pioBase + ATSAM3X8E.PIO.OER_OFFSET, mask)

        // Safety net if the register behaves RW in your build/access path
        rmw_or(pioBase + ATSAM3X8E.PIO.OER_OFFSET, mask)

        if let pioBase2, let mask2 {
            write32(pioBase2 + ATSAM3X8E.PIO.OER_OFFSET, mask2)
            rmw_or(pioBase2 + ATSAM3X8E.PIO.OER_OFFSET, mask2)
        }
    }

    @inline(__always)
    public func input() {
        // Preferred (SAM3X style): write-1-to-disable output
        write32(pioBase + ATSAM3X8E.PIO.ODR_OFFSET, mask)

        // Safety net if you ended up with RW semantics somewhere:
        rmw_andnot(pioBase + ATSAM3X8E.PIO.OER_OFFSET, mask)

        if let pioBase2, let mask2 {
            write32(pioBase2 + ATSAM3X8E.PIO.ODR_OFFSET, mask2)
            rmw_andnot(pioBase2 + ATSAM3X8E.PIO.OER_OFFSET, mask2)
        }
    }

    @inline(__always)
    public func on() {
        // Set output data bit(s)
        write32(pioBase + ATSAM3X8E.PIO.SODR_OFFSET, mask)
        if let pioBase2, let mask2 {
            write32(pioBase2 + ATSAM3X8E.PIO.SODR_OFFSET, mask2)
        }
    }

    @inline(__always)
    public func off() {
        // Clear output data bit(s)
        write32(pioBase + ATSAM3X8E.PIO.CODR_OFFSET, mask)
        if let pioBase2, let mask2 {
            write32(pioBase2 + ATSAM3X8E.PIO.CODR_OFFSET, mask2)
        }
    }

    @inline(__always)
    public func read() -> Bool {
        let v1 = (read32(pioBase + ATSAM3X8E.PIO.PDSR_OFFSET) & mask) != 0
        if let pioBase2, let mask2 {
            let v2 = (read32(pioBase2 + ATSAM3X8E.PIO.PDSR_OFFSET) & mask2) != 0
            return v1 || v2
        }
        return v1
    }

    // MARK: - tiny RMW helpers (no heap)

    @inline(__always)
    private func rmw_or(_ addr: U32, _ bits: U32) {
        let v = read32(addr)
        write32(addr, v | bits)
    }

    @inline(__always)
    private func rmw_andnot(_ addr: U32, _ bits: U32) {
        let v = read32(addr)
        write32(addr, v & ~bits)
    }
}