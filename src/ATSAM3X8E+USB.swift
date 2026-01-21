// ATSAM3X8E+USB.swift
//
// Canonical USB register map for SAM3X (Arduino Due Native USB = UOTGHS).
// Alinhado com o layout típico dos headers CMSIS/ASF do SAM3X (component_uotghs.h + instance_uotghs.h).
//
// Observação importante:
// - Os *endereços* e *offsets* abaixo são os do UOTGHS do SAM3X (0x400A_C000).
// - Os *bitfields* de DEVEPTCFG/DEVEPTISR/DEVEPTICR seguem o padrão Atmel UOTGHS/UDPHS
//   usado no ArduinoCore-sam (ASF). Se você estiver com headers diferentes, mantenha os offsets,
//   e ajuste apenas máscaras/posições conforme o seu component_uotghs.h.

public extension ATSAM3X8E {

    // UOTGHS peripheral base address (SAM3X)
    static let UOTGHS_BASE: U32 = 0x400A_C000

    // Peripheral ID (SAM3X IRQ list: UOTGHS_IRQn == 40)
    enum USBConst {
        static let PERIPH_ID_UOTGHS: U32 = 40
    }
}

public extension ATSAM3X8E.ID {
    static let UOTGHS: U32 = ATSAM3X8E.USBConst.PERIPH_ID_UOTGHS
}

// MARK: - PMC bits/regs needed for USB clocks (UPLL + USB clock selection)
public extension ATSAM3X8E {

    enum PMC_USBX {
        // component_pmc.h offsets
        public static let CKGR_UCKR: U32 = ATSAM3X8E.PMC_BASE + 0x001C
        public static let SR:       U32 = ATSAM3X8E.PMC_BASE + 0x0068
        public static let USB:      U32 = ATSAM3X8E.PMC_BASE + 0x0038
        public static let SCER:     U32 = ATSAM3X8E.PMC_BASE + 0x0000

        // CKGR_UCKR
        public static let UCKR_UPLLEN: U32 = (1 << 16)
        public static let UCKR_UPLLCOUNT_SHIFT: U32 = 20
        public static let UCKR_UPLLCOUNT_MASK:  U32 = (0xF << UCKR_UPLLCOUNT_SHIFT)

        // PMC_SR
        public static let SR_LOCKU: U32 = (1 << 6)

        // PMC_USB
        public static let USB_USBS: U32 = (1 << 0) // select UPLL for USB clock
        public static let USB_USBDIV_SHIFT: U32 = 8
        public static let USB_USBDIV_MASK:  U32 = (0xF << USB_USBDIV_SHIFT)

        // PMC_SCER
        public static let SCER_UOTGCLK: U32 = (1 << 5)
    }
}

// MARK: - UOTGHS core + device registers (component_uotghs.h layout)
public extension ATSAM3X8E {

    enum UOTGHS {

        // MARK: Global regs (device/host shared)
        public static let CTRL:   U32 = ATSAM3X8E.UOTGHS_BASE + 0x0000
        public static let DEVEPT: U32 = ATSAM3X8E.UOTGHS_BASE + 0x0004
        public static let DEVADDR: U32 = ATSAM3X8E.UOTGHS_BASE + 0x0008
        public static let DEVCTRL: U32 = ATSAM3X8E.UOTGHS_BASE + 0x000C

        // CTRL bits
        public static let CTRL_USBE:   U32 = (1 << 0)   // USB enable
        public static let CTRL_UIMOD:  U32 = (1 << 1)   // 1=device, 0=host
        public static let CTRL_FRZCLK: U32 = (1 << 14)  // freeze USB clock

        // DEVADDR fields
        // UADD [6:0], ADDEN [7]
        public static let DEVADDR_UADD_MASK: U32 = 0x7F
        public static let DEVADDR_ADDEN:     U32 = (1 << 7)

        // DEVCTRL bits (device control)
        public static let DEVCTRL_DETACH: U32 = (1 << 0) // 1=detach (pull-up off)
        // Nota: em SAM UOTGHS, “address enable” é DEVADDR.ADDEN.
        // Mantenho DEVCTRL_ADDEN aqui só se você quiser compat/legado, mas use DEVADDR_ADDEN.
        public static let DEVCTRL_ADDEN:  U32 = (1 << 1)

