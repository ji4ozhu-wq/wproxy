import Foundation
import os

struct CountryInfo: Identifiable, Codable, Equatable, Sendable {
    var code: String   // ISO 3166-1 alpha-2, e.g. "CN"
    var name: String   // localized in the device UI language
    /// English name kept for search and as a glyph-safe fallback.
    var englishName: String = ""
    var cidrCount: Int
    var id: String { code }

    /// Regional-indicator flag emoji, derived from the ISO code.
    var flag: String {
        let scalars = code.uppercased().unicodeScalars
        guard scalars.count == 2, scalars.allSatisfy({ (65...90).contains($0.value) }) else { return "" }
        var result = ""
        for scalar in scalars {
            guard let flagScalar = UnicodeScalar(127_397 + scalar.value) else { return "" }
            result.unicodeScalars.append(flagScalar)
        }
        return result
    }
}

/// Provides the country/region list shown by the Routing picker.
///
/// The CIDR data itself is no longer decoded into memory: the app ships the raw
/// v2ray `geoip.dat` (gzipped) and `GeoIPAssetManager` extracts only the selected
/// lists at connect time for Xray's `ext:<file>:<cc>` routing rules. This type only
/// loads the small metadata sidecar (`geoip_countries.json`, ~3 KB) that maps list
/// code → CIDR count, with two sources:
///
/// 1. the App Group copy written by `GeoIPUpdater` / `GeoIPAssetManager` after the
///    bundled dataset is installed or refreshed (wins when readable);
/// 2. the copy bundled in `Wuji/Resources` (offline fallback).
///
/// A corrupt App Group metadata file is ignored in favour of the bundled one, so a
/// failed update can never take the picker down. `reload()` re-reads after an
/// install/update.
final class CountryDirectory {
    static let shared = CountryDirectory()

    static let resourceName = "geoip_countries"
    static let resourceExtension = "json"

    private static let log = Logger(subsystem: "com.juejin.ios.wuji", category: "country-data")

    private struct Snapshot {
        var countries: [CountryInfo]
        var source: String
        var generated: String?
        var dataVersion: String?
        var totalCIDRCount: Int
        var isOverride: Bool
    }

