//
// EEFC.swift — Key/Value storage on a reserved flash page using SAM3X8E EEFC1.
//
// Goals:
// - Defensive + informative API (explicit errors, detailed failure reasons).
// - "UserDefaults-like" single-page KV store: save/load by string key.
// - Convenience helpers for common types (String, U32, Bool, Bytes).
// - Provide a convenient error name/message for logging/UI.
//
// Project rules:
// - Hardware addresses/sizes stay in ATSAM3X8E.swift.
// - This file contains logic + on-flash format only.
//
// Notes:
// - This writes the entire reserved page on each save/remove.
// - Flash endurance is limited: do not write often.
// - Make sure linker.ld reserves ATSAM3X8E.NVM.PAGE_ADDR..+PAGE_SIZE.
//
// Dependencies:
// - MMIO.swift: bm_read32/bm_write32, bm_dsb/bm_isb, waitUntil()
// - ATSAM3X8E.swift: EEFC regs/bitfields + NVM page geometry
//

public enum EEFCError: Error {
    // General / configuration
    case invalidKey
    case keyTooLong(Int)              // actual length
    case valueTooLarge(Int)           // actual bytes
    case noRoom(missing: Int)         // how many bytes short
    case internalInvariant(String)

    // Load errors (format / integrity)
    case empty
    case badMagic
    case unsupportedVersion(found: U32)
    case corruptHeader
    case corruptPayload
    case crcMismatch(expected: U32, got: U32)

    // Key/value semantics
    case keyNotFound(String)
    case typeMismatch(expected: EEFCStorage.ValueType, got: EEFCStorage.ValueType)
    case invalidUTF8

    // Flash / EEFC failures
    case timeout
    case commandError
    case lockError

    // MARK: - Convenient name/message for logging

    /// Short stable identifier (good for logs / UI keys).
    public var name: String {
        switch self {
        case .invalidKey: return "invalid_key"
        case .keyTooLong: return "key_too_long"
        case .valueTooLarge: return "value_too_large"
        case .noRoom: return "no_room"
        case .internalInvariant: return "internal_invariant"

        case .empty: return "empty"
        case .badMagic: return "bad_magic"
        case .unsupportedVersion: return "unsupported_version"
        case .corruptHeader: return "corrupt_header"
        case .corruptPayload: return "corrupt_payload"
        case .crcMismatch: return "crc_mismatch"

        case .keyNotFound: return "key_not_found"
        case .typeMismatch: return "type_mismatch"
        case .invalidUTF8: return "invalid_utf8"

        case .timeout: return "timeout"
        case .commandError: return "command_error"
        case .lockError: return "lock_error"
        }
    }

    /// Human-friendly message for printing.
    public var message: String {
        switch self {
        case .invalidKey:
            return "Invalid key (empty or contains unsupported characters)."
        case .keyTooLong(let n):
            return "Key too long (\(n) bytes)."
        case .valueTooLarge(let n):
            return "Value too large (\(n) bytes)."
        case .noRoom(let missing):
            return "Not enough room in the flash page (missing \(missing) bytes)."
        case .internalInvariant(let s):
            return "Internal invariant failed: \(s)"

        case .empty:
            return "Storage is empty."
        case .badMagic:
            return "Storage header magic mismatch (not initialized)."
        case .unsupportedVersion(let v):
            return "Unsupported storage version: \(v)."
        case .corruptHeader:
            return "Storage header is corrupt."
        case .corruptPayload:
            return "Storage payload is corrupt."
        case .crcMismatch(let expected, let got):
            return "CRC mismatch (expected \(expected), got \(got))."

        case .keyNotFound(let k):
            return "Key not found: \(k)"
        case .typeMismatch(let expected, let got):
            return "Type mismatch (expected \(expected), got \(got))."
        case .invalidUTF8:
            return "Invalid UTF-8 string data."

        case .timeout:
            return "Flash controller timeout."
        case .commandError:
            return "Flash controller reported a command error."
        case .lockError:
            return "Flash controller reported a lock error."
        }
    }
}

public enum EEFCLoadResult<T> {
    case failure(EEFCError)
    case success(T)
}

public struct EEFCStorage {

