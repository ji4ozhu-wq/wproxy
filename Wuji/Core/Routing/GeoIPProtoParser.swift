import Foundation

/// Errors thrown by `GeoIPProtoParser`.
///
/// Every case is recoverable: the updater turns them into `lastError` and keeps the
/// previous dataset, so a malformed or truncated download can never corrupt the app.
enum GeoIPProtoError: Error, Equatable, LocalizedError {
    case emptyPayload
    case truncated
    case malformedVarint
    case invalidFieldNumber
    case unsupportedWireType(Int)
    case noEntries
    case missingCountryCode
    case invalidRange(Int)

    var errorDescription: String? {
        switch self {
        case .emptyPayload:
            return "the GeoIP payload is empty"
        case .truncated:
            return "the GeoIP payload is truncated"
        case .malformedVarint:
            return "the GeoIP payload contains a malformed protobuf varint"
        case .invalidFieldNumber:
            return "the GeoIP payload contains an invalid protobuf field number"
        case .unsupportedWireType(let wireType):
            return "the GeoIP payload uses unsupported protobuf wire type \(wireType)"
        case .noEntries:
            return "the GeoIP payload contains no country entries"
        case .missingCountryCode:
            return "a GeoIP entry has no country code"
        case .invalidRange(let offset):
            return "a GeoIP entry range is outside the payload (offset \(offset))"
        }
    }
}

/// One entry of a v2ray `GeoIPList` — the format of v2fly/geoip `geoip.dat`.
///
/// `payloadRange` is the byte range of the inner `GeoIP` message *inside the source
/// file*. The pipeline never decodes the thousands of CIDR messages: it only needs
/// the list of entries (code + a cheap CIDR count for the picker) and the raw bytes
/// of the entries the user selected. Copying those ranges into a new list produces a
/// valid `geoip.dat` that Xray can match with `ext:<file>:<code>` rule targets.
struct GeoIPListEntry: Equatable, Sendable {
    /// Uppercased list code: `"CN"`, `"JP"`, `"PRIVATE"`, `"TEST"`, `"ZZ"`.
    let code: String
    /// Byte range of the inner `GeoIP` message payload (without the outer tag/length).
    let payloadRange: Range<Int>
    /// Number of `CIDR` items in this entry (cheap `field 2` count, no decoding).
    let cidrCount: Int
}

/// Scans/assembles v2ray `GeoIPList` protobuf files — the format of v2fly/geoip
/// `geoip.dat`.
///
/// Schema (see https://github.com/v2fly/v2ray-core/blob/master/app/router/config.proto):
///
///     message GeoIPList { repeated GeoIP entry = 1; }
///     message GeoIP {
///       string country_code = 1;   // "CN"
///       repeated CIDR cidr = 2;
///     }
///     message CIDR {
///       bytes ip = 1;              // 4 bytes IPv4, 16 bytes IPv6, network order
///       uint32 prefix = 2;         // 0...32 / 0...128
///     }
///
/// Wire format: every field starts with `varint(tag = field_number << 3 | wire_type)`
/// followed by its payload for wire types 0 (varint), 1 (fixed64), 2 (length-
/// delimited) and 5 (fixed32). The scanner is deliberately defensive: it bounds-
/// checks every read, skips unknown field numbers (so a future upstream schema
/// change does not break the app) and throws a typed error for truncated payloads
/// instead of trapping.
///
/// The parser is pure Swift (no third-party dependency) and is also compiled into
/// the tunnel extension via the shared `Wuji/Core/Routing` source group.
enum GeoIPProtoParser {
    /// Lists every entry with its raw payload range; preserves upstream order.
    static func entries(in data: Data) throws -> [GeoIPListEntry] {
        guard !data.isEmpty else { throw GeoIPProtoError.emptyPayload }
        let bytes = [UInt8](data)
        var reader = WireReader(bytes: bytes)
        var entries: [GeoIPListEntry] = []

        while !reader.isAtEnd {
            let (field, wireType) = try reader.readTag()
            guard field == 1, wireType == 2 else {
                // Unknown top-level fields (or a known field with a different wire
                // type) are skipped so the payload can evolve upstream.
                try reader.skip(wireType: wireType)
                continue
            }
            let range = try reader.readRange()
            entries.append(try parseEntry(bytes: bytes, range: range))
        }

        guard !entries.isEmpty else { throw GeoIPProtoError.noEntries }
        return entries
    }

