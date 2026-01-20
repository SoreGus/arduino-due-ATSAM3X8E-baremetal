// main.swift — Arduino Due as I2C MASTER talking to Arduino Giga SLAVE (0x42)
// Uses Board.initBoard() which already brings up: clock + UART + SysTick + I2C.

var timer: Timer?

@_cdecl("main")
public func main() -> Never {
    let ctx = Board.initBoard(i2cClockHz: 50_000)

    let serial = ctx.serial
    let i2c    = ctx.i2c
    timer      = ctx.timer

    serial.writeString("DUE I2C MASTER START\r\n")
    serial.writeString("I2C init OK\r\n")

    var tx0: UInt8 = 0x10
    var tx1: UInt8 = 0x20
    var tx2: UInt8 = 0x30

    while true {
        // WRITE
        serial.writeString("WRITE -> ")
        serialWriteHex8(serial, tx0); serial.writeString(" ")
        serialWriteHex8(serial, tx1); serial.writeString(" ")
        serialWriteHex8(serial, tx2); serial.writeString("\r\n")

        i2c.beginTransmission(0x42)
        _ = i2c.write(tx0)
        _ = i2c.write(tx1)
        _ = i2c.write(tx2)
        let err = i2c.endTransmission()

        if err != 0 {
            serial.writeString("WRITE FAIL err=")
            serialWriteDecU32(serial, U32(err))
            serial.writeString("\r\n")
            ctx.timer.sleepFor(ms: 500)
            continue
        }

        // READ 4 bytes
        let n = i2c.requestFrom(0x42, 4)
        serial.writeString("READ <- ")

        var got: U32 = 0
        while got < n {
            if i2c.available() > 0 {
                let v = i2c.read() // Int
                let b = UInt8(truncatingIfNeeded: v)
                serialWriteHex8(serial, b)
                serial.writeString(" ")
                got &+= 1
            }
        }
        serial.writeString("\r\n")

        tx0 &+= 1
        tx1 &+= 1
        tx2 &+= 1

        ctx.timer.sleepFor(ms: 500)
    }
}

// MARK: - Tiny local helpers (Embedded-Swift friendly)

@inline(__always)
private func hexNibbleASCII(_ v: UInt8) -> UInt8 {
    // returns ASCII code for 0..F
    if v < 10 { return 48 &+ v }           // '0' + v
    return 55 &+ v                          // 'A' (65) - 10 = 55
}

@inline(__always)
private func serialWriteHex8(_ serial: SerialUART, _ b: UInt8) {
    // Build 2-char string using a fixed [UInt8] and String(decoding:as:) (works in Embedded)
    var buf = [UInt8](repeating: 0, count: 2)
    buf[0] = hexNibbleASCII((b >> 4) & 0x0F)
    buf[1] = hexNibbleASCII(b & 0x0F)

    // This initializer is the one Embedded Swift usually keeps (no Foundation).
    let s = String(decoding: buf, as: Unicode.ASCII.self)
    serial.writeString(s)
}

private func serialWriteDecU32(_ serial: SerialUART, _ v: U32) {
    // Decimal print with fixed buffer, no fancy String APIs.
    if v == 0 {
        serial.writeString("0")
        return
    }

    var x = v
    var buf = [UInt8](repeating: 0, count: 10) // max for u32
    var n: Int = 0

    while x > 0 && n < 10 {
        let digit = UInt8(x % 10)
        buf[n] = 48 &+ digit
        x /= 10
        n += 1
    }

    // reverse-print
    while n > 0 {
        n -= 1
        let ch = String(decoding: [buf[n]], as: Unicode.ASCII.self)
        serial.writeString(ch)
    }
}