        // MARK: Device interrupts
        public static let DEVISR:  U32 = ATSAM3X8E.UOTGHS_BASE + 0x0010
        public static let DEVIER:  U32 = ATSAM3X8E.UOTGHS_BASE + 0x0014
        public static let DEVIDR:  U32 = ATSAM3X8E.UOTGHS_BASE + 0x0018
        public static let DEVIMR:  U32 = ATSAM3X8E.UOTGHS_BASE + 0x001C
        public static let DEVICR:  U32 = ATSAM3X8E.UOTGHS_BASE + 0x0020

        // DEVISR / DEVIER / DEVICR bits
        public static let DEVISR_EORST: U32 = (1 << 3)  // End of reset
        public static let DEVISR_SUSP:  U32 = (1 << 0)  // Suspend (useful to early-exit waits)

        // MARK: Endpoint register arrays (device endpoints)
        // Stride = 0x20 per endpoint
        @inline(__always) public static func DEVEPTCFG(_ ep: U32) -> U32 { ATSAM3X8E.UOTGHS_BASE + 0x0100 + ep * 0x20 }
        @inline(__always) public static func DEVEPTISR(_ ep: U32) -> U32 { ATSAM3X8E.UOTGHS_BASE + 0x0130 + ep * 0x20 }
        @inline(__always) public static func DEVEPTICR(_ ep: U32) -> U32 { ATSAM3X8E.UOTGHS_BASE + 0x0160 + ep * 0x20 }
        @inline(__always) public static func DEVEPTIFR(_ ep: U32) -> U32 { ATSAM3X8E.UOTGHS_BASE + 0x0190 + ep * 0x20 }
        @inline(__always) public static func DEVEPTIER(_ ep: U32) -> U32 { ATSAM3X8E.UOTGHS_BASE + 0x01C0 + ep * 0x20 }
        @inline(__always) public static func DEVEPTIDR(_ ep: U32) -> U32 { ATSAM3X8E.UOTGHS_BASE + 0x01F0 + ep * 0x20 }
        @inline(__always) public static func DEVEPTIMR(_ ep: U32) -> U32 { ATSAM3X8E.UOTGHS_BASE + 0x0220 + ep * 0x20 }

        // MARK: DEVEPT (endpoint enable bits)
        @inline(__always) public static func EPEN(_ ep: U32) -> U32 { (1 << ep) }

        // MARK: Endpoint ISR flags (common)
        public static let EPISR_RXSTPI: U32 = (1 << 0)   // SETUP received
        public static let EPISR_TXINI:  U32 = (1 << 1)   // IN ready
        public static let EPISR_RXOUTI: U32 = (1 << 2)   // OUT received
        public static let EPISR_STALLEDI: U32 = (1 << 6) // STALL sent/active (varia em alguns headers)

        // Config OK (after ALLOC)
        public static let EPISR_CFGOK: U32 = (1 << 18)

        // Byte count field (BYCT) for OUT/SETUP data (típico: bits [30:20])
        public static let EPISR_BYCT_SHIFT: U32 = 20
        public static let EPISR_BYCT_MASK:  U32 = (0x7FF << EPISR_BYCT_SHIFT)

        // MARK: DEVEPTICR clear bits (ack)
        // Em UOTGHS, o ICR costuma usar “*_C” para limpar.
        // Aqui usamos a convenção: escrever o mesmo bit do ISR para limpar.
        public static let EPICR_RXSTPIC: U32 = EPISR_RXSTPI
        public static let EPICR_TXINIC:  U32 = EPISR_TXINI
        public static let EPICR_RXOUTIC: U32 = EPISR_RXOUTI

        // MARK: DEVEPTIFR (force)
        // Nem sempre necessário para um driver mínimo.
        public static let EPIFR_RXOUTIS: U32 = EPISR_RXOUTI
        public static let EPIFR_TXINIS:  U32 = EPISR_TXINI

