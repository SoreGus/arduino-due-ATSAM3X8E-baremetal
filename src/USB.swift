// USB.swift
// UOTGHS device driver + CDC-ACM (mínimo) para ATSAM3X8E (Arduino Due Native USB)
//
// Requisitos:
// - MMIO.swift: read32/write32, bm_dsb/bm_isb/bm_nop
// - ATSAM3X8E.swift + ATSAM3X8E+USB.swift (endereços + masks)
// - SerialUSBDescriptor.swift

public final class USBDevice {

    public enum State: Equatable {
        case detached
        case powered
        case defaultState
        case addressed(UInt8)
        case configured(UInt8)
    }

    public struct SetupPacket {
        public var bmRequestType: UInt8
        public var bRequest: UInt8
        public var wValue: UInt16
        public var wIndex: UInt16
        public var wLength: UInt16
    }

    private var state: State = .detached
    private var addressPending: UInt8? = nil
    private var configurationValue: UInt8 = 0

    // CDC line coding
    private var lineCoding: (dwDTERate: UInt32, bCharFormat: UInt8, bParityType: UInt8, bDataBits: UInt8) =
        (115200, 0, 0, 8)

    // RX buffer simples
    private var cdcRxBuf: [UInt8] = []
    private var cdcRxCount: Int = 0

    public init() {}

    // Se você quiser usar no main: if usb.isConfigured { ... }
    public var isConfigured: Bool {
        if case .configured = state { return true }
        return false
    }

    // MARK: - Public

    public func begin() {
        // clocks primeiro
        enableUSBClocks()

        // core + device mode
        initUOTGHSDevice()

        // força detach/attach (garante re-enum)
        detach()
        smallDelay()
        attach()

        // EP0 + endereços zerados
        onBusReset()

        // Agora estamos prontos: host deve detectar e mandar reset
        state = .defaultState
    }

    public func poll() {
        // Reset do barramento
        let isr = read32(ATSAM3X8E.UOTGHS.DEVISR)
        if (isr & ATSAM3X8E.UOTGHS.DEVISR_EORST) != 0 {
            // ack reset
            write32(ATSAM3X8E.UOTGHS.DEVICR, ATSAM3X8E.UOTGHS.DEVISR_EORST)
            onBusReset()
        }

        // EP0 control
        serviceEP0()

        // CDC OUT
        serviceCDCOut()
    }

    // MARK: - CDC API

    public func cdcWrite(_ bytes: [UInt8]) {
        guard isConfigured else { return }
        epWriteIN(ep: SerialUSBDescriptor.EP_CDC_IN, bytes: bytes, maxPacket: Int(SerialUSBDescriptor.BULK_SIZE))
    }

    public func cdcWriteString(_ s: String) {
        // sem alocação gigante
        var out: [UInt8] = []
        out.reserveCapacity(s.utf8.count)
        for b in s.utf8 { out.append(b) }
        cdcWrite(out)
    }

    public func cdcAvailable() -> Int { cdcRxCount }

    public func cdcRead() -> Int {
        if cdcRxCount == 0 { return -1 }
        let b = cdcRxBuf.removeFirst()
        cdcRxCount -= 1
        return Int(b)
    }

    // MARK: - Clocks + Core init