    // MARK: - On-flash format (not hardware)

    private static let magic: U32 = 0x4545_4B56 // "EEKV"
    private static let version: U32 = 1

    private static let headerWords: U32 = 4
    private static var headerBytes: U32 { headerWords * 4 }

    public enum ValueType: UInt8 {
        case bytes  = 1
        case string = 2
        case u32    = 3
        case bool   = 4
    }

    // MARK: - Hardware config (from ATSAM3X8E.swift)

    private let pageAddr: U32
    private let pageSize: U32
    private let payloadMax: Int
    private let bank1PageIndex: U32

    public init(
        pageAddr: U32 = ATSAM3X8E.NVM.PAGE_ADDR,
        pageSize: U32 = ATSAM3X8E.NVM.PAGE_SIZE,
        bank1PageIndex: U32 = ATSAM3X8E.NVM.BANK1_PAGE_INDEX
    ) {
        self.pageAddr = pageAddr
        self.pageSize = pageSize
        self.bank1PageIndex = bank1PageIndex
        self.payloadMax = Int(pageSize - Self.headerBytes)
    }

    // MARK: - Public API (generic)

    public func load(key: String) -> EEFCLoadResult<[UInt8]> {
        guard validateKey(key) else { return .failure(.invalidKey) }
        let keyBytes = utf8Bytes(key)

        let page = readPage()
        let hdr = parseHeader(page)
        switch hdr {
        case .failure(let e): return .failure(e)
        case .success(let h):
            let used = Int(h.usedBytes)
            if used == 0 { return .failure(.empty) }
            if used > payloadMax { return .failure(.corruptHeader) }

            let payload = slice(page, from: Int(Self.headerBytes), count: used)
            let got = crc32(payload)
            if got != h.crc { return .failure(.crcMismatch(expected: h.crc, got: got)) }

            if let found = findEntry(payload: payload, keyBytes: keyBytes) {
                return .success(found.valueBytes)
            }
            return .failure(.keyNotFound(key))
        }
    }

    public func save(key: String, value: [UInt8], type: ValueType = .bytes) -> EEFCError? {
        guard validateKey(key) else { return .invalidKey }
        let keyBytes = utf8Bytes(key)

        // Defensive size checks
        if keyBytes.count > 255 { return .keyTooLong(keyBytes.count) }
        if value.count > 0xFFFF { return .valueTooLarge(value.count) }

        // Load existing map (or empty if not initialized)
        let oldPayloadResult = readValidPayloadOrEmpty()
        switch oldPayloadResult {
        case .failure(let e):
            // If totally empty/uninitialized, we can still proceed from empty payload.
            // But if it's corrupted, fail (defensive).
            switch e {
            case .empty, .badMagic:
                break
            default:
                return e
            }
        case .success:
            break
        }

        var payload = oldPayloadResult.payloadOrEmpty()

        // Remove existing entry if present
        payload = removeEntry(payload: payload, keyBytes: keyBytes)

        // Add new entry
        let entry = encodeEntry(keyBytes: keyBytes, type: type, valueBytes: value)

        // Capacity check
        let newUsed = payload.count + entry.count
        if newUsed > payloadMax {
            return .noRoom(missing: newUsed - payloadMax)
        }

        payload.append(contentsOf: entry)

        // Write full page
        let err = writePayload(payload)
        return err
    }

    public func remove(key: String) -> EEFCError? {
        guard validateKey(key) else { return .invalidKey }
        let keyBytes = utf8Bytes(key)

        let oldPayloadResult = readValidPayloadOrEmpty()
        switch oldPayloadResult {
        case .failure(let e):
            switch e {
            case .empty, .badMagic:
                return .keyNotFound(key)
            default:
                return e
            }
        case .success(let payload):
            let newPayload = removeEntry(payload: payload, keyBytes: keyBytes)
            if newPayload.count == payload.count {
                return .keyNotFound(key)
            }
            return writePayload(newPayload)
        }
    }

    public func clear() -> EEFCError? {
        return writePayload([])
    }

    /// Remove all keys and values from the reserved flash page.
    /// This is an alias for `clear()` provided for API clarity.
    public func removeAll() -> EEFCError? {
        return clear()
    }

