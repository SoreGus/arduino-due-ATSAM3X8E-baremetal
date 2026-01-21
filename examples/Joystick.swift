// Joystick.swift
//
// Example: Arduino Due Joystick Shield (Analog + Buttons)
//
// This file demonstrates how to use the SAM3X8E ADC and GPIO
// in pure bare-metal Embedded Swift, without Arduino core or HAL.
//
// Hardware assumed:
// - Arduino Due (ATSAM3X8E, Cortex-M3)
// - Common Joystick Shield:
//     • X axis  -> A0 (potentiometer)
//     • Y axis  -> A1 (potentiometer)
//     • Buttons -> Digital pins (typically D2–D7, depending on shield)
//
// Features shown:
// - Raw ADC reads (12-bit, 0–4095)
// - Stable analog input configuration
// - Digital input with pull-up
// - Simple polling loop (no interrupts)
// - UART output for debugging/telemetry
//
// Purpose:
// - Serve as a reference "main-like" example
// - Validate AnalogPIN + PIN drivers
// - Provide a clean base for games, UI navigation,
//   or custom input devices on bare metal
//
// Notes:
// - ADC values are read via ADC_LCDR (last converted value),
//   matching the official Arduino-SAM implementation.
// - No floating-point math is used (Embedded Swift safe).
// - Timing is cooperative via Timer.sleepFor(ms:).
//
// This file is intentionally simple and explicit,
// prioritizing clarity over abstraction.
//

// ---------- Helpers ----------

@inline(__always)
func decString(_ value: U16) -> String {
    // Max for ADC/DAC here is 4095 (4 digits), but keep 5 for safety.
    var v = value
    var buf = [UInt8](repeating: 0, count: 5)
    var i: Int = 0

    // Must handle 0 correctly.
    repeat {
        buf[i] = UInt8(v % 10) + 48 // '0'
        v /= 10
        i += 1
    } while v > 0

    var s = ""
    while i > 0 {
        i -= 1
        // ASCII digits only, so this is safe.
        s.append(Character(UnicodeScalar(buf[i])))
    }
    return s
}

// ---------- Main ----------

@_cdecl("main")
public func main() -> Never {
    let ctx = Board.initBoard()
    let serial = ctx.serial
    let timer  = ctx.timer

    // ADC clock correto (principalmente se clock cair em 4MHz)
    AnalogPIN.configure(mckHz: ctx.mckHz)

    // LEDs
    let led13 = PIN(13)
    let led7  = PIN(7)
    led13.output()
    led7.output()
    led7.on()

    // Botões
    let btnA = PIN(3)
    let btnB = PIN(4)
    let btnC = PIN(5)
    let btnD = PIN(6)

    btnA.inputPullup()
    btnB.inputPullup()
    btnC.inputPullup()
    btnD.inputPullup()

    var lastA = false
    var lastB = false
    var lastC = false
    var lastD = false

    // ADC
    let a0 = AnalogPIN(0) // A0
    let a1 = AnalogPIN(1) // A1

    serial.writeString("Ready (Buttons + ADC A0/A1)\r\n")

    while true {
        // ---- Botões ----
        let a = btnA.isLow()
        let b = btnB.isLow()
        let c = btnC.isLow()
        let d = btnD.isLow()

        if !lastA && a { serial.writeString("A\r\n"); led13.toggle(); led7.toggle() }
        if !lastB && b { serial.writeString("B\r\n"); led13.toggle(); led7.toggle() }
        if !lastC && c { serial.writeString("C\r\n"); led13.toggle(); led7.toggle() }
        if !lastD && d { serial.writeString("D\r\n"); led13.toggle(); led7.toggle() }

        lastA = a
        lastB = b
        lastC = c
        lastD = d

        // ---- ADC ----
        do {
            let v0 = try a0.readRaw()
            let v1 = try a1.readRaw()

            serial.writeString("A0=")
            serial.writeString(decString(v0))
            serial.writeString("  A1=")
            serial.writeString(decString(v1))
            serial.writeString("\r\n")
        } catch let e {
            _ = e
            serial.writeString("ADC error\r\n")
        }

        timer.sleepFor(ms: 100)
    }
}