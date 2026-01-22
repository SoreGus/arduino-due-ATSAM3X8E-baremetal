//
// ATSAM3X8E.swift — ATSAM3X8E (Arduino Due / Cortex-M3)
// Memory map + register addresses + bitfields (NO methods, NO logic).
//
// Rules:
// - This file is the single source of truth for hardware addresses/bitfields.
// - No runtime logic here.
//
// Depends on MMIO.swift defining: typealias U32 = UInt32
//

public enum ATSAM3X8E {

    // MARK: - Base addresses (peripheral memory map)

    public static let PMC_BASE:  U32 = 0x400E_0600

    public static let PIOA_BASE: U32 = 0x400E_0E00
    public static let PIOB_BASE: U32 = 0x400E_1000
    public static let PIOC_BASE: U32 = 0x400E_1200
    public static let PIOD_BASE: U32 = 0x400E_1400

    public static let WDT_BASE:  U32 = 0x400E_1A50

    public static let EEFC0_BASE: U32 = 0x400E_0A00
    public static let EEFC1_BASE: U32 = 0x400E_0C00

    // UART (Arduino Due "Programming Port" serial)
    public static let UART_BASE: U32 = 0x400E_0800

    // TWI (I2C)
    public static let TWI0_BASE: U32 = 0x4008_C000
    public static let TWI1_BASE: U32 = 0x4009_0000

    // Cortex-M3 SysTick (SCS)
    public static let SYST_CSR: U32 = 0xE000_E010
    public static let SYST_RVR: U32 = 0xE000_E014
    public static let SYST_CVR: U32 = 0xE000_E018

    // ADC / DACC
    public static let ADC_BASE:  U32 = 0x400C_0000
    public static let DACC_BASE: U32 = 0x400C_8000

    // MARK: - Flash memory map (code is mapped at 0x0008_0000)
    public static let FLASH_BASE: U32 = 0x0008_0000

    // MARK: - Peripheral IDs (for PMC clock enable)
    public enum ID {
        public static let UART: U32 = 8

        public static let PIOA: U32 = 11
        public static let PIOB: U32 = 12
        public static let PIOC: U32 = 13
        public static let PIOD: U32 = 14

        public static let TWI0: U32 = 22
        public static let TWI1: U32 = 23

        public static let ADC:  U32 = 37
        public static let DACC: U32 = 38
    }

    // MARK: - PMC (Power Management Controller)
    public enum PMC {
        // Registers
        public static let PCER0: U32 = ATSAM3X8E.PMC_BASE + 0x0010
        public static let PCDR0: U32 = ATSAM3X8E.PMC_BASE + 0x0014
        public static let PCSR0: U32 = ATSAM3X8E.PMC_BASE + 0x0018

        // IDs >= 32 use PCER1/PCDR1/PCSR1
        public static let PCER1: U32 = ATSAM3X8E.PMC_BASE + 0x0100
        public static let PCDR1: U32 = ATSAM3X8E.PMC_BASE + 0x0104
        public static let PCSR1: U32 = ATSAM3X8E.PMC_BASE + 0x0108

        public static let CKGR_MOR:   U32 = ATSAM3X8E.PMC_BASE + 0x0020
        public static let CKGR_PLLAR: U32 = ATSAM3X8E.PMC_BASE + 0x0028
        public static let MCKR:       U32 = ATSAM3X8E.PMC_BASE + 0x0030
        public static let SR:         U32 = ATSAM3X8E.PMC_BASE + 0x0068

        // SR bits
        public static let SR_MOSCXTS:  U32 = U32(1) << 0
        public static let SR_LOCKA:    U32 = U32(1) << 1
        public static let SR_MCKRDY:   U32 = U32(1) << 3
        public static let SR_MOSCSELS: U32 = U32(1) << 16

        // CKGR_MOR bits/fields
        public static let MOR_MOSCXTEN: U32 = U32(1) << 0