    public func contains(key: String) -> Bool {
        switch load(key: key) {
        case .success: return true
        case .failure: return false
        }
    }

    // MARK: - Convenience typed API

    public func loadString(key: String) -> EEFCLoadResult<String> {
        let r = load(key: key)
        switch r {
        case .failure(let e): return .failure(e)
        case .success(let bytes):
            // Expect "string" type by convention (we don't store type separately in this load path),
            // so we decode as UTF-8 and validate.
            if let s = stringFromUTF8(bytes) {
                return .success(s)
            }
            return .failure(.invalidUTF8)
        }
    }

    public func save(key: String, value: String) -> EEFCError? {
        let bytes = utf8Bytes(value)
        return save(key: key, value: bytes, type: .string)
    }

    public func loadU32(key: String) -> EEFCLoadResult<U32> {
        let r = load(key: key)
        switch r {
        case .failure(let e): return .failure(e)
        case .success(let bytes):
            if bytes.count != 4 { return .failure(.corruptPayload) }
            let v = u32LE(bytes, 0)
            return .success(v)
        }
    }

    public func save(key: String, value: U32) -> EEFCError? {
        var bytes = [UInt8]()
        bytes.reserveCapacity(4)
        appendU32LE(value, to: &bytes)
        return save(key: key, value: bytes, type: .u32)
    }

    public func loadBool(key: String) -> EEFCLoadResult<Bool> {
        let r = load(key: key)
        switch r {
        case .failure(let e): return .failure(e)
        case .success(let bytes):
            if bytes.count != 1 { return .failure(.corruptPayload) }
            return .success(bytes[0] != 0)
        }
    }

    public func save(key: String, value: Bool) -> EEFCError? {
        let bytes: [UInt8] = [value ? 1 : 0]
        return save(key: key, value: bytes, type: .bool)
    }

    // MARK: - Internals: header parsing

    private struct Header {
        let usedBytes: U32
        let crc: U32
        let version: U32
    }

    private func parseHeader(_ page: [UInt8]) -> EEFCLoadResult<Header> {
        if page.count != Int(pageSize) { return .failure(.internalInvariant("page size mismatch")) }

        let m = u32LE(page, 0)
        if m == 0xFFFF_FFFF { return .failure(.empty) } // erased page
        if m != Self.magic { return .failure(.badMagic) }

        let v = u32LE(page, 4)
        if v != Self.version { return .failure(.unsupportedVersion(found: v)) }

        let used = u32LE(page, 8)
        let crc = u32LE(page, 12)

        if used > U32(payloadMax) { return .failure(.corruptHeader) }

        return .success(Header(usedBytes: used, crc: crc, version: v))
    }

    // MARK: - Internals: read/write payload

    private enum PayloadRead {
        case success([UInt8])
        case failure(EEFCError)

        func payloadOrEmpty() -> [UInt8] {
            switch self {
            case .success(let p): return p
            case .failure: return []
            }
        }
    }

    private func readValidPayloadOrEmpty() -> PayloadRead {
        let page = readPage()
        let hdr = parseHeader(page)
        switch hdr {
        case .failure(let e):
            return .failure(e)
        case .success(let h):
            let used = Int(h.usedBytes)
            if used == 0 { return .failure(.empty) }
            let payload = slice(page, from: Int(Self.headerBytes), count: used)
            let got = crc32(payload)
            if got != h.crc { return .failure(.crcMismatch(expected: h.crc, got: got)) }
            return .success(payload)
        }
    }

