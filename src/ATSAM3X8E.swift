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

    // Cortex-M3 SysTick (SCS)
    public static let SYST_CSR: U32 = 0xE000_E010
    public static let SYST_RVR: U32 = 0xE000_E014
    public static let SYST_CVR: U32 = 0xE000_E018

    // MARK: - Peripheral IDs (for PMC clock enable)

    public enum ID {
        public static let PIOA: U32 = 11
        public static let PIOB: U32 = 13
        public static let PIOC: U32 = 14
        public static let PIOD: U32 = 15
    }

    // MARK: - PMC (Power Management Controller)

    public enum PMC {
        // Registers
        public static let PCER0: U32 = ATSAM3X8E.PMC_BASE + 0x0010

        public static let CKGR_MOR:  U32 = ATSAM3X8E.PMC_BASE + 0x0020
        public static let CKGR_PLLAR: U32 = ATSAM3X8E.PMC_BASE + 0x0028
        public static let MCKR:      U32 = ATSAM3X8E.PMC_BASE + 0x0030
        public static let SR:        U32 = ATSAM3X8E.PMC_BASE + 0x0068

        // SR bits
        public static let SR_MOSCXTS: U32 = U32(1) << 0
        public static let SR_LOCKA:   U32 = U32(1) << 1
        public static let SR_MCKRDY:  U32 = U32(1) << 3

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
        public static let FMR_FWS_MASK: U32 = 0xF << 8
        public static let FMR_FWS_SHIFT: U32 = 8
    }

    // MARK: - PIO (Parallel I/O) offsets

    public enum PIO {
        public static let PER_OFFSET:  U32 = 0x0000 // PIO Enable Register
        public static let OER_OFFSET:  U32 = 0x0010 // Output Enable Register
        public static let SODR_OFFSET: U32 = 0x0030 // Set Output Data Register
        public static let CODR_OFFSET: U32 = 0x0034 // Clear Output Data Register
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