        public static let MOR_MOSCXTST_SHIFT: U32 = 8
        public static let MOR_MOSCXTST_MASK:  U32 = 0xFF << MOR_MOSCXTST_SHIFT

        public static let MOR_MOSCSEL: U32 = U32(1) << 24

        // Write-protect key: 0x37 at bits [23:16]
        public static let MOR_KEY: U32 = 0x37 << 16

        // PMC_MCKR fields
        public static let MCKR_CSS_MASK: U32 = 0x3
        public static let MCKR_CSS_PLLA: U32 = 2

        public static let MCKR_PRES_MASK: U32 = 0x7 << 4
        public static let MCKR_PRES_1:    U32 = 0 << 4
    }

    // MARK: - EEFC (Enhanced Embedded Flash Controller)
    public enum EEFC {
        // Common offsets
        public static let FMR_OFFSET: U32 = 0x00
        public static let FCR_OFFSET: U32 = 0x04
        public static let FSR_OFFSET: U32 = 0x08
        public static let FRR_OFFSET: U32 = 0x0C

        // FMR fields (Flash Wait States)
        public static let FMR_FWS_SHIFT: U32 = 8
        public static let FMR_FWS_MASK:  U32 = 0xF << FMR_FWS_SHIFT

        // FSR bits
        public static let FSR_FRDY:   U32 = U32(1) << 0
        public static let FSR_FCMDE:  U32 = U32(1) << 1
        public static let FSR_FLOCKE: U32 = U32(1) << 2

        // FCR fields
        public static let FCR_FCMD_MASK:   U32 = 0xFF
        public static let FCR_FARG_SHIFT:  U32 = 8
        public static let FCR_FKEY_SHIFT:  U32 = 24
        public static let FCR_FKEY_PASSWD: U32 = 0x5A << FCR_FKEY_SHIFT

        // Commands (FCMD)
        public static let FCMD_WP:  U32 = 0x01  // Write Page
        public static let FCMD_EWP: U32 = 0x03  // Erase Page and Write Page
    }

    // Absolute addresses for EEFC0 / EEFC1
    public enum EEFC0 {
        public static let FMR: U32 = ATSAM3X8E.EEFC0_BASE + ATSAM3X8E.EEFC.FMR_OFFSET
        public static let FCR: U32 = ATSAM3X8E.EEFC0_BASE + ATSAM3X8E.EEFC.FCR_OFFSET
        public static let FSR: U32 = ATSAM3X8E.EEFC0_BASE + ATSAM3X8E.EEFC.FSR_OFFSET
        public static let FRR: U32 = ATSAM3X8E.EEFC0_BASE + ATSAM3X8E.EEFC.FRR_OFFSET
    }

    public enum EEFC1 {
        public static let FMR: U32 = ATSAM3X8E.EEFC1_BASE + ATSAM3X8E.EEFC.FMR_OFFSET
        public static let FCR: U32 = ATSAM3X8E.EEFC1_BASE + ATSAM3X8E.EEFC.FCR_OFFSET
        public static let FSR: U32 = ATSAM3X8E.EEFC1_BASE + ATSAM3X8E.EEFC.FSR_OFFSET
        public static let FRR: U32 = ATSAM3X8E.EEFC1_BASE + ATSAM3X8E.EEFC.FRR_OFFSET
    }

    // MARK: - PIO (GPIO) offsets
    public enum PIO {
        public static let PER_OFFSET:  U32 = 0x0000
        public static let PDR_OFFSET:  U32 = 0x0004

        public static let OER_OFFSET:  U32 = 0x0010
        public static let ODR_OFFSET:  U32 = 0x0014

        public static let IFER_OFFSET: U32 = 0x0020
        public static let IFDR_OFFSET: U32 = 0x0024

        public static let SODR_OFFSET: U32 = 0x0030
        public static let CODR_OFFSET: U32 = 0x0034
        public static let ODSR_OFFSET: U32 = 0x0038
        public static let PDSR_OFFSET: U32 = 0x003C

