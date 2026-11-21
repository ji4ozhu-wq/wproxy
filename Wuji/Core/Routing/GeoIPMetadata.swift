import Foundation

/// Metadata for the country-list snapshot (`geoip_countries.json`).
///
/// The dataset itself is the raw v2ray `geoip.dat` (bundled as `geoip.dat.gz`,
/// materialized into the App Group container). This small sidecar carries the
/// per-list CIDR counts the country picker displays plus the provenance/licence
/// fields. It exists both in the app bundle (produced by
/// `tools/prepare_geoip_assets.py`) and in the App Group container (rewritten by
/// `GeoIPUpdater` / `GeoIPAssetManager` after a fresh dataset is installed).
struct GeoIPCountryMetadata: Codable, Equatable, Sendable {
    var version: Int
    /// Human-readable provenance (v2fly/geoip release branch + DB-IP Lite).
    var source: String
    var license: String?
    /// First 12 hex chars of the dataset sha256 — stable identifier for the data.
    var dataVersion: String?
    /// Full sha256 of the decompressed `geoip.dat`, used to verify the bundle and
    /// detect a stale App Group copy.
    var sha256: String?
    var generated: String?
    /// Number of lists that are real countries (2-letter code, not ZZ).
    var countryCount: Int?
    /// Number of lists in total (countries + PRIVATE + TEST + ZZ) = 253.
    var entryCount: Int?
    /// List code (`"CN"`, `"PRIVATE"`, …) → number of CIDRs in the entry.
    var countries: [String: Int]
}

/// Loads/saves `geoip_countries.json` and holds the file-layout constants shared by
/// the app bundle and the App Group container.
enum GeoIPMetadataStore {
    static let fileName = "geoip_countries.json"

    /// Lists that are not ISO 3166-1 countries and must not appear in the picker.
    static let nonCountryCodes: Set<String> = ["TEST", "PRIVATE", "ZZ"]

    static func isCountryCode(_ code: String) -> Bool {
        guard code.count == 2 else { return false }
        let scalars = code.unicodeScalars
        guard scalars.allSatisfy({ (65...90).contains($0.value) }) else { return false }
        return !nonCountryCodes.contains(code)
    }

    static func load(from url: URL) -> GeoIPCountryMetadata? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return try? JSONDecoder().decode(GeoIPCountryMetadata.self, from: data)
    }

    /// Metadata shipped inside the app bundle (used before the first launch install
    /// and as a fallback when the App Group copy is missing/corrupt).
    static func bundled(_ bundle: Bundle = .main) -> GeoIPCountryMetadata? {
        guard let url = bundle.url(forResource: "geoip_countries", withExtension: "json") else {
            return nil
        }
        return load(from: url)
    }

    static func write(_ metadata: GeoIPCountryMetadata,
                      to containerURL: URL,
                      fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(metadata)
        let url = containerURL.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Builds a metadata record from a fresh dataset scan.
    static func make(source: String,
                     license: String?,
                     dataVersion: String?,
                     sha256: String?,
                     generated: String?,
                     counts: [String: Int]) -> GeoIPCountryMetadata {
        GeoIPCountryMetadata(
            version: 1,
            source: source,
            license: license,
            dataVersion: dataVersion,
            sha256: sha256,
            generated: generated,
            countryCount: counts.keys.filter(isCountryCode).count,
            entryCount: counts.count,
            countries: counts
        )
    }

    /// Total number of CIDRs across every list (countries + pseudo lists).
    static func totalCIDRCount(_ metadata: GeoIPCountryMetadata) -> Int {
        metadata.countries.values.reduce(0, +)
    }
}