    private func writePayload(_ payload: [UInt8]) -> EEFCError? {
        if payload.count > payloadMax { return .valueTooLarge(payload.count) }

        if !waitReady(timeout: 5_000_000) { return .timeout }

        // Build full page image: [header][payload][padding=0xFF]
        var page = [UInt8]()
        page.reserveCapacity(Int(pageSize))

        // Header placeholder
        appendU32LE(Self.magic, to: &page)
        appendU32LE(Self.version, to: &page)
        appendU32LE(U32(payload.count), to: &page)
        appendU32LE(crc32(payload), to: &page)

        // Payload
        page.append(contentsOf: payload)

        // Padding with 0xFF WITHOUT using repeating initializer (avoids __aeabi_memset issues)
        let total = Int(pageSize)
        if page.count < total {
            let padCount = total - page.count
            var i = 0
            while i < padCount {
                page.append(0xFF)
                i += 1
            }
        }

        // Copy page image into flash write buffer (memory-mapped flash)
        var off: U32 = 0
        while off < pageSize {
            let w = u32LE(page, Int(off))
            bm_write32(pageAddr + off, w)
            off &+= 4
        }

        bm_dsb()
        bm_isb()

        // EEFC command: Erase Page and Write Page (EWP) on EEFC1
        let cmd =
            ATSAM3X8E.EEFC.FCR_FKEY_PASSWD |
            (bank1PageIndex << ATSAM3X8E.EEFC.FCR_FARG_SHIFT) |
            (ATSAM3X8E.EEFC.FCMD_EWP & ATSAM3X8E.EEFC.FCR_FCMD_MASK)

        bm_write32(ATSAM3X8E.EEFC1.FCR, cmd)

        if !waitReady(timeout: 20_000_000) { return .timeout }

        let fsr = bm_read32(ATSAM3X8E.EEFC1.FSR)
        if (fsr & ATSAM3X8E.EEFC.FSR_FCMDE) != 0 { return .commandError }
        if (fsr & ATSAM3X8E.EEFC.FSR_FLOCKE) != 0 { return .lockError }

        return nil
    }

    @inline(__always)
    private func waitReady(timeout: U32) -> Bool {
        waitUntil(timeout) {
            (bm_read32(ATSAM3X8E.EEFC1.FSR) & ATSAM3X8E.EEFC.FSR_FRDY) != 0
        }
    }

    // MARK: - Internals: entry encode/parse

    private func encodeEntry(keyBytes: [UInt8], type: ValueType, valueBytes: [UInt8]) -> [UInt8] {
        // Entry header: keyLen (u8), type (u8), valueLen (u16 LE)
        var out = [UInt8]()
        out.reserveCapacity(1 + 1 + 2 + keyBytes.count + valueBytes.count)

        out.append(UInt8(truncatingIfNeeded: keyBytes.count))
        out.append(type.rawValue)
        out.append(UInt8(valueBytes.count & 0xFF))
        out.append(UInt8((valueBytes.count >> 8) & 0xFF))

        out.append(contentsOf: keyBytes)
        out.append(contentsOf: valueBytes)
        return out
    }

    private struct FoundEntry {
        let type: ValueType
        let valueBytes: [UInt8]
    }

    private func findEntry(payload: [UInt8], keyBytes: [UInt8]) -> FoundEntry? {
        var i = 0
        while i + 4 <= payload.count {
            let keyLen = Int(payload[i + 0])
            let typeRaw = payload[i + 1]
            let valueLen = Int(payload[i + 2]) | (Int(payload[i + 3]) << 8)

            let headerSize = 4
            let keyStart = i + headerSize
            let keyEnd = keyStart + keyLen
            let valStart = keyEnd
            let valEnd = valStart + valueLen

            if keyLen == 0 { return nil }
            if keyEnd > payload.count { return nil }
            if valEnd > payload.count { return nil }

            if keyLen == keyBytes.count {
                var match = true
                var k = 0
                while k < keyLen {
                    if payload[keyStart + k] != keyBytes[k] { match = false; break }
                    k += 1
                }
                if match {
                    guard let t = ValueType(rawValue: typeRaw) else { return nil }
                    let value = slice(payload, from: valStart, count: valueLen)
                    return FoundEntry(type: t, valueBytes: value)
                }
            }

            i = valEnd
        }
        return nil
    }

    private func removeEntry(payload: [UInt8], keyBytes: [UInt8]) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(payload.count)

