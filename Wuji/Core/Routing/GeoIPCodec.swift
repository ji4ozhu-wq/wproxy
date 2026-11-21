import Compression
import Foundation

/// gzip container helpers for the GeoIP assets.
///
/// The raw v2ray `geoip.dat` (23.8 MB) is shipped gzip-compressed as
/// `Wuji/Resources/geoip.dat.gz` (~4.4 MB) so the app bundle stays compact; the
/// first launch decompresses it into the App Group container where Xray and the
/// asset extractor read it. `GeoIPAssetManager` also uses this type to verify the
/// bundled payload against the metadata sha256.
///
/// Apple's `Compression` framework only understands the raw DEFLATE stream
/// (RFC 1951), so this type implements the small gzip envelope (RFC 1952) on top:
/// header parsing (including FEXTRA/FNAME/FCOMMENT/FHCRC), the 8-byte trailer with
/// CRC-32 and ISIZE, and a gzip writer used by tests/tools. Both are validated so a
/// truncated or corrupted asset is rejected instead of being decoded as garbage.
enum GeoIPCodec {
    enum CodecError: Error, Equatable, LocalizedError {
        case truncated
        case notGzip
        case unsupportedCompressionMethod(UInt8)
        case unsupportedFlags(UInt8)
        case decompressionFailed
        case sizeMismatch(expected: Int, actual: Int)
        case checksumMismatch(expected: UInt32, actual: UInt32)
        case compressionFailed
        case emptyPayload

        var errorDescription: String? {
            switch self {
            case .truncated:
                return "the compressed payload is truncated"
            case .notGzip:
                return "the payload does not start with the gzip magic bytes"
            case .unsupportedCompressionMethod(let method):
                return "unsupported gzip compression method \(method)"
            case .unsupportedFlags(let flags):
                return "unsupported gzip flags \(flags)"
            case .decompressionFailed:
                return "DEFLATE decompression failed"
            case .sizeMismatch(let expected, let actual):
                return "gzip ISIZE \(expected) does not match the decoded size \(actual)"
            case .checksumMismatch(let expected, let actual):
                return String(format: "gzip CRC-32 mismatch (expected %08x, got %08x)", expected, actual)
            case .compressionFailed:
                return "DEFLATE compression failed"
            case .emptyPayload:
                return "the payload is empty"
            }
        }
    }

    private static let gzipMagic: (UInt8, UInt8) = (0x1F, 0x8B)
    private static let gzipHeader: [UInt8] = [
        0x1F, 0x8B,  // magic
        0x08,        // CM = DEFLATE
        0x00,        // FLG
        0x00, 0x00, 0x00, 0x00,  // MTIME (deterministic: zero)
        0x00,        // XFL
        0x03         // OS = Unix
    ]

    // MARK: - Public API