    private func enableUSBClocks() {
        // 1) UPLL ON
        var uckr = read32(ATSAM3X8E.PMC_USBX.CKGR_UCKR)
        uckr &= ~ATSAM3X8E.PMC_USBX.UCKR_UPLLCOUNT_MASK
        uckr |= (0xF << ATSAM3X8E.PMC_USBX.UCKR_UPLLCOUNT_SHIFT)
        uckr |= ATSAM3X8E.PMC_USBX.UCKR_UPLLEN
        write32(ATSAM3X8E.PMC_USBX.CKGR_UCKR, uckr)

        // wait LOCKU
        var t: U32 = 5_000_000
        while t != 0 {
            if (read32(ATSAM3X8E.PMC_USBX.SR) & ATSAM3X8E.PMC_USBX.SR_LOCKU) != 0 { break }
            bm_nop()
            t &-= 1
        }

        // 2) USB clock source = UPLL, div=0
        var usb = read32(ATSAM3X8E.PMC_USBX.USB)
        usb |= ATSAM3X8E.PMC_USBX.USB_USBS
        usb &= ~ATSAM3X8E.PMC_USBX.USB_USBDIV_MASK
        usb |= (0 << ATSAM3X8E.PMC_USBX.USB_USBDIV_SHIFT)
        write32(ATSAM3X8E.PMC_USBX.USB, usb)

        // 3) enable UOTGCLK
        write32(ATSAM3X8E.PMC_USBX.SCER, ATSAM3X8E.PMC_USBX.SCER_UOTGCLK)
    }

    private func initUOTGHSDevice() {
        // CTRL: USBE + device mode + OTG pad + unfreeze
        var ctrl = read32(ATSAM3X8E.UOTGHS.CTRL)
        ctrl |= ATSAM3X8E.UOTGHS.CTRL_USBE
        ctrl |= ATSAM3X8E.UOTGHS.CTRL_UIMOD
        ctrl |= (1 << 4) // OTGPADE (bit do CTRL no UOTGHS). Alguns headers chamam de CTRL_OTGPADE.
        ctrl &= ~ATSAM3X8E.UOTGHS.CTRL_FRZCLK
        write32(ATSAM3X8E.UOTGHS.CTRL, ctrl)

        // Enable reset interrupt (polling usa ISR, mas o enable é necessário em vários IPs)
        write32(ATSAM3X8E.UOTGHS.DEVIER, ATSAM3X8E.UOTGHS.DEVISR_EORST)

        // Zera address
        write32(ATSAM3X8E.UOTGHS.DEVADDR, 0)

        bm_dsb()
        bm_isb()
    }

    private func attach() {
        var devctrl = read32(ATSAM3X8E.UOTGHS.DEVCTRL)
        devctrl &= ~ATSAM3X8E.UOTGHS.DEVCTRL_DETACH
        write32(ATSAM3X8E.UOTGHS.DEVCTRL, devctrl)
        state = .powered
    }

    private func detach() {
        var devctrl = read32(ATSAM3X8E.UOTGHS.DEVCTRL)
        devctrl |= ATSAM3X8E.UOTGHS.DEVCTRL_DETACH
        write32(ATSAM3X8E.UOTGHS.DEVCTRL, devctrl)
        state = .detached
    }

    private func onBusReset() {
        addressPending = nil
        configurationValue = 0
        state = .defaultState

        // addr = 0, ADDEN=0
        write32(ATSAM3X8E.UOTGHS.DEVADDR, 0)

        // EP0 control
        configureEP0()

        // CDC endpoints (ficam prontos; só usamos depois de SET_CONFIGURATION)
        configureCDCEndpoints()
    }

    // MARK: - Endpoint config

    private func configureEP0() {
        let ep: U32 = 0

        // desliga/limpa tudo
        write32(ATSAM3X8E.UOTGHS.DEVEPTIDR(ep), 0xFFFF_FFFF)
        write32(ATSAM3X8E.UOTGHS.DEVEPTICR(ep), 0xFFFF_FFFF)

        // configura EP0 como CONTROL 64B, 1 bank, alloc
        let cfg: U32 =
            ATSAM3X8E.UOTGHS.DEVEPTCFG_EPTYPE_CTRL |
            ATSAM3X8E.UOTGHS.DEVEPTCFG_EPSIZE_64_BYTE |
            ATSAM3X8E.UOTGHS.DEVEPTCFG_EPBK_1_BANK |
            ATSAM3X8E.UOTGHS.DEVEPTCFG_ALLOC

        write32(ATSAM3X8E.UOTGHS.DEVEPTCFG(ep), cfg)

        // habilita EP0 no DEVEPT (bit por endpoint)
        write32(ATSAM3X8E.UOTGHS.DEVEPT, ATSAM3X8E.UOTGHS.EPEN(ep))

        // habilita IRQ flags que a gente usa no polling
        write32(ATSAM3X8E.UOTGHS.DEVEPTIER(ep), ATSAM3X8E.UOTGHS.EPISR_RXSTPI)
    }