        public static let IER_OFFSET:  U32 = 0x0040
        public static let IDR_OFFSET:  U32 = 0x0044
        public static let IMR_OFFSET:  U32 = 0x0048
        public static let ISR_OFFSET:  U32 = 0x004C

        public static let MDER_OFFSET: U32 = 0x0050
        public static let MDDR_OFFSET: U32 = 0x0054
    }

    public enum PIOX {
        public static let PDR_OFFSET:  U32 = 0x0004
        public static let ABSR_OFFSET: U32 = 0x0070

        public static let PUER_OFFSET: U32 = 0x0064
        public static let PUDR_OFFSET: U32 = 0x0060
    }

    // MARK: - ADC
    public enum ADC {
        public static let CR_OFFSET:   U32 = 0x00
        public static let MR_OFFSET:   U32 = 0x04
        public static let CHER_OFFSET: U32 = 0x10
        public static let CHDR_OFFSET: U32 = 0x14
        public static let CHSR_OFFSET: U32 = 0x18
        public static let LCDR_OFFSET: U32 = 0x20

        public static let IER_OFFSET:  U32 = 0x24
        public static let IDR_OFFSET:  U32 = 0x28
        public static let IMR_OFFSET:  U32 = 0x2C
        public static let ISR_OFFSET:  U32 = 0x30

        public static let CDR0_OFFSET: U32 = 0x50

        public static let CR:   U32 = ATSAM3X8E.ADC_BASE + CR_OFFSET
        public static let MR:   U32 = ATSAM3X8E.ADC_BASE + MR_OFFSET
        public static let CHER: U32 = ATSAM3X8E.ADC_BASE + CHER_OFFSET
        public static let CHDR: U32 = ATSAM3X8E.ADC_BASE + CHDR_OFFSET
        public static let CHSR: U32 = ATSAM3X8E.ADC_BASE + CHSR_OFFSET
        public static let LCDR: U32 = ATSAM3X8E.ADC_BASE + LCDR_OFFSET

        public static let IER:  U32 = ATSAM3X8E.ADC_BASE + IER_OFFSET
        public static let IDR:  U32 = ATSAM3X8E.ADC_BASE + IDR_OFFSET
        public static let IMR:  U32 = ATSAM3X8E.ADC_BASE + IMR_OFFSET
        public static let ISR:  U32 = ATSAM3X8E.ADC_BASE + ISR_OFFSET

        public static let CDR0: U32 = ATSAM3X8E.ADC_BASE + CDR0_OFFSET

        // Alias
        public static let SR: U32 = ISR

        // Bits/fields
        public static let CR_SWRST: U32 = U32(1) << 0
        public static let CR_START: U32 = U32(1) << 1

        public static let MR_PRESCAL_SHIFT: U32 = 8
        public static let MR_PRESCAL_MASK:  U32 = 0xFF << MR_PRESCAL_SHIFT

        public static let MR_STARTUP_SHIFT: U32 = 16
        public static let MR_STARTUP_MASK:  U32 = 0x0F << MR_STARTUP_SHIFT

        public static let MR_TRACKTIM_SHIFT: U32 = 24
        public static let MR_TRACKTIM_MASK:  U32 = 0x0F << MR_TRACKTIM_SHIFT

        public static let MR_TRANSFER_SHIFT: U32 = 28
        public static let MR_TRANSFER_MASK:  U32 = 0x03 << MR_TRANSFER_SHIFT

        public static let CDR_STRIDE: U32 = 4
        public static let CDR_12BIT_MASK: U32 = 0x0FFF
    }

    // MARK: - DACC
    public enum DACC {
        public static let CR_OFFSET:   U32 = 0x00
        public static let MR_OFFSET:   U32 = 0x04
        public static let CHER_OFFSET: U32 = 0x10
        public static let CDR_OFFSET:  U32 = 0x20
        public static let ISR_OFFSET:  U32 = 0x30

