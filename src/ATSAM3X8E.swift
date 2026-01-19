// ATSAM3X8E.swift — Arduino Due (ATSAM3X8E / Cortex-M3)
// Memory map + register addresses + bitfields (NO methods, NO logic).
// Depends on MMIO.swift defining: typealias U32 = UInt32 (ou similar)

public enum ATSAM3X8E {
    // MARK: - Base addresses

    public static let PMC_BASE:  U32 = 0x400E_0600

    public static let PIOA_BASE: U32 = 0x400E_0E00
    public static let PIOB_BASE: U32 = 0x400E_1000
    public static let PIOC_BASE: U32 = 0x400E_1200
    public static let PIOD_BASE: U32 = 0x400E_1400

    public static let WDT_BASE:  U32 = 0x400E_1A50

    public static let EEFC0_BASE: U32 = 0x400E_0A00
    public static let EEFC1_BASE: U32 = 0x400E_0C00

    // ✅ UART (used for "Programming Port" USB-serial on Arduino Due)
    public static let UART_BASE: U32 = 0x400E_0800

    // Cortex-M3 SysTick (SCS)
    public static let SYST_CSR: U32 = 0xE000_E010
    public static let SYST_RVR: U32 = 0xE000_E014
    public static let SYST_CVR: U32 = 0xE000_E018

    // MARK: - Peripheral IDs (for PMC clock enable)

    public enum ID {
        public static let UART: U32 = 8

        public static let PIOA: U32 = 11
        public static let PIOB: U32 = 13
        public static let PIOC: U32 = 14
        public static let PIOD: U32 = 15
    }

    // MARK: - PMC (Power Management Controller)

    public enum PMC {
        // Registers
        public static let PCER0: U32 = ATSAM3X8E.PMC_BASE + 0x0010

        public static let CKGR_MOR:   U32 = ATSAM3X8E.PMC_BASE + 0x0020
        public static let CKGR_PLLAR: U32 = ATSAM3X8E.PMC_BASE + 0x0028
        public static let MCKR:       U32 = ATSAM3X8E.PMC_BASE + 0x0030
        public static let SR:         U32 = ATSAM3X8E.PMC_BASE + 0x0068

        // SR bits
        public static let SR_MOSCXTS:  U32 = U32(1) << 0
        public static let SR_LOCKA:    U32 = U32(1) << 1
        public static let SR_MCKRDY:   U32 = U32(1) << 3
        // ✅ (hardening) crystal selected as MAINCK (some sequences wait this)
        public static let SR_MOSCSELS: U32 = U32(1) << 16

        // CKGR_MOR bits/fields
        public static let MOR_MOSCXTEN: U32 = U32(1) << 0

        public static let MOR_MOSCXTST_SHIFT: U32 = 8
        public static let MOR_MOSCXTST_MASK:  U32 = 0xFF << MOR_MOSCXTST_SHIFT

        public static let MOR_MOSCSEL: U32 = U32(1) << 24

        // CKGR_MOR write-protect key: write 0x37 at bits [23:16]
        public static let MOR_KEY: U32 = 0x37 << 16

        // PMC_MCKR fields
        public static let MCKR_CSS_MASK: U32 = 0x3
        public static let MCKR_CSS_PLLA: U32 = 2

        public static let MCKR_PRES_MASK: U32 = 0x7 << 4
        public static let MCKR_PRES_1:    U32 = 0 << 4
    }

    // MARK: - EEFC (Flash Controller)

    public enum EEFC {
        // Registers (offsets)
        public static let FMR_OFFSET: U32 = 0x0000

        // EEFC_FMR fields
        // FWS typically bits [11:8] => mask 0xF << 8
        public static let FMR_FWS_MASK:  U32 = 0xF << 8
        public static let FMR_FWS_SHIFT: U32 = 8
    }

    // MARK: - PIO (Parallel I/O) offsets (basic GPIO)

    public enum PIO {
        public static let PER_OFFSET:  U32 = 0x0000 // PIO Enable Register
        public static let OER_OFFSET:  U32 = 0x0010 // Output Enable Register
        public static let ODR_OFFSET:  U32 = 0x0014 // Output Disable Register
        public static let SODR_OFFSET: U32 = 0x0030 // Set Output Data Register
        public static let CODR_OFFSET: U32 = 0x0034 // Clear Output Data Register
        public static let PDSR_OFFSET: U32 = 0x003C // Pin Data Status Register (read)
    }

