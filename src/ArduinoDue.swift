// ArduinoDue.swift — Arduino Due digital pin mapping (D0...D53)
// Provides a small mapping layer: Arduino digital pin -> SAM3X PIO port + bit.
//
// Source: Arduino Due documentation pin mapping table (D0..D53).  [oai_citation:1‡Imimg](https://5.imimg.com/data5/OZ/WE/IJ/SELLER-1833510/arduino-due.pdf)
//
// Notes:
// - D4 is connected to BOTH PA29 and PC26.
// - D10 is connected to BOTH PA28 and PC29.
// For those, we expose a "secondary" mapping so PIN can drive both.

public enum ArduinoDue {
    public struct DigitalPinDesc {
        public let pioBase: U32
        public let pioID: U32
        public let mask: U32

        // Some board pins are wired to two SAM3X pins.
        public let pioBase2: U32?
        public let pioID2: U32?
        public let mask2: U32?

        @inline(__always)
        public init(
            pioBase: U32,
            pioID: U32,
            bit: U32,
            pioBase2: U32? = nil,
            pioID2: U32? = nil,
            bit2: U32? = nil
        ) {
            self.pioBase = pioBase
            self.pioID = pioID
            self.mask = U32(1) << bit

            if let pioBase2, let pioID2, let bit2 {
                self.pioBase2 = pioBase2
                self.pioID2 = pioID2
                self.mask2 = U32(1) << bit2
            } else {
                self.pioBase2 = nil
                self.pioID2 = nil
                self.mask2 = nil
            }
        }
    }

    // Convenience (PIOA/B/C/D)
    @inline(__always) private static func PA(_ bit: U32) -> DigitalPinDesc {
        .init(pioBase: ATSAM3X8E.PIOA_BASE, pioID: ATSAM3X8E.ID.PIOA, bit: bit)
    }
    @inline(__always) private static func PB(_ bit: U32) -> DigitalPinDesc {
        .init(pioBase: ATSAM3X8E.PIOB_BASE, pioID: ATSAM3X8E.ID.PIOB, bit: bit)
    }
    @inline(__always) private static func PC(_ bit: U32) -> DigitalPinDesc {
        .init(pioBase: ATSAM3X8E.PIOC_BASE, pioID: ATSAM3X8E.ID.PIOC, bit: bit)
    }
    @inline(__always) private static func PD(_ bit: U32) -> DigitalPinDesc {
        .init(pioBase: ATSAM3X8E.PIOD_BASE, pioID: ATSAM3X8E.ID.PIOD, bit: bit)
    }

    // D4: both PA29 and PC26
    private static let D4: DigitalPinDesc = .init(
        pioBase: ATSAM3X8E.PIOA_BASE, pioID: ATSAM3X8E.ID.PIOA, bit: 29,
        pioBase2: ATSAM3X8E.PIOC_BASE, pioID2: ATSAM3X8E.ID.PIOC, bit2: 26
    )

    // D10: both PA28 and PC29
    private static let D10: DigitalPinDesc = .init(
        pioBase: ATSAM3X8E.PIOA_BASE, pioID: ATSAM3X8E.ID.PIOA, bit: 28,
        pioBase2: ATSAM3X8E.PIOC_BASE, pioID2: ATSAM3X8E.ID.PIOC, bit2: 29
    )

    /// Returns mapping for Arduino Due digital pins D0...D53.
    @inline(__always)
    public static func digital(_ pin: U32) -> DigitalPinDesc? {
        switch pin {
        case 0:  return PA(8)    // RX0
        case 1:  return PA(9)    // TX0
        case 2:  return PB(25)   // D2   [oai_citation:2‡Imimg](https://5.imimg.com/data5/OZ/WE/IJ/SELLER-1833510/arduino-due.pdf)
        case 3:  return PC(28)   // D3
        case 4:  return D4       // D4: PA29 + PC26
        case 5:  return PC(25)   // D5
        case 6:  return PC(24)   // D6
        case 7:  return PC(23)   // D7
        case 8:  return PC(22)   // D8
        case 9:  return PC(21)   // D9
        case 10: return D10      // D10: PA28 + PC29
        case 11: return PD(7)    // D11
        case 12: return PD(8)    // D12
        case 13: return PB(27)   // D13 / LED "L"
        case 14: return PD(4)    // TX3
        case 15: return PD(5)    // RX3
        case 16: return PA(13)   // TX2
        case 17: return PA(12)   // RX2
        case 18: return PA(11)   // TX1
        case 19: return PA(10)   // RX1
        case 20: return PB(12)   // SDA
        case 21: return PB(13)   // SCL
        case 22: return PB(26)   // D22
        case 23: return PA(14)   // D23
        case 24: return PA(15)   // D24
        case 25: return PD(0)    // D25
        case 26: return PD(1)    // D26
        case 27: return PD(2)    // D27
        case 28: return PD(3)    // D28
        case 29: return PD(6)    // D29
        case 30: return PD(9)    // D30
        case 31: return PA(7)    // D31
        case 32: return PD(10)   // D32
        case 33: return PC(1)    // D33
        case 34: return PC(2)    // D34
        case 35: return PC(3)    // D35
        case 36: return PC(4)    // D36
        case 37: return PC(5)    // D37
        case 38: return PC(6)    // D38
        case 39: return PC(7)    // D39
        case 40: return PC(8)    // D40
        case 41: return PC(9)    // D41
        case 42: return PA(19)   // D42
        case 43: return PA(20)   // D43
        case 44: return PC(19)   // D44
        case 45: return PC(18)   // D45
        case 46: return PC(17)   // D46
        case 47: return PC(16)   // D47
        case 48: return PC(15)   // D48
        case 49: return PC(14)   // D49
        case 50: return PC(13)   // D50
        case 51: return PC(12)   // D51
        case 52: return PB(21)   // D52
        case 53: return PB(14)   // D53
        default:
            return nil
        }
    }
}