// main.swift — Arduino Due (ATSAM3X8E) as I2C MASTER talking to SLAVE 0x42
// Uses Board.initBoard() which brings up: clock + UART + SysTick + I2C object (NOT started).
//
// Requirements:
// - Board.swift must create ctx.i2c but NOT call i2c.begin() automatically (as you already changed).
// - I2C.swift must support master begin(), setClock(), beginTransmission(), write(), endTransmission(), requestFrom().

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
    i2c.setClock(100_000) // 100 kHz (bem estável)
    serial.writeString("I2C init OK\r\n")

    var tx0: UInt8 = 0x10
    var tx1: UInt8 = 0x20
    var tx2: UInt8 = 0x30

    while true {
        // ---- WRITE ----
        serial.writeString("WRITE -> ")
        serialWriteHex8(serial, tx0); serial.writeString(" ")
        serialWriteHex8(serial, tx1); serial.writeString(" ")
        serialWriteHex8(serial, tx2); serial.writeString(" ")

        i2c.beginTransmission(0x42)
        _ = i2c.write(tx0)
        _ = i2c.write(tx1)
        _ = i2c.write(tx2)
        let err = i2c.endTransmission(true)

        if err != 0 {
            serial.writeString("| WRITE FAIL err=")
            serialWriteDecU32(serial, U32(err))
            serial.writeString("\r\n")
            ctx.timer.sleepFor(ms: 500)
            continue
        }

        // Pequena janela para o SLAVE processar onReceive antes do onRequest
        // (equivalente ao delayMicroseconds(200) no Arduino)
        spinDelayUs(ctx.timer, 250)

        // ---- READ ----
        let n = i2c.requestFrom(0x42, 4, true)

        serial.writeString("| READ <- ")
        var got: Int = 0
        while got < n {
            if i2c.available() > 0 {
                let v = i2c.read()
                if v >= 0 {
                    let b = UInt8(truncatingIfNeeded: v)
                    serialWriteHex8(serial, b)
                    serial.writeString(" ")
                    got += 1
                }
            }
        }
        serial.writeString("\r\n")

        // Incrementa padrão
        tx0 &+= 1
        tx1 &+= 1
        tx2 &+= 1

        ctx.timer.sleepFor(ms: 500)
    }
}

// MARK: - Helpers (Embedded-Swift friendly)

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
    if v == 0 { serial.writeString("0"); return }

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
        serial.writeString(String(decoding: [buf[n]], as: Unicode.ASCII.self))
    }
}

/// Busy wait in microseconds using Timer.millis() granularity + small NOP loop.
/// Since we only need ~200-300us, we do a calibrated-ish spin.
/// (Good enough for the "gap" between write and read.)
@inline(__always)
private func spinDelayUs(_ timer: Timer, _ us: U32) {
    // crude: ~1us per 20 nops (depends on cpu). We don't need precision.
    // make it bigger rather than smaller.
    var loops: U32 = us &* 30
    while loops > 0 {
        bm_nop()
        loops &-= 1
    }
}