    private func configureCDCEndpoints() {
        // EP1 Interrupt IN (8 bytes)
        configureEndpoint(
            ep: U32(SerialUSBDescriptor.EP_CDC_NOTIFY),
            type: ATSAM3X8E.UOTGHS.DEVEPTCFG_EPTYPE_INT,
            size: epsizeFor(maxPacket: Int(SerialUSBDescriptor.INT_SIZE)),
            dirIn: true
        )

        // EP2 Bulk OUT (64 bytes)
        configureEndpoint(
            ep: U32(SerialUSBDescriptor.EP_CDC_OUT),
            type: ATSAM3X8E.UOTGHS.DEVEPTCFG_EPTYPE_BULK,
            size: ATSAM3X8E.UOTGHS.DEVEPTCFG_EPSIZE_64_BYTE,
            dirIn: false
        )

        // EP3 Bulk IN (64 bytes)
        configureEndpoint(
            ep: U32(SerialUSBDescriptor.EP_CDC_IN),
            type: ATSAM3X8E.UOTGHS.DEVEPTCFG_EPTYPE_BULK,
            size: ATSAM3X8E.UOTGHS.DEVEPTCFG_EPSIZE_64_BYTE,
            dirIn: true
        )

        // OUT: habilita RXOUTI
        write32(
            ATSAM3X8E.UOTGHS.DEVEPTIER(U32(SerialUSBDescriptor.EP_CDC_OUT)),
            ATSAM3X8E.UOTGHS.EPISR_RXOUTI
        )
    }

    private func configureEndpoint(ep: U32, type: U32, size: U32, dirIn: Bool) {
        write32(ATSAM3X8E.UOTGHS.DEVEPTIDR(ep), 0xFFFF_FFFF)
        write32(ATSAM3X8E.UOTGHS.DEVEPTICR(ep), 0xFFFF_FFFF)

        var cfg: U32 =
            type |
            size |
            ATSAM3X8E.UOTGHS.DEVEPTCFG_EPBK_1_BANK |
            ATSAM3X8E.UOTGHS.DEVEPTCFG_ALLOC

        if dirIn { cfg |= ATSAM3X8E.UOTGHS.DEVEPTCFG_EPDIR }

        write32(ATSAM3X8E.UOTGHS.DEVEPTCFG(ep), cfg)
        write32(ATSAM3X8E.UOTGHS.DEVEPT, read32(ATSAM3X8E.UOTGHS.DEVEPT) | ATSAM3X8E.UOTGHS.EPEN(ep))
    }

    private func epsizeFor(maxPacket: Int) -> U32 {
        switch maxPacket {
        case 8:   return ATSAM3X8E.UOTGHS.DEVEPTCFG_EPSIZE_8_BYTE
        case 16:  return ATSAM3X8E.UOTGHS.DEVEPTCFG_EPSIZE_16_BYTE
        case 32:  return ATSAM3X8E.UOTGHS.DEVEPTCFG_EPSIZE_32_BYTE
        case 64:  return ATSAM3X8E.UOTGHS.DEVEPTCFG_EPSIZE_64_BYTE
        default:  return ATSAM3X8E.UOTGHS.DEVEPTCFG_EPSIZE_64_BYTE
        }
    }

    // MARK: - EP0 service / setup

