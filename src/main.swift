@_cdecl("main")
public func main() -> Never {
    write32(ATSAM3X8E.WDT.MR, ATSAM3X8E.WDT.WDT_MR_WDDIS)

    let ok = DueClock.init84MHz()
    let mck: U32 = ok ? 84_000_000 : 4_000_000
    let cpuHz: U32 = ok ? 84_000_000 : 4_000_000

    let serial = SerialUART(mckHz: mck)
    serial.begin(115_200)
    serial.writeString("BOOT\r\nclock_ok=")
    serial.writeString(ok ? "1" : "0")
    serial.writeString("\r\n")

    write32(ATSAM3X8E.PMC.PCER0, U32(1) << ArduinoDue.LED_PIO_ID)
    write32(ArduinoDue.LED_PIO_BASE + ATSAM3X8E.PIO.PER_OFFSET, ArduinoDue.LED_MASK)
    write32(ArduinoDue.LED_PIO_BASE + ATSAM3X8E.PIO.OER_OFFSET, ArduinoDue.LED_MASK)

    bm_enable_irq()
    let timer = Timer(cpuHz: cpuHz)
    timer.startTick1ms()

    // parâmetros
    let onMs: U32 = 1000
    let offMs: U32 = 1000
    let period: U32 = onMs &+ offMs

    // alinha no próximo múltiplo de 1000ms (opcional)
    var t0 = timer.millis()
    var next = (t0 / 1000) * 1000
    next &+= 1000

    while true {
        // ===== início do ciclo (LED ON) =====
        timer.sleepUntil(next)

        serial.writeString("tick=")
        serial.writeHex32(next)
        serial.writeString("\r\n")

        write32(ArduinoDue.LED_PIO_BASE + ATSAM3X8E.PIO.SODR_OFFSET, ArduinoDue.LED_MASK)

        // ===== LED OFF depois de 1000ms =====
        timer.sleepUntil(next &+ onMs)
        write32(ArduinoDue.LED_PIO_BASE + ATSAM3X8E.PIO.CODR_OFFSET, ArduinoDue.LED_MASK)

        // ===== próximo ciclo =====
        next &+= period
    }
}