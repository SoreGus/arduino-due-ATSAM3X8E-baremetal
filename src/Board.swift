// Board.swift — Arduino Due bring-up (clock + UART + SysTick + I2C)
// Keeps main.swift clean.
// Depends on: Clock.swift (DueClock), Timer.swift, SerialUART.swift, I2C.swift,
//            MMIO.swift, ATSAM3X8E.swift, ArduinoDue.swift.

public enum Board {
    public struct Context {
        public let clockOk: Bool
        public let mckHz: U32
        public let cpuHz: U32
        public let serial: SerialUART
        public let timer: Timer
        public let i2c: I2C
    }

    @inline(__always)
    public static func initBoard(
        baud: U32 = 115_200,
        printBootBanner: Bool = true,
        i2cClockHz: U32 = 100_000
    ) -> Context {
        // 1) Disable watchdog
        write32(ATSAM3X8E.WDT.MR, ATSAM3X8E.WDT.WDT_MR_WDDIS)

        // 2) Clock (84MHz). Fallback if it fails.
        let ok = DueClock.init84MHz()
        let mck: U32 = ok ? 84_000_000 : 4_000_000
        let cpu: U32 = ok ? 84_000_000 : 4_000_000

        // 3) UART
        let serial = SerialUART(mckHz: mck)
        serial.begin(baud)

        if printBootBanner {
            serial.writeString("BOOT\r\nclock_ok=")
            serial.writeString(ok ? "1" : "0")
            serial.writeString("\r\n")
        }

        // 4) SysTick (1ms) — configure first, then enable IRQ
        let timer = Timer(cpuHz: cpu)
        timer.startTick1ms()
        bm_enable_irq()

        // 5) I2C (Master) — default bus = ArduinoDue.Wire (pins 20/21 = TWI1)
        // Clock can be changed later via setClock(...)
        let i2c = I2C(mckHz: mck, timer: timer, bus: .wire)
        i2c.begin()
        i2c.setClock(i2cClockHz)

        return Context(
            clockOk: ok,
            mckHz: mck,
            cpuHz: cpu,
            serial: serial,
            timer: timer,
            i2c: i2c
        )
    }
}