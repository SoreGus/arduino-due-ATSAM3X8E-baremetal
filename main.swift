// main.swift — Blink PB27/D13 using SysTick Timer (Arduino Due)

private let PMC_BASE: U32  = 0x400E_0600
private let PIOB_BASE: U32 = 0x400E_1000
private let WDT_BASE: U32  = 0x400E_1A50

private let PMC_PCER0: U32 = PMC_BASE + 0x0010

private let PIO_PER:  U32  = PIOB_BASE + 0x0000
private let PIO_OER:  U32  = PIOB_BASE + 0x0010
private let PIO_SODR: U32  = PIOB_BASE + 0x0030
private let PIO_CODR: U32  = PIOB_BASE + 0x0034

private let WDT_MR: U32 = WDT_BASE + 0x0004

private let LED_PIN: U32  = 27
private let LED_MASK: U32 = (U32(1) << LED_PIN)
private let ID_PIOB: U32  = 13

@_cdecl("main")
public func main() -> Never {
    // Disable watchdog
    write32(WDT_MR, U32(1) << 15)

    // ✅ Set clock ASAP (so everything after is “normal speed”)
    let ok = DueClock.init84MHz()
    if !ok {
        // If clock init failed, blink slow forever
        write32(PMC_PCER0, U32(1) << ID_PIOB)
        write32(PIO_PER, LED_MASK)
        write32(PIO_OER, LED_MASK)

        while true {
            write32(PIO_SODR, LED_MASK); for _ in 0..<2_000_000 { bm_nop() }
            write32(PIO_CODR, LED_MASK); for _ in 0..<2_000_000 { bm_nop() }
        }
    }

    // Enable PIOB clock + PB27 output
    write32(PMC_PCER0, U32(1) << ID_PIOB)
    write32(PIO_PER, LED_MASK)
    write32(PIO_OER, LED_MASK)

    bm_enable_irq()

    let timer = Timer(cpuHz: 84_000_000)
    timer.startTick1ms()

    while true {
        write32(PIO_SODR, LED_MASK)
        timer.sleep(ms: 1000)
        write32(PIO_CODR, LED_MASK)
        timer.sleep(ms: 1000)
    }
}