        // MARK: DEVEPTCFG fields (típico UOTGHS/UDPHS da Atmel)
        //
        // - ALLOC: solicita alocação do endpoint no DPRAM
        // - EPTYPE: type do endpoint
        // - EPSIZE: tamanho (8/16/32/64/128/256/512/1024)
        // - EPDIR: direção (IN=1, OUT=0) para não-control
        // - EPBK: número de bancos (1/2/3) — para começar use 1 banco
        //
        // Se o seu component_uotghs.h divergir, ajuste estes shifts/masks.
        public static let DEVEPTCFG_ALLOC: U32 = (1 << 1)

        public static let DEVEPTCFG_EPBK_SHIFT: U32 = 2
        public static let DEVEPTCFG_EPBK_MASK:  U32 = (0x3 << DEVEPTCFG_EPBK_SHIFT)
        public static let DEVEPTCFG_EPBK_1_BANK: U32 = (0x0 << DEVEPTCFG_EPBK_SHIFT)
        public static let DEVEPTCFG_EPBK_2_BANK: U32 = (0x1 << DEVEPTCFG_EPBK_SHIFT)

        public static let DEVEPTCFG_EPSIZE_SHIFT: U32 = 4
        public static let DEVEPTCFG_EPSIZE_MASK:  U32 = (0x7 << DEVEPTCFG_EPSIZE_SHIFT)
        public static let DEVEPTCFG_EPSIZE_8_BYTE:    U32 = (0x0 << DEVEPTCFG_EPSIZE_SHIFT)
        public static let DEVEPTCFG_EPSIZE_16_BYTE:   U32 = (0x1 << DEVEPTCFG_EPSIZE_SHIFT)
        public static let DEVEPTCFG_EPSIZE_32_BYTE:   U32 = (0x2 << DEVEPTCFG_EPSIZE_SHIFT)
        public static let DEVEPTCFG_EPSIZE_64_BYTE:   U32 = (0x3 << DEVEPTCFG_EPSIZE_SHIFT)
        public static let DEVEPTCFG_EPSIZE_128_BYTE:  U32 = (0x4 << DEVEPTCFG_EPSIZE_SHIFT)
        public static let DEVEPTCFG_EPSIZE_256_BYTE:  U32 = (0x5 << DEVEPTCFG_EPSIZE_SHIFT)
        public static let DEVEPTCFG_EPSIZE_512_BYTE:  U32 = (0x6 << DEVEPTCFG_EPSIZE_SHIFT)
        public static let DEVEPTCFG_EPSIZE_1024_BYTE: U32 = (0x7 << DEVEPTCFG_EPSIZE_SHIFT)

        public static let DEVEPTCFG_EPTYPE_SHIFT: U32 = 8
        public static let DEVEPTCFG_EPTYPE_MASK:  U32 = (0x7 << DEVEPTCFG_EPTYPE_SHIFT)
        public static let DEVEPTCFG_EPTYPE_CTRL:  U32 = (0x0 << DEVEPTCFG_EPTYPE_SHIFT)
        public static let DEVEPTCFG_EPTYPE_ISO:   U32 = (0x1 << DEVEPTCFG_EPTYPE_SHIFT)
        public static let DEVEPTCFG_EPTYPE_BULK:  U32 = (0x2 << DEVEPTCFG_EPTYPE_SHIFT)
        public static let DEVEPTCFG_EPTYPE_INT:   U32 = (0x3 << DEVEPTCFG_EPTYPE_SHIFT)

        public static let DEVEPTCFG_EPDIR: U32 = (1 << 11) // 1=IN, 0=OUT (para não-control)

        // MARK: DPRAM / FIFO mapping
        //
        // instance_uotghs.h (ArduinoCore-sam / CMSIS) expõe o DPRAM do UOTGHS em 0x400A_8000.
        // O layout exato por endpoint pode variar; para CDC (EP1..EP3) normalmente funciona com stride 0x800.
        public static let DPRAM_BASE: U32 = 0x400A_8000
        public static let DPRAM_STRIDE_PER_EP: U32 = 0x0800 // 2KB por endpoint (layout comum)

        @inline(__always) public static func DEVEPTFIFO(_ ep: U32) -> U32 {
            DPRAM_BASE + ep * DPRAM_STRIDE_PER_EP
        }
    }
}