    private func serviceEP0() {
        let ep: U32 = 0
        let isr = read32(ATSAM3X8E.UOTGHS.DEVEPTISR(ep))

        // SETUP?
        if (isr & ATSAM3X8E.UOTGHS.EPISR_RXSTPI) != 0 {
            // ack RXSTP
            write32(ATSAM3X8E.UOTGHS.DEVEPTICR(ep), ATSAM3X8E.UOTGHS.EPICR_RXSTPIC)

            if let setup = epReadSetup(ep: ep) {
                handleSetup(setup)
            }
        }

        // commit address AFTER status stage (aqui no polling: logo após responder ZLP)
        if let addr = addressPending {
            // DEVADDR = addr | ADDEN
            let v: U32 = (U32(addr) & ATSAM3X8E.UOTGHS.DEVADDR_UADD_MASK) | ATSAM3X8E.UOTGHS.DEVADDR_ADDEN
            write32(ATSAM3X8E.UOTGHS.DEVADDR, v)
            addressPending = nil
            state = .addressed(addr)
        }
    }

    private func handleSetup(_ s: SetupPacket) {
        // GET_DESCRIPTOR
        if s.bRequest == SerialUSBDescriptor.REQ_GET_DESCRIPTOR {
            let dtype = UInt8(truncatingIfNeeded: s.wValue >> 8)
            let dindex = UInt8(truncatingIfNeeded: s.wValue & 0xFF)
            let maxLen = Int(s.wLength)

            if let desc = SerialUSBDescriptor.getDescriptor(type: dtype, index: dindex, maxLen: maxLen) {
                epWriteControlIN(ep: 0, bytes: desc, maxPacket: Int(SerialUSBDescriptor.EP0_SIZE))
                epZLP_IN(ep: 0)
            } else {
                stallEP0()
            }
            return
        }

        // SET_ADDRESS
        if s.bRequest == 0x05 {
            let addr = UInt8(truncatingIfNeeded: s.wValue & 0x7F)
            epZLP_IN(ep: 0)             // status
            addressPending = addr        // commit no próximo poll
            return
        }

        // SET_CONFIGURATION
        if s.bRequest == 0x09 {
            let cfg = UInt8(truncatingIfNeeded: s.wValue & 0xFF)
            configurationValue = cfg
            epZLP_IN(ep: 0)

            if cfg != 0 {
                state = .configured(cfg)
            } else {
                if case .addressed(let a) = state {
                    state = .addressed(a)
                } else {
                    state = .defaultState
                }
            }
            return
        }

        // CDC class requests
        if s.bRequest == 0x20, s.wLength == 7 {
            let data = epReadControlOUT(ep: 0, count: 7)
            if data.count == 7 {
                let rate = UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 24)
                lineCoding = (rate, data[4], data[5], data[6])
            }
            epZLP_IN(ep: 0)
            return
        }

        if s.bRequest == 0x21 {
            var out: [UInt8] = [0,0,0,0, lineCoding.bCharFormat, lineCoding.bParityType, lineCoding.bDataBits]
            let r = lineCoding.dwDTERate
            out[0] = UInt8(truncatingIfNeeded: r & 0xFF)
            out[1] = UInt8(truncatingIfNeeded: (r >> 8) & 0xFF)
            out[2] = UInt8(truncatingIfNeeded: (r >> 16) & 0xFF)
            out[3] = UInt8(truncatingIfNeeded: (r >> 24) & 0xFF)

            epWriteControlIN(ep: 0, bytes: out, maxPacket: Int(SerialUSBDescriptor.EP0_SIZE))
            epZLP_IN(ep: 0)
            return
        }

        if s.bRequest == 0x22 {
            epZLP_IN(ep: 0)
            return
        }

