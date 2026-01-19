// main.swift — Blink PB27/D13 using SysTick Timer (Arduino Due)

@_cdecl("main")
public func main() -> Never {
    // Disable watchdog
    write32(ATSAM3X8E.WDT.MR, ATSAM3X8E.WDT.WDT_MR_WDDIS)

    // ✅ Set clock ASAP (so everything after is “normal speed”)
    let ok = DueClock.init84MHz()
    if !ok {
        // If clock init failed, blink slow forever
        write32(ATSAM3X8E.PMC.PCER0, U32(1) << ArduinoDue.LED_PIO_ID)
        write32(ArduinoDue.LED_PIO_BASE + ATSAM3X8E.PIO.PER_OFFSET, ArduinoDue.LED_MASK)
        write32(ArduinoDue.LED_PIO_BASE + ATSAM3X8E.PIO.OER_OFFSET, ArduinoDue.LED_MASK)

        while true {
            write32(ArduinoDue.LED_PIO_BASE + ATSAM3X8E.PIO.SODR_OFFSET, ArduinoDue.LED_MASK)
            for _ in 0..<2_000_000 { bm_nop() }
            write32(ArduinoDue.LED_PIO_BASE + ATSAM3X8E.PIO.CODR_OFFSET, ArduinoDue.LED_MASK)
            for _ in 0..<2_000_000 { bm_nop() }
        }
    }

    // Enable PIOB clock + PB27 output
    write32(ATSAM3X8E.PMC.PCER0, U32(1) << ArduinoDue.LED_PIO_ID)
    write32(ArduinoDue.LED_PIO_BASE + ATSAM3X8E.PIO.PER_OFFSET, ArduinoDue.LED_MASK)
    write32(ArduinoDue.LED_PIO_BASE + ATSAM3X8E.PIO.OER_OFFSET, ArduinoDue.LED_MASK)

    bm_enable_irq()

    let timer = Timer(cpuHz: 84_000_000)
    timer.startTick1ms()

    while true {
        write32(ArduinoDue.LED_PIO_BASE + ATSAM3X8E.PIO.SODR_OFFSET, ArduinoDue.LED_MASK)
        timer.sleep(ms: 1000)
        write32(ArduinoDue.LED_PIO_BASE + ATSAM3X8E.PIO.CODR_OFFSET, ArduinoDue.LED_MASK)
        timer.sleep(ms: 1000)
    }
}