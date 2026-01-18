// main.swift — Arduino Due (ATSAM3X8E) — Blink LED (PB27 / D13) in Embedded Swift

typealias U32 = UInt32

@_silgen_name("bm_nop")
func bm_nop() -> Void

@inline(__always)
func reg32(_ addr: U32) -> UnsafeMutablePointer<U32> {
    // Safe enough for bare-metal MMIO. Crashes if addr invalid (as expected).
    return UnsafeMutablePointer<U32>(bitPattern: UInt(addr))!
}

@inline(__always)
func write32(_ addr: U32, _ value: U32) {
    reg32(addr).pointee = value
}

@inline(__always)
func delay(_ n: U32) {
    var i = n
    while i != 0 {
        bm_nop()     // prevents the loop from being optimized away
        i &-= 1
    }
}

// --- SAM3X8E base addresses ---
let PMC_BASE: U32  = 0x400E_0600
let PIOB_BASE: U32 = 0x400E_1000
let WDT_BASE: U32  = 0x400E_1A50

// PMC
let PMC_PCER0: U32 = PMC_BASE + 0x0010   // Peripheral Clock Enable Register 0 (write-only)

// PIOB
let PIO_PER:  U32  = PIOB_BASE + 0x0000  // PIO Enable Register (write-only)
let PIO_OER:  U32  = PIOB_BASE + 0x0010  // Output Enable Register (write-only)
let PIO_SODR: U32  = PIOB_BASE + 0x0030  // Set Output Data Register (write-only)
let PIO_CODR: U32  = PIOB_BASE + 0x0034  // Clear Output Data Register (write-only)

// Watchdog (WDT)
let WDT_MR: U32 = WDT_BASE + 0x0004      // Mode Register

// LED "L" on Arduino Due is PB27 (Arduino pin 13)  [oai_citation:0‡Arduino Official Store](https://store.arduino.cc/products/arduino-due?srsltid=AfmBOoqNIh16na3ZZY1olItnImXDwoGJVwv4tm57YI4IAWSEzrZ-jiWX&utm_source=chatgpt.com)
let LED_PIN: U32  = 27
let LED_MASK: U32 = (1 << LED_PIN)

// Peripheral ID for PIOB on SAM3X is 13 (ID_PIOB)
let ID_PIOB: U32  = 13

@_cdecl("main")
public func main() -> Never {
    // Disable watchdog early (common cause of “runs but never blinks”)
    // WDDIS bit = 1 (bit 15)
    write32(WDT_MR, 1 << 15)

    // Enable clock for PIOB
    write32(PMC_PCER0, 1 << ID_PIOB)

    // Enable PIO control and set PB27 as output
    write32(PIO_PER, LED_MASK)
    write32(PIO_OER, LED_MASK)

    while true {
        write32(PIO_SODR, LED_MASK)   // LED ON
        delay(50_000)

        write32(PIO_CODR, LED_MASK)   // LED OFF
        delay(50_000)
    }
}