    private let bundle: Bundle
    private let explicitMetadataURL: URL?
    private let explicitIsOverride: Bool
    private let lock = NSLock()
    private var snapshot: Snapshot?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        self.explicitMetadataURL = nil
        self.explicitIsOverride = false
    }

    /// Test/utility initializer with an explicit metadata file.
    init(metadataURL: URL, isOverride: Bool = false) {
        self.bundle = .main
        self.explicitMetadataURL = metadataURL
        self.explicitIsOverride = isOverride
    }

    // MARK: - Public data

    /// All countries/territories with at least one prefix, sorted by localized name.
    /// Pseudo lists (`PRIVATE`, `TEST`, `ZZ`) are not countries and are filtered out.
    var countries: [CountryInfo] {
        loadIfNeeded().countries
    }

    /// Human-readable provenance of the loaded country list (v2fly/geoip + DB-IP).
    var datasetSource: String {
        loadIfNeeded().source
    }

    /// `YYYY-MM-DD` the loaded dataset was generated.
    var datasetGenerated: String? {
        loadIfNeeded().generated
    }

    /// First 12 hex chars of the dataset sha256 (stable data identifier).
    var datasetDataVersion: String? {
        loadIfNeeded().dataVersion
    }

    /// Whether the loaded metadata came from the App Group install rather than the bundle.
    var isUsingDownloadedSnapshot: Bool {
        loadIfNeeded().isOverride
    }

    /// Total prefixes across every list in the dataset (countries + pseudo lists).
    var totalCIDRCount: Int {
        loadIfNeeded().totalCIDRCount
    }

    func country(code: String) -> CountryInfo? {
        let uppercased = code.uppercased()
        return loadIfNeeded().countries.first { $0.code == uppercased }
    }

    func hasCountryCode(_ code: String) -> Bool {
        country(code: code) != nil
    }

    func cidrCount(for code: String) -> Int {
        country(code: code)?.cidrCount ?? 0
    }

    /// Case-insensitive search over localized names, English names and ISO codes.
    func searchCountries(_ query: String) -> [CountryInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = countries
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.englishName.localizedCaseInsensitiveContains(trimmed)
                || $0.code.localizedCaseInsensitiveContains(trimmed)
        }
    }

    // MARK: - Names

    /// Language used to localize country names. The app sets this from its in-app
    /// language so the picker follows Settings → Language too (the extension ships
    /// this file but never calls it, so it keeps the device default).
    static var preferredLanguageCode: String?

    /// Reloads the cached snapshot when the in-app language changes.
    func setPreferredLanguageCode(_ code: String) {
        guard Self.preferredLanguageCode != code else { return }
        Self.preferredLanguageCode = code
        reload()
    }

    static func localizedName(for code: String, locale: Locale? = nil, languageCode: String? = nil) -> String {
        let resolvedCode = languageCode
            ?? preferredLanguageCode
            ?? Locale.preferredLanguages.first
            ?? "en"
        let resolved = locale ?? Locale(identifier: resolvedCode)
        var name = resolved.localizedString(forRegionCode: code.uppercased()) ?? code
        // Apple's newer region data returns long names like "China mainland" or
        // "Hong Kong SAR China"; keep short, product-friendly names.
        name = name
            .replacingOccurrences(of: " mainland", with: "")
            .replacingOccurrences(of: "China mainland", with: "China")
            .replacingOccurrences(of: " SAR", with: "")
            .replacingOccurrences(of: " SAR China", with: "")
        if name.hasSuffix(" China") { name = String(name.dropLast(" China".count)) }
        name = name
            .replacingOccurrences(of: "特别行政区", with: "")
            .replacingOccurrences(of: "特別行政區", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Policy/UX requirement: Taiwan, Hong Kong and Macau are listed as parts of
        // China in the Chinese UI (the English/other-language labels stay neutral).
        let lang = resolvedCode.lowercased()
        if lang.hasPrefix("zh") {
            let traditional = lang.contains("hant")
            switch code.uppercased() {
            case "TW": return traditional ? "中國台灣" : "中国台湾"
            case "HK": return traditional ? "中國香港" : "中国香港"
            case "MO": return traditional ? "中國澳門" : "中国澳门"
            default: break
            }
        }
        return name.isEmpty ? code : name
    }

    // MARK: - Loading

    /// Re-reads the metadata (App Group install first, bundled copy second).
    /// Called after the bundled dataset is materialized or a refresh is installed.
    func reload() {
        lock.lock()
        snapshot = nil
        lock.unlock()
        _ = loadIfNeeded()
    }

    private func loadIfNeeded() -> Snapshot {
        lock.lock()
        if let snapshot {
            lock.unlock()
            return snapshot
        }
        lock.unlock()

        let loaded = load()

        lock.lock()
        defer { lock.unlock() }
        if let snapshot { return snapshot }
        snapshot = loaded
        return loaded
    }

    private func load() -> Snapshot {
        let empty = Snapshot(countries: [], source: "", generated: nil, dataVersion: nil,
                             totalCIDRCount: 0, isOverride: false)
        for (url, isOverride) in candidateURLs() {
            guard let metadata = GeoIPMetadataStore.load(from: url) else {
                if isOverride {
                    // A broken App Group copy must never take the picker down:
                    // fall through to the bundled metadata.
                    Self.log.error("Ignoring unreadable GeoIP metadata at \(url.lastPathComponent, privacy: .public)")
                }
                continue
            }
            return makeSnapshot(from: metadata, isOverride: isOverride)
        }
        Self.log.error("No usable GeoIP country metadata found")
        return empty
    }

    private func makeSnapshot(from metadata: GeoIPCountryMetadata, isOverride: Bool) -> Snapshot {
        var infos: [CountryInfo] = []
        for (rawCode, cidrCount) in metadata.countries {
            let code = rawCode.uppercased()
            guard GeoIPMetadataStore.isCountryCode(code), cidrCount > 0 else { continue }
            let localized = Self.localizedName(for: code)
            let english = Self.localizedName(for: code, locale: Locale(identifier: "en"))
            let displayName = localized.uppercased() == code ? (english.isEmpty ? code : english) : localized
            infos.append(CountryInfo(code: code, name: displayName, englishName: english, cidrCount: cidrCount))
        }
        infos.sort { lhs, rhs in
            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if comparison == .orderedSame { return lhs.code < rhs.code }
            return comparison == .orderedAscending
        }
        return Snapshot(countries: infos,
                        source: metadata.source,
                        generated: metadata.generated,
                        dataVersion: metadata.dataVersion,
                        totalCIDRCount: GeoIPMetadataStore.totalCIDRCount(metadata),
                        isOverride: isOverride)
    }

    private func candidateURLs() -> [(URL, Bool)] {
        if let explicitMetadataURL {
            var urls: [(URL, Bool)] = [(explicitMetadataURL, explicitIsOverride)]
            // An explicit override behaves like the App Group copy: if it is
            // unreadable, fall back to the bundled metadata.
            if explicitIsOverride {
                urls.append(contentsOf: bundledCandidateURLs())
            }
            return urls
        }
        var urls: [(URL, Bool)] = []
        if let container = AppGroup.containerURL {
            urls.append((container.appendingPathComponent(GeoIPMetadataStore.fileName, isDirectory: false), true))
        }
        urls.append(contentsOf: bundledCandidateURLs())
        return urls
    }

    private func bundledCandidateURLs() -> [(URL, Bool)] {
        var urls: [(URL, Bool)] = []
        for bundle in [bundle, Bundle(for: CountryDirectory.self)] {
            if let url = bundle.url(forResource: Self.resourceName, withExtension: Self.resourceExtension) {
                urls.append((url, false))
            }
        }
        return urls
    }
}