        public static let CR:   U32 = ATSAM3X8E.DACC_BASE + CR_OFFSET
        public static let MR:   U32 = ATSAM3X8E.DACC_BASE + MR_OFFSET
        public static let CHER: U32 = ATSAM3X8E.DACC_BASE + CHER_OFFSET
        public static let CDR:  U32 = ATSAM3X8E.DACC_BASE + CDR_OFFSET
        public static let ISR:  U32 = ATSAM3X8E.DACC_BASE + ISR_OFFSET

        public static let CR_SWRST: U32 = U32(1) << 0

        public static let MR_TRGEN_DIS: U32 = 0 << 0
        public static let MR_WORD_HALF: U32 = 0 << 4
        public static let MR_TAG_EN:    U32 = U32(1) << 20

        public static let ISR_TXRDY: U32 = U32(1) << 0
    }

    // MARK: - UART
    public enum UART {
        public static let CR:   U32 = ATSAM3X8E.UART_BASE + 0x0000
        public static let MR:   U32 = ATSAM3X8E.UART_BASE + 0x0004
        public static let IER:  U32 = ATSAM3X8E.UART_BASE + 0x0008
        public static let IDR:  U32 = ATSAM3X8E.UART_BASE + 0x000C
        public static let IMR:  U32 = ATSAM3X8E.UART_BASE + 0x0010
        public static let SR:   U32 = ATSAM3X8E.UART_BASE + 0x0014
        public static let RHR:  U32 = ATSAM3X8E.UART_BASE + 0x0018
        public static let THR:  U32 = ATSAM3X8E.UART_BASE + 0x001C
        public static let BRGR: U32 = ATSAM3X8E.UART_BASE + 0x0020

        public static let CR_RSTRX: U32 = U32(1) << 2
        public static let CR_RSTTX: U32 = U32(1) << 3
        public static let CR_RXEN:  U32 = U32(1) << 4
        public static let CR_RXDIS: U32 = U32(1) << 5
        public static let CR_TXEN:  U32 = U32(1) << 6
        public static let CR_TXDIS: U32 = U32(1) << 7

        public static let SR_RXRDY: U32 = U32(1) << 0
        public static let SR_TXRDY: U32 = U32(1) << 1
        public static let SR_OVRE:  U32 = U32(1) << 5
        public static let SR_FRAME: U32 = U32(1) << 6
        public static let SR_PARE:  U32 = U32(1) << 7

        public static let MR_PAR_SHIFT: U32 = 9
        public static let MR_PAR_MASK:  U32 = 0x7 << MR_PAR_SHIFT
        public static let MR_PAR_NONE:  U32 = 0x4 << MR_PAR_SHIFT

        public static let MR_CHMODE_SHIFT: U32 = 14
        public static let MR_CHMODE_MASK:  U32 = 0x3 << MR_CHMODE_SHIFT
        public static let MR_CHMODE_NORMAL: U32 = 0x0 << MR_CHMODE_SHIFT
    }

    public enum PIOA_UART {
        public static let RX_PIN: U32 = 8
        public static let TX_PIN: U32 = 9
        public static let RX_MASK: U32 = U32(1) << RX_PIN
        public static let TX_MASK: U32 = U32(1) << TX_PIN
        public static let MASK: U32 = RX_MASK | TX_MASK
    }

    // MARK: - TWI (I2C)
    public enum TWI {
        public static let CR_OFFSET:   U32 = 0x0000
        public static let MMR_OFFSET:  U32 = 0x0004
        public static let SMR_OFFSET:  U32 = 0x0008
        public static let IADR_OFFSET: U32 = 0x000C
        public static let CWGR_OFFSET: U32 = 0x0010

