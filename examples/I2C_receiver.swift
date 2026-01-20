// main.swift — Arduino Due (ATSAM3X8E) as I2C SLAVE (0x42) responding to Arduino Giga MASTER
// Polling-based slave: MUST call i2c.poll() as fast as possible.
//
// Key fix vs your version:
// - DO NOT print inside onReceive/onRequest (can break timing / UART can steal time).
// - Callback only updates shared state.
// - Main loop prints status periodically (safe).
//
// Expected behavior:
// - Giga stops showing err=2 (NACK) once Due is running.
// - Due prints rxCount increasing and counter changing.

var gTimer: Timer?

@_cdecl("main")
public func main() -> Never {
    let ctx = Board.initBoard()

    let serial = ctx.serial
    let i2c    = ctx.i2c
    gTimer     = ctx.timer

    serial.writeString("DUE I2C SLAVE START\r\n")

    // Shared state (updated by callbacks)
    var counter: UInt8 = 0
    var rxCount: U32 = 0
    var txCount: U32 = 0

    // Configure as SLAVE address 0x42 (7-bit)
    i2c.begin(0x42)

    // Master wrote data to us
    i2c.onReceive { _ in
        while i2c.available() > 0 {
            let v = i2c.read()
            if v >= 0 { counter = UInt8(truncatingIfNeeded: v) }
        }
        rxCount &+= 1
    }

    // Master is requesting data from us
    i2c.onRequest {
        // Keep it tiny; just push bytes
        _ = i2c.write(counter)
        _ = i2c.write(counter &+ 1)
        _ = i2c.write(counter &+ 2)
        _ = i2c.write(counter &+ 3)
        txCount &+= 1
    }

    serial.writeString("I2C slave init OK\r\n")

    // Periodic print (outside callbacks)
    var lastPrint: U32 = 0

    while true {
        i2c.poll()

        let now = ctx.timer.millis()
        if now &- lastPrint >= 500 {
            lastPrint = now

            serial.writeString("rxCount=")
            serialWriteDecU32(serial, rxCount)
            serial.writeString(" txCount=")
            serialWriteDecU32(serial, txCount)
            serial.writeString(" counter=0x")
            serialWriteHex8(serial, counter)
            serial.writeString("\r\n")
        }

        bm_nop()
    }
}

// MARK: - Tiny helpers (Embedded-Swift friendly)

@inline(__always)
private func hexNibbleASCII(_ v: UInt8) -> UInt8 {
    if v < 10 { return 48 &+ v }  // '0'
    return 55 &+ v                // 'A' - 10
}

@inline(__always)
private func serialWriteHex8(_ serial: SerialUART, _ b: UInt8) {
    var buf = [UInt8](repeating: 0, count: 2)
    buf[0] = hexNibbleASCII((b >> 4) & 0x0F)
    buf[1] = hexNibbleASCII(b & 0x0F)
    serial.writeString(String(decoding: buf, as: Unicode.ASCII.self))
}

private func serialWriteDecU32(_ serial: SerialUART, _ v: U32) {
    if v == 0 {
        serial.writeString("0")
        return
    }

    var x = v
    var buf = [UInt8](repeating: 0, count: 10) // u32 max digits
    var n: Int = 0

    while x > 0 && n < 10 {
        let digit = UInt8(x % 10)
        buf[n] = 48 &+ digit
        x /= 10
        n += 1
    }

    while n > 0 {
        n -= 1
        serial.writeString(String(decoding: [buf[n]], as: Unicode.ASCII.self))
    }
}