// AnalogPIN.swift — Arduino Due (SAM3X8E) Analog wrapper (ADC + DAC)
//
// Uses:
// - ArduinoDue.analog(_:) mapping (A0..A11 + DAC0/DAC1)
// - ATSAM3X8E.swift for register addresses/offsets/bits
// - MMIO.swift for read32/write32 + U32/U16
// - bm_nop()
//
// IMPORTANT (Embedded Swift / bare-metal):
// - Avoid Float to not pull __aeabi_* soft-fp helpers at link time.

@inline(__always)
private func pmcEnablePeripheral(_ id: U32) {
    // SAM3X PMC has two enable registers:
    //  - PCER0 for IDs 0..31
    //  - PCER1 for IDs 32..63 (bit = id-32)
    if id < 32 {
        write32(ATSAM3X8E.PMC.PCER0, U32(1) << id)
    } else {
        write32(ATSAM3X8E.PMC.PCER1, U32(1) << (id - 32))
    }
}

public struct AnalogPIN {
    // MARK: - Public API

    public enum Kind: Equatable {
        case adc(channel: U32) // ADC channel 0..15
        case dac(channel: U32) // DACC channel 0..1
    }

    public enum Error: Swift.Error, Equatable {
        case invalidAnalogPin(U32)
        case notADC(pin: U32)
        case notDAC(pin: U32)
        case dacChannelUnavailable(channel: U32)
        case valueOutOfRange
    }

    /// Arduino-style analog number:
    /// - 0...11 => A0...A11 (ADC)
    /// - 12 => DAC0
    /// - 13 => DAC1
    public init(_ analogPin: U32) {
        guard let d = ArduinoDue.analog(analogPin) else {
            // Embedded-friendly "trap"
            while true { bm_nop() }
        }

        self.analogPin = analogPin
        self.kind = Self.convertKind(d.kind)
        self.pioBase = d.pioBase
        self.pioID = d.pioID
        self.mask = d.mask
        self.peripheral = d.peripheral

        // 1) Enable PIO clock for port
        enablePIOClock(pioID)

        // NOTE (SAM3X/SAM3A ADC):
        // The Arduino core does NOT do a PIO_Configure() for analogRead on SAM3X;
        // it relies on board pin description + ADC channel enable and reads LCDR.
        //
        // Therefore we keep ADC pins as plain inputs with pullups disabled.
        // For DAC pins we hand over to the peripheral (A/B).

        switch kind {
        case .adc:
            // Keep pin under PIO control as input
            write32(pioBase + ATSAM3X8E.PIO.PER_OFFSET, mask)   // enable PIO control
            write32(pioBase + ATSAM3X8E.PIO.ODR_OFFSET, mask)   // input (disable output)

            // Safe defaults for analog input
            write32(pioBase + ATSAM3X8E.PIO.IDR_OFFSET, mask)   // disable interrupts
            write32(pioBase + ATSAM3X8E.PIOX.PUDR_OFFSET, mask) // pull-up disable
            write32(pioBase + ATSAM3X8E.PIO.MDDR_OFFSET, mask)  // multidriver off
            write32(pioBase + ATSAM3X8E.PIO.IFDR_OFFSET, mask)  // input filter off

        case .dac:
            // Select peripheral A/B via ABSR, then disable PIO via PDR (handover)
            switch peripheral {
            case .a:
                let v = read32(pioBase + ATSAM3X8E.PIOX.ABSR_OFFSET)
                write32(pioBase + ATSAM3X8E.PIOX.ABSR_OFFSET, v & ~mask) // A = 0
            case .b:
                let v = read32(pioBase + ATSAM3X8E.PIOX.ABSR_OFFSET)
                write32(pioBase + ATSAM3X8E.PIOX.ABSR_OFFSET, v | mask) // B = 1
            }

            // Hand over to peripheral
            write32(pioBase + ATSAM3X8E.PIO.PDR_OFFSET, mask)

            // Safe defaults
            write32(pioBase + ATSAM3X8E.PIO.IDR_OFFSET, mask)   // disable interrupts
            write32(pioBase + ATSAM3X8E.PIOX.PUDR_OFFSET, mask) // pull-up disable
            write32(pioBase + ATSAM3X8E.PIO.MDDR_OFFSET, mask)  // multidriver off
            write32(pioBase + ATSAM3X8E.PIO.IFDR_OFFSET, mask)  // input filter off
        }

        // 4) Lazy init underlying peripheral
        switch kind {
        case .adc:
            ADC.ensureInit(mckHz: Self.defaultMckHz, adcClockHz: Self.defaultAdcClockHz)
        case .dac:
            DAC.ensureInit(mckHz: Self.defaultMckHz)
        }
    }

