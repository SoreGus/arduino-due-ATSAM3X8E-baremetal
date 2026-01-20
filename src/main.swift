// main.swift — Arduino Due (ATSAM3X8E) as I2C MASTER
// Sends the ASCII word "Hello" to SLAVE 0x42 every 1 second.
//
// Assumptions:
// - Board.initBoard() sets up clock, UART, SysTick
// - I2C is polling-based
// - i2c.begin() puts peripheral in MASTER mode

var gTimer: Timer?

@_cdecl("main")
public func main() -> Never {
    let ctx = Board.initBoard()

    let serial = ctx.serial
    let i2c    = ctx.i2c
    gTimer     = ctx.timer

    serial.writeString("DUE I2C MASTER START\r\n")

    // Start I2C as MASTER
    i2c.begin()
    i2c.setClock(100_000) // 100 kHz
    serial.writeString("I2C init OK\r\n")

    // Message to send (ASCII)
    let msg: [UInt8] = Array("Hello".utf8)

    while true {
        serial.writeString("WRITE -> ")

        // Print what we are about to send
        for b in msg {
            serial.writeString(String(decoding: [b], as: Unicode.ASCII.self))
        }
        serial.writeString("\r\n")

        // ---- I2C WRITE ----
        i2c.beginTransmission(0x42)

        for b in msg {
            _ = i2c.write(b)
        }

        let err = i2c.endTransmission(true)

        if err != 0 {
            serial.writeString("WRITE FAIL err=")
            serialWriteDecU32(serial, U32(err))
            serial.writeString("\r\n")
        }

        // Wait 1 second
        ctx.timer.sleepFor(ms: 1000)
    }
}

// MARK: - Small helpers

private func serialWriteDecU32(_ serial: SerialUART, _ v: U32) {
    if v == 0 {
        serial.writeString("0")
        return
    }

    var x = v
    var buf = [UInt8](repeating: 0, count: 10)
    var n: Int = 0

    while x > 0 && n < 10 {
        let digit = UInt8(x % 10)
        buf[n] = 48 &+ digit
        x /= 10
        n += 1
    }

    while n > 0 {
        n -= 1
        serial.writeString(
            String(decoding: [buf[n]], as: Unicode.ASCII.self)
        )
    }
}