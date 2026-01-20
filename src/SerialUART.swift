// SerialUART.swift — UART on ATSAM3X8E (Arduino Due "Programming Port" USB-serial)
// Minimal polling TX/RX. No interrupts.
// Depends on: MMIO.swift and ATSAM3X8E.swift.

public final class SerialUART {
    private let mckHz: U32

    public init(mckHz: U32) {
        self.mckHz = mckHz
    }

    public func begin(_ baud: U32) {
        // Enable UART peripheral clock (PCER0) — write-1-to-enable
        // NOTE: PCER0 is write-only; do NOT read-modify-write.
        write32(ATSAM3X8E.PMC.PCER0, U32(1) << ATSAM3X8E.ID.UART)

        // Switch PA8/PA9 to Peripheral A (UART), disable PIO control
        let pioa = ATSAM3X8E.PIOA_BASE

        // Hand over PA8/PA9 to peripheral (disable PIO control)
        write32(pioa + ATSAM3X8E.PIOX.PDR_OFFSET, ATSAM3X8E.PIOA_UART.MASK)

        // Select Peripheral A: ABSR bit=0 => A
        // ABSR is R/W so read-modify-write is fine here.
        clearBits32(pioa + ATSAM3X8E.PIOX.ABSR_OFFSET, ATSAM3X8E.PIOA_UART.MASK)

        // Optional pull-up on RX
        write32(pioa + ATSAM3X8E.PIOX.PUER_OFFSET, ATSAM3X8E.PIOA_UART.RX_MASK)

        // Reset + disable TX/RX
        write32(ATSAM3X8E.UART.CR, ATSAM3X8E.UART.CR_RSTRX | ATSAM3X8E.UART.CR_RSTTX)
        write32(ATSAM3X8E.UART.CR, ATSAM3X8E.UART.CR_RXDIS | ATSAM3X8E.UART.CR_TXDIS)

        // Mode: 8N1, normal
        var mr: U32 = 0
        mr = (mr & ~ATSAM3X8E.UART.MR_PAR_MASK) | ATSAM3X8E.UART.MR_PAR_NONE
        mr = (mr & ~ATSAM3X8E.UART.MR_CHMODE_MASK) | ATSAM3X8E.UART.MR_CHMODE_NORMAL
        write32(ATSAM3X8E.UART.MR, mr)

        // Baud: CD = MCK / (16 * baud)
        // Add rounding to reduce error on some baud rates.
        let denom = 16 * baud
        let cd = (mckHz + (denom / 2)) / denom
        write32(ATSAM3X8E.UART.BRGR, cd)

        // Enable TX/RX
        write32(ATSAM3X8E.UART.CR, ATSAM3X8E.UART.CR_RXEN | ATSAM3X8E.UART.CR_TXEN)
    }

    // Init + minimal banner (no String interpolation)
    @inline(__always)
    public func beginWithBootBanner(_ baud: U32, clockOk: Bool) {
        begin(baud)
        writeString("BOOT\r\nclock_ok=")
        writeString(clockOk ? "1" : "0")
        writeString("\r\n")
    }

    @inline(__always)
    public func writeByte(_ b: U8) {
        while (read32(ATSAM3X8E.UART.SR) & ATSAM3X8E.UART.SR_TXRDY) == 0 {
            bm_nop()
        }
        write32(ATSAM3X8E.UART.THR, U32(b))
    }

    public func writeString(_ s: String) {
        for u in s.utf8 {
            if u == 10 { writeByte(13) } // \n -> \r\n
            writeByte(u)
        }
    }

    // Hex print sem divisao (nao puxa __aeabi_uldivmod)
    public func writeHex32(_ v: U32, prefix: Bool = true) {
        if prefix { writeString("0x") }
        let hex: [U8] = Array("0123456789ABCDEF".utf8)

        var shift: U32 = 28
        while true {
            let nib = Int((v >> shift) & 0xF)
            writeByte(hex[nib])
            if shift == 0 { break }
            shift &-= 4
        }
    }

    // Returns: 0...255 if byte available, or -1 if none
    @inline(__always)
    public func readByteNonBlocking() -> Int32 {
        if (read32(ATSAM3X8E.UART.SR) & ATSAM3X8E.UART.SR_RXRDY) != 0 {
            return Int32(read32(ATSAM3X8E.UART.RHR) & 0xFF)
        }
        return -1
    }
}