        stallEP0()
    }

    private func stallEP0() {
        // mínimo: sem STALL explícito por enquanto
    }

    // MARK: - CDC OUT

    private func serviceCDCOut() {
        guard isConfigured else { return }

        let ep = U32(SerialUSBDescriptor.EP_CDC_OUT)
        let isr = read32(ATSAM3X8E.UOTGHS.DEVEPTISR(ep))

        if (isr & ATSAM3X8E.UOTGHS.EPISR_RXOUTI) == 0 { return }

        let byct = Int((isr & ATSAM3X8E.UOTGHS.EPISR_BYCT_MASK) >> ATSAM3X8E.UOTGHS.EPISR_BYCT_SHIFT)

        // ack RXOUTI
        write32(ATSAM3X8E.UOTGHS.DEVEPTICR(ep), ATSAM3X8E.UOTGHS.EPICR_RXOUTIC)

        if byct <= 0 { return }

        let fifo = ATSAM3X8E.UOTGHS.DEVEPTFIFO(ep)
        for _ in 0..<byct {
            let b = read8(fifo)
            cdcRxBuf.append(b)
            cdcRxCount += 1
        }
    }

    // MARK: - FIFO 8-bit access

    @inline(__always)
    private func read8(_ addr: U32) -> UInt8 {
        UnsafeMutablePointer<UInt8>(bitPattern: Int(addr))!.pointee
    }

    @inline(__always)
    private func write8(_ addr: U32, _ v: UInt8) {
        UnsafeMutablePointer<UInt8>(bitPattern: Int(addr))!.pointee = v
    }

    // MARK: - EP0 I/O

    private func epReadSetup(ep: U32) -> SetupPacket? {
        let fifo = ATSAM3X8E.UOTGHS.DEVEPTFIFO(ep)

        let b0 = read8(fifo)
        let b1 = read8(fifo)
        let b2 = read8(fifo)
        let b3 = read8(fifo)
        let b4 = read8(fifo)
        let b5 = read8(fifo)
        let b6 = read8(fifo)
        let b7 = read8(fifo)

        let wValue  = UInt16(b2) | (UInt16(b3) << 8)
        let wIndex  = UInt16(b4) | (UInt16(b5) << 8)
        let wLength = UInt16(b6) | (UInt16(b7) << 8)

        return SetupPacket(
            bmRequestType: b0,
            bRequest: b1,
            wValue: wValue,
            wIndex: wIndex,
            wLength: wLength
        )
    }

    private func epReadControlOUT(ep: U32, count: Int) -> [UInt8] {
        let fifo = ATSAM3X8E.UOTGHS.DEVEPTFIFO(ep)
        var out: [UInt8] = []
        out.reserveCapacity(count)
        for _ in 0..<count { out.append(read8(fifo)) }
        return out
    }

    private func epWriteControlIN(ep: U32, bytes: [UInt8], maxPacket: Int) {
        var idx = 0
        while idx < bytes.count {
            let chunk = min(maxPacket, bytes.count - idx)
            let fifo = ATSAM3X8E.UOTGHS.DEVEPTFIFO(ep)

            for i in 0..<chunk { write8(fifo, bytes[idx + i]) }
            idx += chunk

            waitTxINI(ep: ep)
        }
    }

    private func epZLP_IN(ep: U32) {
        waitTxINI(ep: ep)
    }

    private func waitTxINI(ep: U32) {
        var t: U32 = 2_000_000
        while t != 0 {
            let isr = read32(ATSAM3X8E.UOTGHS.DEVEPTISR(ep))
            if (isr & ATSAM3X8E.UOTGHS.EPISR_TXINI) != 0 {
                write32(ATSAM3X8E.UOTGHS.DEVEPTICR(ep), ATSAM3X8E.UOTGHS.EPICR_TXINIC)
                return
            }
            bm_nop()
            t &-= 1
        }
    }

    // MARK: - CDC IN

    private func epWriteIN(ep: UInt8, bytes: [UInt8], maxPacket: Int) {
        let epu = U32(ep)
        var idx = 0

        while idx < bytes.count {
            let chunk = min(maxPacket, bytes.count - idx)

            waitTxINI(ep: epu)

            let fifo = ATSAM3X8E.UOTGHS.DEVEPTFIFO(epu)
            for i in 0..<chunk { write8(fifo, bytes[idx + i]) }
            idx += chunk
        }
    }

    // MARK: - tiny delay

    private func smallDelay() {
        var t: U32 = 200_000
        while t != 0 { bm_nop(); t &-= 1 }
    }
}