        var i = 0
        while i + 4 <= payload.count {
            let keyLen = Int(payload[i + 0])
            let valueLen = Int(payload[i + 2]) | (Int(payload[i + 3]) << 8)
            let headerSize = 4

            let keyStart = i + headerSize
            let keyEnd = keyStart + keyLen
            let valEnd = keyEnd + valueLen

            if keyLen == 0 { return out } // stop on corruption defensively
            if keyEnd > payload.count { return out }
            if valEnd > payload.count { return out }

            var isTarget = (keyLen == keyBytes.count)
            if isTarget {
                var k = 0
                while k < keyLen {
                    if payload[keyStart + k] != keyBytes[k] { isTarget = false; break }
                    k += 1
                }
            }

            if !isTarget {
                // copy entry bytes as-is
                let entryLen = valEnd - i
                var j = 0
                while j < entryLen {
                    out.append(payload[i + j])
                    j += 1
                }
            }

            i = valEnd
        }

        return out
    }

    // MARK: - Internals: key validation

    private func validateKey(_ key: String) -> Bool {
        let b = utf8Bytes(key)
        if b.isEmpty { return false }
        // Simple safe charset: [A-Za-z0-9._-]
        // (avoids spaces/utf8 surprises in embedded storage)
        var i = 0
        while i < b.count {
            let c = b[i]
            let isAZ = (c >= 65 && c <= 90)
            let isaz = (c >= 97 && c <= 122)
            let is09 = (c >= 48 && c <= 57)
            let isOk = isAZ || isaz || is09 || c == 46 || c == 95 || c == 45
            if !isOk { return false }
            i += 1
        }
        return true
    }

    // MARK: - Internals: page read

    private func readPage() -> [UInt8] {
        let total = Int(pageSize)
        var out = [UInt8]()
        out.reserveCapacity(total)

        var off: U32 = 0
        while off < pageSize {
            let w = bm_read32(pageAddr + off)
            out.append(UInt8((w >> 0) & 0xFF))
            out.append(UInt8((w >> 8) & 0xFF))
            out.append(UInt8((w >> 16) & 0xFF))
            out.append(UInt8((w >> 24) & 0xFF))
            off &+= 4
        }

        // Ensure exact length
        if out.count > total { out.removeLast(out.count - total) }
        return out
    }

    // MARK: - Small utilities (no Foundation)

    private func slice(_ a: [UInt8], from: Int, count: Int) -> [UInt8] {
        if count <= 0 { return [] }
        var out = [UInt8]()
        out.reserveCapacity(count)
        var i = 0
        while i < count {
            out.append(a[from + i])
            i += 1
        }
        return out
    }

    private func utf8Bytes(_ s: String) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(s.utf8.count)
        for b in s.utf8 { out.append(b) }
        return out
    }

    private func stringFromUTF8(_ bytes: [UInt8]) -> String? {
        // Embedded Swift can construct String from UTF8 bytes (no Foundation).
        // This initializer is available in stdlib:
        // String(decoding: bytes, as: UTF8.self)
        // But to be safe, we validate by re-encoding and comparing length.
        let s = String(decoding: bytes, as: UTF8.self)
        // If bytes contained invalid sequences, String(decoding:) replaces them.
        // We detect that by round-tripping.
        let round = utf8Bytes(s)
        if round.count != bytes.count { return nil }
        var i = 0
        while i < bytes.count {
            if round[i] != bytes[i] { return nil }
            i += 1
        }
        return s
    }

    private func u32LE(_ a: [UInt8], _ offset: Int) -> U32 {
        U32(a[offset + 0]) |
        (U32(a[offset + 1]) << 8) |
        (U32(a[offset + 2]) << 16) |
        (U32(a[offset + 3]) << 24)
    }

    private func appendU32LE(_ v: U32, to out: inout [UInt8]) {
        out.append(UInt8((v >> 0) & 0xFF))
        out.append(UInt8((v >> 8) & 0xFF))
        out.append(UInt8((v >> 16) & 0xFF))
        out.append(UInt8((v >> 24) & 0xFF))
    }

    // MARK: - CRC32 (small, tableless)

    private func crc32(_ bytes: [UInt8]) -> U32 {
        var crc: U32 = 0xFFFF_FFFF
        for b in bytes {
            crc ^= U32(b)
            var i = 0
            while i < 8 {
                let lsb = (crc & 1) != 0
                crc = (crc >> 1) ^ (lsb ? 0xEDB8_8320 : 0)
                i += 1
            }
        }
        return ~crc
    }
}