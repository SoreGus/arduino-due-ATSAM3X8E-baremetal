// SerialUSBDescriptor.swift
// CDC-ACM descriptors for Arduino Due Native USB (UOTGHS) in bare-metal Swift.

public enum SerialUSBDescriptor {

    // USB descriptor types
    public static let DESC_DEVICE: UInt8        = 0x01
    public static let DESC_CONFIGURATION: UInt8 = 0x02
    public static let DESC_STRING: UInt8        = 0x03
    private static let DESC_INTERFACE: UInt8    = 0x04
    private static let DESC_ENDPOINT: UInt8     = 0x05
    private static let DESC_IAD: UInt8          = 0x0B

    // CDC class-specific descriptor types
    private static let CS_INTERFACE: UInt8 = 0x24
    private static let CS_ENDPOINT: UInt8  = 0x25

    // Requests
    public static let REQ_GET_DESCRIPTOR: UInt8 = 0x06

    // VID/PID (você pode trocar depois)
    public static let VID: UInt16 = 0x2341
    public static let PID: UInt16 = 0x003E

    // Endpoints
    public static let EP_CDC_NOTIFY: UInt8 = 1 // Interrupt IN
    public static let EP_CDC_OUT: UInt8    = 2 // Bulk OUT
    public static let EP_CDC_IN: UInt8     = 3 // Bulk IN

    // Packet sizes
    public static let EP0_SIZE: UInt16  = 64
    public static let BULK_SIZE: UInt16 = 64
    public static let INT_SIZE: UInt16  = 8

    // ---------- Device Descriptor ----------
    public static let device: [UInt8] = [
        18, DESC_DEVICE,
        0x00, 0x02,                       // bcdUSB = 2.00
        0x00,                             // bDeviceClass (defined at interface)
        0x00,
        0x00,
        UInt8(truncatingIfNeeded: EP0_SIZE), // bMaxPacketSize0
        lo(VID), hi(VID),
        lo(PID), hi(PID),
        0x00, 0x01,                       // bcdDevice = 1.00
        0x01,                             // iManufacturer
        0x02,                             // iProduct
        0x03,                             // iSerialNumber
        0x01                              // bNumConfigurations
    ]

