// Board.swift — clock + UART + SysTick + I2C (board services only)
//
// Responsibilities:
// - Disable watchdog
// - Configure system clock (84 MHz, fallback to 4 MHz)
// - Initialize UART for logging
// - Start SysTick (1 ms tick)
// - Create I2C object (no begin here)
//
// IMPORTANT:
// - This file MUST NOT know about Flash / EEFC / persistence.
// - EEFC is application-level logic and must live in main.swift or higher layers.
//
// Dependencies:
// - ATSAM3X8E.swift
// - MMIO.swift
// - Clock.swift
// - Timer.swift
// - SerialUART.swift
// - I2C.swift

public enum Board {

    // MARK: - Board context returned to the application

    public struct Context {
        public let clockOk: Bool
        public let mckHz: U32
        public let cpuHz: U32
        public let serial: SerialUART
        public let timer: Timer
        public let i2c: I2C
    }

    // MARK: - Board initialization

    @inline(__always)
    public static func initBoard(
        baud: U32 = 115_200,
        printBootBanner: Bool = true
    ) -> Context {

        // 1) Disable watchdog
        write32(ATSAM3X8E.WDT.MR, ATSAM3X8E.WDT.WDT_MR_WDDIS)

        // 2) Clock setup (84 MHz, fallback to 4 MHz)
        let ok = DueClock.init84MHz()
        let mck: U32 = ok ? 84_000_000 : 4_000_000
        let cpu: U32 = ok ? 84_000_000 : 4_000_000

        // 3) UART
        let serial = SerialUART(mckHz: mck)
        serial.begin(baud)

        if printBootBanner {
            serial.writeString("BOOT\r\nclock_ok=")
            serial.writeString(ok ? "1" : "0")
            serial.writeString("\r\nmck_hz=")
            serial.writeString(_board_decU32_toString(mck))
            serial.writeString("\r\n")
        }

        // 4) SysTick (1 ms tick)
        let timer = Timer(cpuHz: cpu)
        timer.startTick1ms()

        // IMPORTANT:
        // - Do NOT enable global IRQs here.
        // - main.swift decides if bm_enable_irq() is needed.
        // - This keeps polling-based drivers safe.
        //
        // bm_enable_irq()

        // 5) I2C object only (no begin here)
        let i2c = I2C(mckHz: mck, timer: timer, bus: .wire)

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

// MARK: - Local helpers (file-scoped, unique names)

// Small decimal U32 → String helper for boot logs.
// Kept local to avoid symbol collisions across Swift files.

@inline(__always)
private func _board_decU32_toString(_ value: U32) -> String {
    var v = value
    var buf = [UInt8](repeating: 0, count: 10)
    var i = 0

    repeat {
        buf[i] = UInt8(v % 10) + 48 // '0'
        v /= 10
        i += 1
    } while v > 0

    var s = ""
    while i > 0 {
        i -= 1
        s.append(Character(UnicodeScalar(buf[i])))
    }
    return s
}