    /// Raw 12-bit ADC read (0...4095).
    @inline(__always)
    public func readRaw() throws(AnalogPIN.Error) -> U16 {
        guard case let .adc(ch) = kind else { throw Error.notADC(pin: analogPin) }
        return ADC.read12(channel: ch)
    }

    /// Arduino-ish 10-bit ADC read (0...1023).
    @inline(__always)
    public func read10() throws(AnalogPIN.Error) -> U16 {
        let v12 = try readRaw()
        return U16((U32(v12) * 1023) / 4095)
    }

    /// Raw 12-bit DAC write (0...4095).
    @inline(__always)
    public func writeRaw(_ value: U16) throws(AnalogPIN.Error) {
        guard case let .dac(ch) = kind else { throw Error.notDAC(pin: analogPin) }
        if value > 4095 { throw Error.valueOutOfRange }
        try DAC.write12(channel: ch, value: value)
    }

    /// Arduino-ish 10-bit DAC write (0...1023).
    @inline(__always)
    public func write10(_ value: U16) throws(AnalogPIN.Error) {
        if value > 1023 { throw Error.valueOutOfRange }
        let v12 = U16((U32(value) * 4095) / 1023)
        try writeRaw(v12)
    }

    // MARK: - Optional explicit configuration

    /// Call once early if you want correct ADC prescaler when MCK changes:
    ///   AnalogPIN.configure(mckHz: ctx.mckHz)
    public static func configure(
        mckHz: U32,
        adcClockHz: U32 = 1_000_000
    ) {
        defaultMckHz = mckHz
        defaultAdcClockHz = adcClockHz
        ADC.ensureInit(mckHz: mckHz, adcClockHz: adcClockHz)
        DAC.ensureInit(mckHz: mckHz)
    }

    // MARK: - Internals

    private let analogPin: U32
    public let kind: Kind

    private let pioBase: U32
    private let pioID: U32
    private let mask: U32
    private let peripheral: ArduinoDue.AnalogPinDesc.PeripheralSel

    private static var defaultMckHz: U32 = 84_000_000
    private static var defaultAdcClockHz: U32 = 1_000_000

    @inline(__always)
    private func enablePIOClock(_ id: U32) {
        pmcEnablePeripheral(id)
    }

    @inline(__always)
    private static func convertKind(_ k: ArduinoDue.AnalogKind) -> Kind {
        switch k {
        case let .adc(channel): return .adc(channel: channel)
        case let .dac(channel): return .dac(channel: channel)
        }
    }
}

// MARK: - ADC (SAM3X ADC)

private enum ADC {
    private static var inited: Bool = false
    private static var lastMckHz: U32 = 0
    private static var lastAdcHz: U32 = 0

    // Arduino core keeps one channel enabled and switches as needed
    private static var latestSelectedChannel: U32 = 0xFFFF

    // DRDY is bit 24 on SAM3X ADC_ISR
    private static let ISR_DRDY: U32 = (U32(1) << 24)

