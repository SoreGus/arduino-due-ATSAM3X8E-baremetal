// main.swift — Blink + UART (Arduino Due "Programming Port") using PIN.swift
// LED: 1000ms ON / 1000ms OFF (sem drift) + print no início do ciclo.

@inline(__always)
private func initBoard() -> (ok: Bool, serial: SerialUART, timer: Timer) {
    // Disable watchdog
    write32(ATSAM3X8E.WDT.MR, ATSAM3X8E.WDT.WDT_MR_WDDIS)

    // Clock (84MHz). Fallback if it fails.
    let ok = DueClock.init84MHz()
    let mck: U32 = ok ? 84_000_000 : 4_000_000
    let cpuHz: U32 = ok ? 84_000_000 : 4_000_000

    // UART + banner
    let serial = SerialUART(mckHz: mck)
    serial.beginWithBootBanner(115_200, clockOk: ok)

    // SysTick
    bm_enable_irq()
    let timer = Timer(cpuHz: cpuHz)
    timer.startTick1ms()

    return (ok, serial, timer)
}

@_cdecl("main")
public func main() -> Never {
    let (_, serial, timer) = initBoard()

    let led = PIN(27) // Arduino Due LED "L" (D13) = PB27
    led.output()

    let onMs: U32 = 1000
    let offMs: U32 = 1000
    let period: U32 = onMs &+ offMs

    // Align to the next 1000ms boundary (nice logs)
    let now = timer.millis()
    var next = (now / 1000) * 1000
    next &+= 1000

    while true {
        timer.sleepUntil(next)

        serial.writeString("tick=")
        serial.writeHex32(next)
        serial.writeString("\r\n")

        led.on()

        timer.sleepUntil(next &+ onMs)
        led.off()

        next &+= period
    }
}