    static func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == gzipMagic.0 && data[data.startIndex + 1] == gzipMagic.1
    }

    /// Decompresses the payload when it is gzip, otherwise returns it unchanged.
    /// Used by `CountryDirectory` so both the gzip snapshot and a plain JSON
    /// fallback (`--plain` generator output / legacy files) load the same way.
    static func decompressedIfNeeded(_ data: Data) throws -> Data {
        guard isGzip(data) else { return data }
        return try gunzip(data)
    }

    /// Wraps a DEFLATE stream in a minimal gzip container (header + CRC-32 + ISIZE).
    static func gunzip(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18 else { throw CodecError.truncated }
        guard bytes[0] == gzipMagic.0, bytes[1] == gzipMagic.1 else { throw CodecError.notGzip }
        guard bytes[2] == 8 else { throw CodecError.unsupportedCompressionMethod(bytes[2]) }
        let flags = bytes[3]
        // Only FHCRC is flagged here; FEXTRA/FNAME/FCOMMENT are skipped below.
        guard flags & ~(0x02 | 0x04 | 0x08 | 0x10) == 0 else { throw CodecError.unsupportedFlags(flags) }

        var cursor = 10
        if flags & 0x04 != 0 {  // FEXTRA
            guard cursor + 2 <= bytes.count else { throw CodecError.truncated }
            let extraLength = Int(bytes[cursor]) | (Int(bytes[cursor + 1]) << 8)
            cursor += 2 + extraLength
            guard cursor <= bytes.count else { throw CodecError.truncated }
        }
        if flags & 0x08 != 0 {  // FNAME
            cursor = try skipZeroTerminated(bytes, from: cursor)
        }
        if flags & 0x10 != 0 {  // FCOMMENT
            cursor = try skipZeroTerminated(bytes, from: cursor)
        }
        if flags & 0x02 != 0 {  // FHCRC
            cursor += 2
        }
        guard cursor + 8 <= bytes.count else { throw CodecError.truncated }

        let isize = UInt32(littleEndian: bytes.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: bytes.count - 4, as: UInt32.self)
        })
        let expectedCRC = UInt32(littleEndian: bytes.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: bytes.count - 8, as: UInt32.self)
        })
        let deflate = Array(bytes[cursor..<(bytes.count - 8)])
        guard !deflate.isEmpty else { throw CodecError.emptyPayload }

        let decoded = try inflate(deflate, expectedSize: Int(isize))
        guard decoded.count == Int(isize) else {
            throw CodecError.sizeMismatch(expected: Int(isize), actual: decoded.count)
        }
        let actualCRC = crc32(decoded)
        guard actualCRC == expectedCRC else {
            throw CodecError.checksumMismatch(expected: expectedCRC, actual: actualCRC)
        }
        return decoded
    }

    /// Compresses JSON bytes into a gzip container (deterministic: zero MTIME).
    static func gzip(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw CodecError.emptyPayload }
        let deflated = try deflate(data)
        var output = Data(gzipHeader)
        output.append(contentsOf: deflated)
        var trailer = [UInt8]()
        trailer.reserveCapacity(8)
        appendLittleEndian(crc32(data), to: &trailer)
        appendLittleEndian(UInt32(truncatingIfNeeded: data.count), to: &trailer)
        output.append(contentsOf: trailer)
        return output
    }

    // MARK: - CRC-32

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 { crc32(bytes: data) }

    private static func crc32<C: Collection>(bytes: C) -> UInt32 where C.Element == UInt8 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - DEFLATE

    private static func inflate(_ deflate: [UInt8], expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { throw CodecError.emptyPayload }
        var output = Data(count: expectedSize)
        let decoded: Int = output.withUnsafeMutableBytes { destination in
            deflate.withUnsafeBytes { source in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBase, expectedSize,
                    sourceBase, deflate.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard decoded == expectedSize else { throw CodecError.decompressionFailed }
        output.count = decoded
        return output
    }

    private static func deflate(_ data: Data) throws -> [UInt8] {
        var capacity = max(1024, data.count / 2)
        let maximum = max(capacity, data.count * 2)
        while capacity <= maximum {
            var output = [UInt8](repeating: 0, count: capacity)
            let encoded: Int = data.withUnsafeBytes { source in
                output.withUnsafeMutableBufferPointer { destination in
                    guard let destinationBase = destination.baseAddress,
                          let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_encode_buffer(
                        destinationBase, capacity,
                        sourceBase, data.count,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            if encoded > 0 {
                return Array(output[0..<encoded])
            }
            capacity *= 2
        }
        throw CodecError.compressionFailed
    }

    // MARK: - Helpers

    private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) throws -> Int {
        var cursor = start
        while cursor < bytes.count {
            if bytes[cursor] == 0 { return cursor + 1 }
            cursor += 1
        }
        throw CodecError.truncated
    }

    private static func appendLittleEndian(_ value: UInt32, to bytes: inout [UInt8]) {
        bytes.append(UInt8(value & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 24) & 0xFF))
    }
}