    // ---------- Configuration Descriptor (CDC ACM) ----------
    public static let configuration: [UInt8] = {
        var b: [UInt8] = []
        b.reserveCapacity(9 + 8 + 9 + 5+5+4+5 + 7 + 9 + 7 + 7)

        func append(_ bytes: [UInt8]) { b.append(contentsOf: bytes) }

        // --- Config descriptor ---
        append([
            9, DESC_CONFIGURATION,
            0x00, 0x00,                   // wTotalLength (patch)
            0x02,                         // bNumInterfaces
            0x01,                         // bConfigurationValue
            0x00,                         // iConfiguration
            0x80,                         // bmAttributes
            50                            // bMaxPower (100mA)
        ])

        // --- (Recomendado) IAD para CDC (Interface Association Descriptor) ---
        // Agrupa IF0 (COMM) + IF1 (DATA)
        append([
            8, DESC_IAD,
            0x00,                         // bFirstInterface
            0x02,                         // bInterfaceCount
            0x02,                         // bFunctionClass (CDC)
            0x02,                         // bFunctionSubClass (ACM)
            0x01,                         // bFunctionProtocol
            0x00                          // iFunction
        ])

        // --- Interface 0: CDC COMM ---
        append([
            9, DESC_INTERFACE,
            0x00,                         // bInterfaceNumber
            0x00,                         // bAlternateSetting
            0x01,                         // bNumEndpoints
            0x02,                         // bInterfaceClass = CDC
            0x02,                         // bInterfaceSubClass = ACM
            0x01,                         // bInterfaceProtocol
            0x00                          // iInterface
        ])

        // CDC Header Functional Descriptor
        append([
            5, CS_INTERFACE,
            0x00,                         // Header subtype
            0x10, 0x01                    // CDC spec 1.10
        ])

        // CDC Call Management Functional Descriptor
        append([
            5, CS_INTERFACE,
            0x01,                         // Call Management subtype
            0x00,                         // bmCapabilities (0 = no call mgmt)
            0x01                          // bDataInterface = 1
        ])

        // CDC ACM Functional Descriptor
        append([
            4, CS_INTERFACE,
            0x02,                         // ACM subtype
            0x02                          // bmCapabilities
        ])

        // CDC Union Functional Descriptor
        append([
            5, CS_INTERFACE,
            0x06,                         // Union subtype
            0x00,                         // bMasterInterface
            0x01                          // bSlaveInterface0
        ])

        // Endpoint 1: Interrupt IN (notify)
        append([
            7, DESC_ENDPOINT,
            UInt8(0x80 | EP_CDC_NOTIFY),  // IN
            0x03,                         // Interrupt
            lo(INT_SIZE), hi(INT_SIZE),
            0x10                          // bInterval
        ])

        // --- Interface 1: CDC DATA ---
        append([
            9, DESC_INTERFACE,
            0x01,                         // bInterfaceNumber
            0x00,
            0x02,                         // 2 endpoints
            0x0A,                         // Data
            0x00,
            0x00,
            0x00
        ])

        // Endpoint 2: Bulk OUT
        append([
            7, DESC_ENDPOINT,
            EP_CDC_OUT,                   // OUT
            0x02,                         // Bulk
            lo(BULK_SIZE), hi(BULK_SIZE),
            0x00
        ])

        // Endpoint 3: Bulk IN
        append([
            7, DESC_ENDPOINT,
            UInt8(0x80 | EP_CDC_IN),      // IN
            0x02,
            lo(BULK_SIZE), hi(BULK_SIZE),
            0x00
        ])

        // Patch wTotalLength
        let total = UInt16(b.count)
        b[2] = lo(total)
        b[3] = hi(total)
        return b
    }()

    // ---------- String descriptors ----------
    public static let string0: [UInt8] = [ 4, DESC_STRING, 0x09, 0x04 ] // en-US

    public static let manufacturer = "Gustavo"
    public static let product      = "Due BareMetal SerialUSB"
    public static let serial       = "0001"

    public static func stringDescriptor(index: UInt8) -> [UInt8]? {
        switch index {
        case 0: return string0
        case 1: return makeString(manufacturer)
        case 2: return makeString(product)
        case 3: return makeString(serial)
        default: return nil
        }
    }

    // ---------- Descriptor router ----------
    public static func getDescriptor(type: UInt8, index: UInt8, maxLen: Int) -> [UInt8]? {
        let raw: [UInt8]?
        switch type {
        case DESC_DEVICE:        raw = device
        case DESC_CONFIGURATION: raw = configuration
        case DESC_STRING:        raw = stringDescriptor(index: index)
        default:                 raw = nil
        }

        guard var d = raw else { return nil }
        if d.count > maxLen { d = Array(d.prefix(maxLen)) }
        return d
    }

    // ---------- helpers ----------
    @inline(__always) private static func lo(_ v: UInt16) -> UInt8 { UInt8(truncatingIfNeeded: v & 0xFF) }
    @inline(__always) private static func hi(_ v: UInt16) -> UInt8 { UInt8(truncatingIfNeeded: (v >> 8) & 0xFF) }

    private static func makeString(_ s: String) -> [UInt8] {
        // UTF-16LE without BOM (correto inclusive para chars > 0xFFFF)
        let utf16 = Array(s.utf16)
        var out: [UInt8] = []
        out.reserveCapacity(2 + utf16.count * 2)
        out.append(0)              // len placeholder
        out.append(DESC_STRING)

        for u in utf16 {
            out.append(UInt8(truncatingIfNeeded: u & 0xFF))
            out.append(UInt8(truncatingIfNeeded: (u >> 8) & 0xFF))
        }

        out[0] = UInt8(out.count)
        return out
    }
}