        public static let SR_OFFSET:   U32 = 0x0020
        public static let IER_OFFSET:  U32 = 0x0024
        public static let IDR_OFFSET:  U32 = 0x0028
        public static let IMR_OFFSET:  U32 = 0x002C
        public static let RHR_OFFSET:  U32 = 0x0030
        public static let THR_OFFSET:  U32 = 0x0034

        public static let PTCR_OFFSET: U32 = 0x0120
        public static let PTSR_OFFSET: U32 = 0x0124

        public enum TWI0 {
            public static let CR:   U32 = ATSAM3X8E.TWI0_BASE + TWI.CR_OFFSET
            public static let MMR:  U32 = ATSAM3X8E.TWI0_BASE + TWI.MMR_OFFSET
            public static let SMR:  U32 = ATSAM3X8E.TWI0_BASE + TWI.SMR_OFFSET
            public static let IADR: U32 = ATSAM3X8E.TWI0_BASE + TWI.IADR_OFFSET
            public static let CWGR: U32 = ATSAM3X8E.TWI0_BASE + TWI.CWGR_OFFSET

            public static let SR:   U32 = ATSAM3X8E.TWI0_BASE + TWI.SR_OFFSET
            public static let IER:  U32 = ATSAM3X8E.TWI0_BASE + TWI.IER_OFFSET
            public static let IDR:  U32 = ATSAM3X8E.TWI0_BASE + TWI.IDR_OFFSET
            public static let IMR:  U32 = ATSAM3X8E.TWI0_BASE + TWI.IMR_OFFSET
            public static let RHR:  U32 = ATSAM3X8E.TWI0_BASE + TWI.RHR_OFFSET
            public static let THR:  U32 = ATSAM3X8E.TWI0_BASE + TWI.THR_OFFSET

            public static let PTCR: U32 = ATSAM3X8E.TWI0_BASE + TWI.PTCR_OFFSET
            public static let PTSR: U32 = ATSAM3X8E.TWI0_BASE + TWI.PTSR_OFFSET
        }

        public enum TWI1 {
            public static let CR:   U32 = ATSAM3X8E.TWI1_BASE + TWI.CR_OFFSET
            public static let MMR:  U32 = ATSAM3X8E.TWI1_BASE + TWI.MMR_OFFSET
            public static let SMR:  U32 = ATSAM3X8E.TWI1_BASE + TWI.SMR_OFFSET
            public static let IADR: U32 = ATSAM3X8E.TWI1_BASE + TWI.IADR_OFFSET
            public static let CWGR: U32 = ATSAM3X8E.TWI1_BASE + TWI.CWGR_OFFSET

            public static let SR:   U32 = ATSAM3X8E.TWI1_BASE + TWI.SR_OFFSET
            public static let IER:  U32 = ATSAM3X8E.TWI1_BASE + TWI.IER_OFFSET
            public static let IDR:  U32 = ATSAM3X8E.TWI1_BASE + TWI.IDR_OFFSET
            public static let IMR:  U32 = ATSAM3X8E.TWI1_BASE + TWI.IMR_OFFSET
            public static let RHR:  U32 = ATSAM3X8E.TWI1_BASE + TWI.RHR_OFFSET
            public static let THR:  U32 = ATSAM3X8E.TWI1_BASE + TWI.THR_OFFSET

            public static let PTCR: U32 = ATSAM3X8E.TWI1_BASE + TWI.PTCR_OFFSET
            public static let PTSR: U32 = ATSAM3X8E.TWI1_BASE + TWI.PTSR_OFFSET
        }

        public static let CR_START: U32 = U32(1) << 0
        public static let CR_STOP:  U32 = U32(1) << 1
        public static let CR_MSEN:  U32 = U32(1) << 2
        public static let CR_MSDIS: U32 = U32(1) << 3
        public static let CR_SVEN:  U32 = U32(1) << 4
        public static let CR_SVDIS: U32 = U32(1) << 5
        public static let CR_QUICK: U32 = U32(1) << 6
        public static let CR_SWRST: U32 = U32(1) << 7