    @inline(__always)
    static func ensureInit(mckHz: U32, adcClockHz: U32) {
        if inited, mckHz == lastMckHz, adcClockHz == lastAdcHz { return }

        // Enable peripheral clock
        pmcEnablePeripheral(ATSAM3X8E.ID.ADC)

        // Reset
        write32(ATSAM3X8E.ADC.CR, ATSAM3X8E.ADC.CR_SWRST)

        // ADCClock = MCK / (2 * (PRESCAL+1))
        let prescal: U32 = {
            if adcClockHz == 0 { return 41 }
            let denom = 2 * adcClockHz
            let q = (mckHz + denom - 1) / denom // ceil(mck/denom)
            return (q > 0) ? (q - 1) : 0
        }()

        // Conservative timings
        let startup: U32 = 8
        let track: U32 = 3
        let transfer: U32 = 1

        var mr: U32 = 0
        mr &= ~ATSAM3X8E.ADC.MR_PRESCAL_MASK
        mr |= (prescal << ATSAM3X8E.ADC.MR_PRESCAL_SHIFT) & ATSAM3X8E.ADC.MR_PRESCAL_MASK

        mr &= ~ATSAM3X8E.ADC.MR_STARTUP_MASK
        mr |= (startup << ATSAM3X8E.ADC.MR_STARTUP_SHIFT) & ATSAM3X8E.ADC.MR_STARTUP_MASK

        mr &= ~ATSAM3X8E.ADC.MR_TRACKTIM_MASK
        mr |= (track << ATSAM3X8E.ADC.MR_TRACKTIM_SHIFT) & ATSAM3X8E.ADC.MR_TRACKTIM_MASK

        mr &= ~ATSAM3X8E.ADC.MR_TRANSFER_MASK
        mr |= (transfer << ATSAM3X8E.ADC.MR_TRANSFER_SHIFT) & ATSAM3X8E.ADC.MR_TRANSFER_MASK

        write32(ATSAM3X8E.ADC.MR, mr)

        // Disable all channels initially
        write32(ATSAM3X8E.ADC.CHDR, 0xFFFF)
        latestSelectedChannel = 0xFFFF

        inited = true
        lastMckHz = mckHz
        lastAdcHz = adcClockHz
    }

    @inline(__always)
    static func read12(channel ch: U32) -> U16 {
        let bit = U32(1) << ch

        // Enable channel if needed (Arduino-like)
        // If switching channels, disable previous channel to avoid surprises.
        let cher = read32(ATSAM3X8E.ADC.CHER) // readback may not be valid on all MCUs; ok if it is
        if (cher & bit) == 0 {
            write32(ATSAM3X8E.ADC.CHER, bit)
            if latestSelectedChannel != 0xFFFF, latestSelectedChannel != ch {
                write32(ATSAM3X8E.ADC.CHDR, U32(1) << latestSelectedChannel)
            }
            latestSelectedChannel = ch
        }

        // Start conversion
        write32(ATSAM3X8E.ADC.CR, ATSAM3X8E.ADC.CR_START)

        // Wait for Data Ready (DRDY), like ArduinoCore-sam
        var spin: U32 = 0
        while (read32(ATSAM3X8E.ADC.ISR) & ISR_DRDY) == 0 {
            spin &+= 1
            if spin > 400_000 {
                return 0xFFFF
            }
            bm_nop()
        }

        // Read latest converted value (LCDR), 12-bit
        // Arduino does adc_get_latest_value(ADC) which reads ADC->ADC_LCDR
        let v = read32(ATSAM3X8E.ADC.LCDR) & 0x0FFF
        return U16(v)
    }
}

// MARK: - DAC (SAM3X DACC)

private enum DAC {
    private static var inited: Bool = false
    private static var lastMckHz: U32 = 0

    @inline(__always)
    static func ensureInit(mckHz: U32) {
        if inited, mckHz == lastMckHz { return }

        // Enable peripheral clock
        pmcEnablePeripheral(ATSAM3X8E.ID.DACC)

        // Reset
        write32(ATSAM3X8E.DACC.CR, ATSAM3X8E.DACC.CR_SWRST)

        // Free running, half-word, TAG enabled
        let mr = ATSAM3X8E.DACC.MR_TRGEN_DIS | ATSAM3X8E.DACC.MR_WORD_HALF | ATSAM3X8E.DACC.MR_TAG_EN
        write32(ATSAM3X8E.DACC.MR, mr)

        // Enable both channels
        write32(ATSAM3X8E.DACC.CHER, (U32(1) << 0) | (U32(1) << 1))

        inited = true
        lastMckHz = mckHz
    }

    @inline(__always)
    static func write12(channel ch: U32, value: U16) throws(AnalogPIN.Error) {
        if ch > 1 { throw AnalogPIN.Error.dacChannelUnavailable(channel: ch) }

        // Wait TX ready
        while (read32(ATSAM3X8E.DACC.ISR) & ATSAM3X8E.DACC.ISR_TXRDY) == 0 {
            bm_nop()
        }

        // TAG mode: channel in bits [13:12], data in [11:0]
        let tag: U32 = (ch & 0x3) << 12
        let data: U32 = U32(value) & 0x0FFF
        write32(ATSAM3X8E.DACC.CDR, tag | data)
    }
}