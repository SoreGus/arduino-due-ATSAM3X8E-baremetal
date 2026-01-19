// PIN.swift — tiny GPIO wrapper (Arduino Due / ATSAM3X8E)
// No heap, no strings, no runtime tricks.

public struct PIN {
    private let pioBase: U32
    private let mask: U32

    // Minimal mapping for now:
    // - 13 or 27 -> Arduino Due LED "L" (PB27)
    public init(_ pin: U32) {
        if pin == 13 || pin == 27 {
            // Enable clock for PIOB once (idempotent write)
            write32(ATSAM3X8E.PMC.PCER0, U32(1) << ArduinoDue.LED_PIO_ID)

            self.pioBase = ArduinoDue.LED_PIO_BASE
            self.mask = ArduinoDue.LED_MASK

            // Take control as GPIO
            write32(pioBase + ATSAM3X8E.PIO.PER_OFFSET, mask)
        } else {
            // Unsupported pin for now -> trap early
            while true { bm_nop() }
        }
    }

    @inline(__always) public func output() {
        write32(pioBase + ATSAM3X8E.PIO.OER_OFFSET, mask)
    }

    @inline(__always) public func input() {
        write32(pioBase + ATSAM3X8E.PIO.ODR_OFFSET, mask)
    }

    @inline(__always) public func on() {
        write32(pioBase + ATSAM3X8E.PIO.SODR_OFFSET, mask)
    }

    @inline(__always) public func off() {
        write32(pioBase + ATSAM3X8E.PIO.CODR_OFFSET, mask)
    }

    @inline(__always) public func read() -> Bool {
        (read32(pioBase + ATSAM3X8E.PIO.PDSR_OFFSET) & mask) != 0
    }
}