    // MARK: - PIO (extra offsets for peripheral mux)

    public enum PIOX {
        public static let PDR_OFFSET:  U32 = 0x0004 // PIO Disable Register (hand over to peripheral)
        public static let ABSR_OFFSET: U32 = 0x0070 // Peripheral AB Select Register
        public static let PUER_OFFSET: U32 = 0x0064 // Pull-up Enable Register
    }

    // MARK: - UART (Programming Port serial) — register addresses + bitfields

    public enum UART {
        // Registers (absolute addresses)
        public static let CR:   U32 = ATSAM3X8E.UART_BASE + 0x0000
        public static let MR:   U32 = ATSAM3X8E.UART_BASE + 0x0004
        public static let IER:  U32 = ATSAM3X8E.UART_BASE + 0x0008
        public static let IDR:  U32 = ATSAM3X8E.UART_BASE + 0x000C
        public static let IMR:  U32 = ATSAM3X8E.UART_BASE + 0x0010
        public static let SR:   U32 = ATSAM3X8E.UART_BASE + 0x0014
        public static let RHR:  U32 = ATSAM3X8E.UART_BASE + 0x0018
        public static let THR:  U32 = ATSAM3X8E.UART_BASE + 0x001C
        public static let BRGR: U32 = ATSAM3X8E.UART_BASE + 0x0020

        // CR bits
        public static let CR_RSTRX: U32 = U32(1) << 2
        public static let CR_RSTTX: U32 = U32(1) << 3
        public static let CR_RXEN:  U32 = U32(1) << 4
        public static let CR_RXDIS: U32 = U32(1) << 5
        public static let CR_TXEN:  U32 = U32(1) << 6
        public static let CR_TXDIS: U32 = U32(1) << 7

        // SR bits
        public static let SR_RXRDY: U32 = U32(1) << 0
        public static let SR_TXRDY: U32 = U32(1) << 1
        public static let SR_OVRE:  U32 = U32(1) << 5
        public static let SR_FRAME: U32 = U32(1) << 6
        public static let SR_PARE:  U32 = U32(1) << 7

        // MR fields (8N1, normal channel mode)
        public static let MR_PAR_SHIFT: U32 = 9
        public static let MR_PAR_MASK:  U32 = 0x7 << MR_PAR_SHIFT
        public static let MR_PAR_NONE:  U32 = 0x4 << MR_PAR_SHIFT

        public static let MR_CHMODE_SHIFT: U32 = 14
        public static let MR_CHMODE_MASK:  U32 = 0x3 << MR_CHMODE_SHIFT
        public static let MR_CHMODE_NORMAL: U32 = 0x0 << MR_CHMODE_SHIFT
    }

    // MARK: - UART pin mapping (PA8/PA9) bitmasks

    public enum PIOA_UART {
        // UART uses PA8 (URXD) and PA9 (UTXD) on SAM3X8E.
        public static let RX_PIN: U32 = 8
        public static let TX_PIN: U32 = 9

        public static let RX_MASK: U32 = U32(1) << RX_PIN
        public static let TX_MASK: U32 = U32(1) << TX_PIN

        public static let MASK: U32 = RX_MASK | TX_MASK
    }

    // MARK: - WDT (Watchdog Timer)

    public enum WDT {
        public static let MR: U32 = ATSAM3X8E.WDT_BASE + 0x0004
        public static let WDT_MR_WDDIS: U32 = U32(1) << 15
    }

    // MARK: - SysTick (Cortex-M3)

    public enum SysTick {
        public static let CSR_ENABLE:  U32 = U32(1) << 0
        public static let CSR_TICKINT: U32 = U32(1) << 1
        public static let CSR_CLKSRC:  U32 = U32(1) << 2
    }
}

// MARK: - Board mapping (Arduino Due)

public enum ArduinoDue {
    // LED "L" (D13) is PB27 on Arduino Due.
    public static let LED_PIN:  U32 = 27
    public static let LED_MASK: U32 = U32(1) << LED_PIN

    public static let LED_PIO_BASE: U32 = ATSAM3X8E.PIOB_BASE
    public static let LED_PIO_ID:   U32 = ATSAM3X8E.ID.PIOB
}