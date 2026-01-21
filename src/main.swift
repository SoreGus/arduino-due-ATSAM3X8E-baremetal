// main.swift — minimal USB debug loop (UART + Native USB)
//
// Ajustes:
// - Sem alocações grandes no loop.
// - “dump” de registradores após usb.begin() (isso mata 90% do debug de enum).
// - Não chama CDC TX se não estiver configurado.
// - Mantém RX opcional.
//
// Depende de:
// - Board.initBoard(baud:printBootBanner:)
// - SerialUART.writeByte, writeString
// - Timer.millis()
// - PIN
// - bm_nop
// - ATSAM3X8E+USB.swift (reg addresses / bits)
// - USBDevice (USB.swift)

@_cdecl("main")
public func main() -> Never {
    let ctx = Board.initBoard(baud: 115_200, printBootBanner: true)
    let serial = ctx.serial
    let timer  = ctx.timer

    // LED (D13)
    let led = PIN(13)
    led.output()
    led.off()

    serial.writeString("MAIN: start\r\n")

    // --- USB ---
    let usb = USBDevice()
    serial.writeString("USB: begin...\r\n")
    usb.begin()
    serial.writeString("USB: begin done\r\n")

    // Dump registradores críticos (se Mac não detecta, isso aqui aponta na hora)
    dumpUSBRegs(serial)

    var lastBeat: U32 = timer.millis()
    var lastReport: U32 = lastBeat
    let bootTime: U32 = lastBeat

    var beat = false
    var cdcTick: U32 = 0

    while true {
        usb.poll()

        // ---- RX: até 16 bytes/loop ----
        var readCount = 0
        while usb.cdcAvailable() > 0 && readCount < 16 {
            let v = usb.cdcRead()
            if v < 0 { break }

            let b = UInt8(truncatingIfNeeded: v)
            serial.writeString("CDC RX: 0x")
            serial.writeHex8(b)
            serial.writeString("\r\n")

            readCount &+= 1
        }

        let now = timer.millis()

        // ---- heartbeat 250ms ----
        if (now &- lastBeat) >= 250 {
            lastBeat = now
            beat.toggle()
            if beat { led.on() } else { led.off() }
        }

        // ---- report 1s ----
        if (now &- lastReport) >= 1000 {
            lastReport = now

            serial.writeString("T=")
            serial.writeU32(now)
            serial.writeString("  usb_poll_ok  cfg=")
            serial.writeByte(usb.isConfigured ? 49 : 48) // '1' : '0'
            serial.writeString("\r\n")

            if usb.isConfigured {
                cdcTick &+= 1

                usb.cdcWriteString("ping ")
                usb.cdcWriteU32(cdcTick)
                usb.cdcWriteString("\r\n")

                serial.writeString("CDC TX: ping ")
                serial.writeU32(cdcTick)
                serial.writeString("\r\n")
            } else {
                let dt = now &- bootTime
                serial.writeString("CDC: waiting enumeration (")
                serial.writeU32(dt)
                serial.writeString("ms)\r\n")

                // Dump leve a cada 2s enquanto não enumera
                if (dt % 2000) < 20 {
                    dumpUSBRegs(serial)
                }
            }
        }

        bm_nop()
    }
}

// MARK: - Debug dump

@inline(__always)
private func dumpUSBRegs(_ serial: SerialUART) {
    let ctrl    = read32(ATSAM3X8E.UOTGHS.CTRL)
    let devctrl = read32(ATSAM3X8E.UOTGHS.DEVCTRL)
    let devisr  = read32(ATSAM3X8E.UOTGHS.DEVISR)
    let devimr  = read32(ATSAM3X8E.UOTGHS.DEVIMR)
    let devaddr = read32(ATSAM3X8E.UOTGHS.DEVADDR)

    serial.writeString("USBREG CTRL=0x");    serial.writeHex32(ctrl)
    serial.writeString(" DEVCTRL=0x");       serial.writeHex32(devctrl)
    serial.writeString(" DEVISR=0x");        serial.writeHex32(devisr)
    serial.writeString(" DEVIMR=0x");        serial.writeHex32(devimr)
    serial.writeString(" DEVADDR=0x");       serial.writeHex32(devaddr)
    serial.writeString("\r\n")
}

// MARK: - UART helpers

extension SerialUART {
    public func writeU32(_ v: U32) {
        var x = v
        var buf = [UInt8](repeating: 0, count: 10)
        var i = 0
        repeat {
            buf[i] = UInt8(x % 10) + 48
            x /= 10
            i &+= 1
        } while x > 0

        while i > 0 {
            i &-= 1
            writeByte(buf[i])
        }
    }

    public func writeHex8(_ b: UInt8) {
        let hex: [UInt8] = Array("0123456789ABCDEF".utf8)
        writeByte(hex[Int((b >> 4) & 0x0F)])
        writeByte(hex[Int(b & 0x0F)])
    }

    public func writeHex32(_ v: U32) {
        writeHex8(UInt8(truncatingIfNeeded: (v >> 24) & 0xFF))
        writeHex8(UInt8(truncatingIfNeeded: (v >> 16) & 0xFF))
        writeHex8(UInt8(truncatingIfNeeded: (v >>  8) & 0xFF))
        writeHex8(UInt8(truncatingIfNeeded: (v >>  0) & 0xFF))
    }
}

// MARK: - USB helpers: send UInt32 as ASCII sem String

extension USBDevice {
    public func cdcWriteU32(_ v: U32) {
        var x = v
        var buf = [UInt8](repeating: 0, count: 10)
        var i = 0
        repeat {
            buf[i] = UInt8(x % 10) + 48
            x /= 10
            i &+= 1
        } while x > 0

        // escreve invertido sem criar String
        // (buf[0..i-1] contém dígitos invertidos)
        var out: [UInt8] = []
        out.reserveCapacity(i)
        while i > 0 {
            i &-= 1
            out.append(buf[i])
        }
        cdcWrite(out)
    }
}