    /// Returns `[countryCode: cidrCount]` for every entry (metadata for the picker).
    /// Duplicate codes (not produced by v2fly) are merged.
    static func countryCounts(in data: Data) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in try entries(in: data) {
            counts[entry.code, default: 0] += entry.cidrCount
        }
        return counts
    }

    /// Builds a new `GeoIPList` from selected entries by copying their raw payload
    /// bytes verbatim (no CIDR decoding/re-encoding). The result is a valid
    /// `geoip.dat` for the chosen lists only, which is what the tunnel hands to
    /// Xray via `xray.location.asset` + `ext:<file>:<code>` rule targets.
    static func assembleList(from data: Data, entries: [GeoIPListEntry]) throws -> Data {
        let bytes = [UInt8](data)
        var output = Data()
        output.reserveCapacity(entries.reduce(0) { $0 + $1.payloadRange.count + 4 })
        for entry in entries {
            guard entry.payloadRange.lowerBound >= 0,
                  entry.payloadRange.upperBound <= bytes.count,
                  !entry.payloadRange.isEmpty else {
                throw GeoIPProtoError.invalidRange(entry.payloadRange.lowerBound)
            }
            appendVarint(UInt64((1 << 3) | 2), to: &output)  // field 1, wire type 2
            appendVarint(UInt64(entry.payloadRange.count), to: &output)
            output.append(contentsOf: bytes[entry.payloadRange])
        }
        return output
    }

    // MARK: - Entry scanning

    private static func parseEntry(bytes: [UInt8], range: Range<Int>) throws -> GeoIPListEntry {
        var reader = WireReader(bytes: bytes, start: range.lowerBound, end: range.upperBound)
        var code: String?
        var cidrCount = 0

        while !reader.isAtEnd {
            let (field, wireType) = try reader.readTag()
            switch (field, wireType) {
            case (1, 2):
                let codeRange = try reader.readRange()
                code = String(decoding: bytes[codeRange], as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
            case (2, 2):
                cidrCount += 1
                _ = try reader.readRange()  // skip the CIDR payload; not decoded here
            default:
                try reader.skip(wireType: wireType)
            }
        }

        guard let code, !code.isEmpty else { throw GeoIPProtoError.missingCountryCode }
        return GeoIPListEntry(code: code, payloadRange: range, cidrCount: cidrCount)
    }

    private static func appendVarint(_ value: UInt64, to data: inout Data) {
        var remaining = value
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            data.append(byte)
        } while remaining != 0
    }
}

// MARK: - Protobuf primitives

/// Minimal bounds-checked protobuf wire reader over a byte buffer. Nested messages
/// reuse the same buffer through `start`/`end` instead of copying their payload.
private struct WireReader {
    let bytes: [UInt8]
    private(set) var index: Int
    let end: Int

    init(bytes: [UInt8], start: Int = 0, end: Int? = nil) {
        self.bytes = bytes
        self.index = start
        self.end = min(end ?? bytes.count, bytes.count)
    }

    var isAtEnd: Bool { index >= end }
    var remaining: Int { end - index }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard index < end else { throw GeoIPProtoError.truncated }
            let byte = bytes[index]
            index += 1
            if shift == 63, byte & 0x7E != 0 {
                throw GeoIPProtoError.malformedVarint
            }
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            guard shift <= 63 else { throw GeoIPProtoError.malformedVarint }
        }
    }

    mutating func readTag() throws -> (field: Int, wireType: Int) {
        let tag = try readVarint()
        let field = Int(tag >> 3)
        let wireType = Int(tag & 0x07)
        guard field > 0 else { throw GeoIPProtoError.invalidFieldNumber }
        return (field, wireType)
    }

    /// Consumes a length-delimited field and returns its absolute byte range.
    mutating func readRange() throws -> Range<Int> {
        let length = try readVarint()
        guard length <= UInt64(remaining) else { throw GeoIPProtoError.truncated }
        let start = index
        index += Int(length)
        return start..<index
    }

    mutating func skip(wireType: Int) throws {
        switch wireType {
        case 0:
            _ = try readVarint()
        case 1:
            guard remaining >= 8 else { throw GeoIPProtoError.truncated }
            index += 8
        case 2:
            _ = try readRange()
        case 5:
            guard remaining >= 4 else { throw GeoIPProtoError.truncated }
            index += 4
        default:
            // Wire types 3/4 (deprecated groups) have no safe length to skip.
            throw GeoIPProtoError.unsupportedWireType(wireType)
        }
    }
}