        public static let MMR_IADRSZ_SHIFT: U32 = 8
        public static let MMR_IADRSZ_MASK:  U32 = 0x3 << MMR_IADRSZ_SHIFT
        public static let MMR_IADRSZ_NONE:  U32 = 0x0 << MMR_IADRSZ_SHIFT
        public static let MMR_IADRSZ_1BYTE: U32 = 0x1 << MMR_IADRSZ_SHIFT
        public static let MMR_IADRSZ_2BYTE: U32 = 0x2 << MMR_IADRSZ_SHIFT
        public static let MMR_IADRSZ_3BYTE: U32 = 0x3 << MMR_IADRSZ_SHIFT

        public static let MMR_MREAD: U32 = U32(1) << 12

        public static let MMR_DADR_SHIFT: U32 = 16
        public static let MMR_DADR_MASK:  U32 = 0x7F << MMR_DADR_SHIFT

        public static let IADR_IADR_SHIFT: U32 = 0
        public static let IADR_IADR_MASK:  U32 = 0x00FF_FFFF << IADR_IADR_SHIFT

        public static let CWGR_CLDIV_SHIFT: U32 = 0
        public static let CWGR_CLDIV_MASK:  U32 = 0xFF << CWGR_CLDIV_SHIFT

        public static let CWGR_CHDIV_SHIFT: U32 = 8
        public static let CWGR_CHDIV_MASK:  U32 = 0xFF << CWGR_CHDIV_SHIFT

        public static let CWGR_CKDIV_SHIFT: U32 = 16
        public static let CWGR_CKDIV_MASK:  U32 = 0x7 << CWGR_CKDIV_SHIFT

        public static let SR_TXCOMP: U32 = U32(1) << 0
        public static let SR_RXRDY:  U32 = U32(1) << 1
        public static let SR_TXRDY:  U32 = U32(1) << 2
        public static let SR_SVREAD: U32 = U32(1) << 3
        public static let SR_SVACC:  U32 = U32(1) << 4
        public static let SR_GACC:   U32 = U32(1) << 5
        public static let SR_OVRE:   U32 = U32(1) << 6
        public static let SR_NACK:   U32 = U32(1) << 8
        public static let SR_ARBLST: U32 = U32(1) << 9
        public static let SR_SCLWS:  U32 = U32(1) << 10
        public static let SR_EOSACC: U32 = U32(1) << 11
        public static let SR_ENDRX:  U32 = U32(1) << 12
        public static let SR_ENDTX:  U32 = U32(1) << 13
        public static let SR_RXBUFF: U32 = U32(1) << 14
        public static let SR_TXBUFE: U32 = U32(1) << 15

        public static let RHR_RXDATA_MASK: U32 = 0xFF
        public static let THR_TXDATA_MASK: U32 = 0xFF
    }

    // MARK: - WDT
    public enum WDT {
        public static let MR: U32 = ATSAM3X8E.WDT_BASE + 0x0004
        public static let WDT_MR_WDDIS: U32 = U32(1) << 15
    }

    // MARK: - SysTick bits
    public enum SysTick {
        public static let CSR_ENABLE:  U32 = U32(1) << 0
        public static let CSR_TICKINT: U32 = U32(1) << 1
        public static let CSR_CLKSRC:  U32 = U32(1) << 2
    }

    // MARK: - Reserved persistent flash page (hardware facts only)
    public enum NVM {
        // Flash page geometry on SAM3X8E: 256-byte pages.
        public static let PAGE_SIZE: U32 = 256

        // Total flash is 512 KiB mapped ending at 0x0010_0000.
        // The last page address is 0x000F_FF00 (page-aligned).
        public static let PAGE_ADDR: U32 = 0x000F_FF00

        // Bank 1 has 256 KiB => 1024 pages at 256 bytes each => last index = 1023.
        public static let BANK1_PAGE_INDEX: U32 = 1023
    }
}