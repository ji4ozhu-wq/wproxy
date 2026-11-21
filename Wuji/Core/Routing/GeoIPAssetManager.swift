import CryptoKit
import Foundation
import os

/// The rule assets handed to `XrayConfigBuilder`/the tunnel extension for one connect.
///
/// `ruleTargets` are ready-to-use Xray routing `ip` entries: `ext:<file>:<code>`.
/// Xray resolves them relative to `xray.location.asset`, which the extension sets to
/// `directory` (the App Group container), and it only loads the lists referenced by
/// these targets — so only the selected countries are parsed by Xray at runtime.
/// `fileName` is deterministic for the same country set + dataset version, which
/// matters because Xray caches matchers by `file:code`.
struct GeoIPAsset: Equatable, Sendable {
    /// Directory that must be exposed as `xray.location.asset`.
    let directory: URL
    /// File written inside `directory`, e.g. `wuji-geoip-5f3a1c2b9d4e.dat`.
    let fileName: String
    /// Xray rule targets, e.g. `["ext:wuji-geoip-5f3a1c2b9d4e.dat:cn", "ext:...:private"]`.
    let ruleTargets: [String]
    /// Uppercased list codes included in the asset (`CN`, `PRIVATE`, …).
    let entryCodes: [String]
    /// Dataset version the asset was extracted from (`sha256` prefix).
    let dataVersion: String

    var fileURL: URL { directory.appendingPathComponent(fileName, isDirectory: false) }
}

/// Builds the small per-connection `geoip.dat` asset from the installed dataset.
///
/// Why extraction instead of expanding CIDRs into the Xray config: the full
/// DB-IP/v2fly dataset has ~1.4 M prefixes (≈26 MB as JSON, and the tunnel
/// extension must stay under ~50 MB). Xray can read `geoip.dat` itself through
/// `ext:<file>:<cc>` route targets, so Wuji copies the raw protobuf entries of the
/// selected countries into a tiny asset file (CN ≈ 0.23 MB, HK ≈ 0.26 MB,
/// US ≈ 3.97 MB) and lets Xray match at runtime.
///
/// Layout in the App Group container (`AppGroup.containerURL`):
///
///     geoip.dat                    installed dataset (bundled snapshot or download)
///     geoip_countries.json         list metadata (written by the updater / prepare)
///     geoip_meta.json              update status (written by `GeoIPUpdater`)
///     wuji-geoip-<hash>.dat        per-connection asset (kept: newest 3)
final class GeoIPAssetManager {
    static let shared = GeoIPAssetManager()

    /// Installed dataset file in the App Group container.
    static let datasetFileName = "geoip.dat"
    /// Bundled compressed snapshot (`geoip.dat.gz` in `Wuji/Resources`).
    static let bundleResourceName = "geoip"
    static let bundleResourceExtension = "dat.gz"
    /// Domain list used by the split DNS resolver (`geosite:cn`).
    static let geoSiteFileName = "geosite.dat"
    static let geoSiteBundleResourceName = "geosite"

    static let assetPrefix = "wuji-geoip-"
    static let assetExtension = "dat"
    /// Keep the current asset plus a few recent ones (avatars of previous selections).
    static let retainedAssetCount = 3
    static let privateEntryCode = "PRIVATE"
    static let privateRuleCode = "private"

    private static let log = Logger(subsystem: "com.juejin.ios.wuji", category: "geoip-assets")

    private let containerURL: URL?
    private let bundle: Bundle
    private let fileManager: FileManager
    private let lock = NSLock()

    init(containerURL: URL? = AppGroup.containerURL,
         bundle: Bundle = .main,
         fileManager: FileManager = .default) {
        self.containerURL = containerURL
        self.bundle = bundle
        self.fileManager = fileManager
    }

    /// URL of the installed `geoip.dat` in the App Group container.
    var datasetURL: URL? {
        containerURL?.appendingPathComponent(Self.datasetFileName, isDirectory: false)
    }

    /// Whether a dataset is installed and the metadata sidecar is available.
    var isDatasetReady: Bool {
        guard let containerURL, let datasetURL else { return false }
        return fileManager.fileExists(atPath: datasetURL.path)
            && fileManager.fileExists(atPath: containerURL.appendingPathComponent(GeoIPMetadataStore.fileName).path)
    }

    static func assetFileName(codes: [String], dataVersion: String) -> String {
        // Sorting makes the file name independent of the selection order; the
        // dataset version keeps different snapshots from sharing a cached matcher.
        let normalizedCodes = codes.sorted().joined(separator: ",")
        let seed = "wuji-geoip-asset-v1|\(dataVersion)|\(normalizedCodes)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        let hash = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        return "\(assetPrefix)\(hash).\(assetExtension)"
    }

    // MARK: - First-launch installation

    /// Decompresses the bundled `geoip.dat.gz` into the App Group container and
    /// writes the matching metadata sidecar. Safe to call repeatedly and from a
    /// background task; returns whether a usable dataset + metadata exist afterwards.
    ///
    /// The App Group copy is required because the Network Extension runs in a
    /// different process and can only read files from the shared container.
    @discardableResult
    func prepareDatasetIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return prepareDatasetLocked()
    }

    // MARK: - Asset extraction

    /// Extracts the selected lists from the installed dataset into
    /// `wuji-geoip-<hash>.dat` and returns the Xray rule targets for it.
    ///
    /// - Parameters:
    ///   - codes: ISO 3166-1 alpha-2 codes selected in Routing settings.
    ///   - includePrivate: add the `PRIVATE` entry when LAN bypass is enabled.
    ///   - dataVersion: installed dataset version (sha256 prefix); part of the file
    ///     name so Xray's per-file matcher cache cannot serve stale data.
    /// - Returns: `nil` when nothing was selected or the dataset is unavailable/corrupt.
    func makeAsset(codes: [String], includePrivate: Bool, dataVersion: String) -> GeoIPAsset? {
        lock.lock()
        defer { lock.unlock() }

        guard prepareDatasetLocked(), let containerURL else { return nil }
        let datasetURL = containerURL.appendingPathComponent(Self.datasetFileName, isDirectory: false)
        guard let data = try? Data(contentsOf: datasetURL, options: .mappedIfSafe),
              let entries = try? GeoIPProtoParser.entries(in: data) else {
            Self.log.error("Cannot read the installed GeoIP dataset; skipping asset generation")
            return nil
        }

        var byCode: [String: GeoIPListEntry] = [:]
        for entry in entries where byCode[entry.code] == nil {
            byCode[entry.code] = entry
        }

        var selected: [GeoIPListEntry] = []
        var ruleCodes: [String] = []
        var seen: Set<String> = []
        for rawCode in codes {
            let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !code.isEmpty, seen.insert(code).inserted, let entry = byCode[code] else { continue }
            selected.append(entry)
            ruleCodes.append(code.lowercased())
        }
        if includePrivate,
           !selected.contains(where: { $0.code == Self.privateEntryCode }),
           let entry = byCode[Self.privateEntryCode] {
            selected.append(entry)
            ruleCodes.append(Self.privateRuleCode)
        }
        guard !selected.isEmpty else { return nil }

        let fileName = Self.assetFileName(codes: ruleCodes, dataVersion: dataVersion)
        let fileURL = containerURL.appendingPathComponent(fileName, isDirectory: false)
        let ruleTargets = ruleCodes.map { "ext:\(fileName):\($0)" }

        if fileManager.fileExists(atPath: fileURL.path) {
            cleanupAssetsLocked(keeping: fileName)
            return GeoIPAsset(directory: containerURL,
                              fileName: fileName,
                              ruleTargets: ruleTargets,
                              entryCodes: selected.map(\.code),
                              dataVersion: dataVersion)
        }

        guard let assembled = try? GeoIPProtoParser.assembleList(from: data, entries: selected) else {
            Self.log.error("Cannot assemble the GeoIP asset for codes \(ruleCodes.joined(separator: ","), privacy: .public)")
            return nil
        }
        do {
            try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
            try assembled.write(to: fileURL,
                                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.log.error("Cannot write GeoIP asset \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        Self.log.info("GeoIP asset \(fileName, privacy: .public) built with \(ruleCodes.count) lists (\(assembled.count) bytes)")
        cleanupAssetsLocked(keeping: fileName)
        return GeoIPAsset(directory: containerURL,
                          fileName: fileName,
                          ruleTargets: ruleTargets,
                          entryCodes: selected.map(\.code),
                          dataVersion: dataVersion)
    }

    // MARK: - Installation internals

    /// Caller must hold `lock`.
    private func prepareDatasetLocked() -> Bool {
        guard let containerURL else { return false }
        installGeoSiteIfNeededLocked(containerURL: containerURL)
        let datasetURL = containerURL.appendingPathComponent(Self.datasetFileName, isDirectory: false)
        let metadataURL = containerURL.appendingPathComponent(GeoIPMetadataStore.fileName, isDirectory: false)
        let bundled = GeoIPMetadataStore.bundled(bundle)

        if fileManager.fileExists(atPath: datasetURL.path) {
            guard !fileManager.fileExists(atPath: metadataURL.path) else { return true }
            // Dataset present but the sidecar was deleted: rebuild it from a scan so
            // the picker keeps showing real counts.
            guard let data = try? Data(contentsOf: datasetURL, options: .mappedIfSafe),
                  let counts = try? GeoIPProtoParser.countryCounts(in: data) else { return false }
            let digest = Self.sha256Hex(data)
            let metadata = GeoIPMetadataStore.make(
                source: bundled?.source ?? GeoIPUpdater.datasetSourceName,
                license: bundled?.license ?? GeoIPUpdater.datasetLicense,
                dataVersion: String(digest.prefix(12)),
                sha256: digest,
                generated: bundled?.generated,
                counts: counts
            )
            do {
                try GeoIPMetadataStore.write(metadata, to: containerURL, fileManager: fileManager)
            } catch {
                return false
            }
            return true
        }

        guard let gzURL = bundle.url(forResource: Self.bundleResourceName,
                                     withExtension: Self.bundleResourceExtension) else {
            Self.log.error("Bundled geoip.dat.gz is missing from the app bundle")
            return false
        }
        do {
            let compressed = try Data(contentsOf: gzURL, options: .mappedIfSafe)
            let dataset = try GeoIPCodec.decompressedIfNeeded(compressed)
            let digest = Self.sha256Hex(dataset)
            if let expected = bundled?.sha256, expected != digest {
                Self.log.error("Bundled geoip.dat.gz failed its integrity check")
                return false
            }
            try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
            try dataset.write(to: datasetURL,
                              options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            if let bundled {
                let counts = try GeoIPProtoParser.countryCounts(in: dataset)
                let metadata = GeoIPMetadataStore.make(
                    source: bundled.source,
                    license: bundled.license,
                    dataVersion: String(digest.prefix(12)),
                    sha256: digest,
                    generated: bundled.generated,
                    counts: counts
                )
                try GeoIPMetadataStore.write(metadata, to: containerURL, fileManager: fileManager)
            }
            CountryDirectory.shared.reload()
            Self.log.info("Installed the bundled GeoIP dataset into the App Group container")
            return true
        } catch {
            Self.log.error("Cannot install the bundled GeoIP dataset: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Decompresses the bundled `geosite.dat.gz` into the App Group container so
    /// Xray's split DNS can resolve Chinese domains with domestic resolvers while
    /// everything else keeps using the proxied DoH servers.
    private func installGeoSiteIfNeededLocked(containerURL: URL) {
        let target = containerURL.appendingPathComponent(Self.geoSiteFileName, isDirectory: false)
        guard !fileManager.fileExists(atPath: target.path) else { return }
        guard let gzURL = bundle.url(forResource: Self.geoSiteBundleResourceName,
                                     withExtension: "dat.gz") else {
            Self.log.error("Bundled geosite.dat.gz is missing from the app bundle")
            return
        }
        do {
            let compressed = try Data(contentsOf: gzURL, options: .mappedIfSafe)
            let dataset = try GeoIPCodec.decompressedIfNeeded(compressed)
            try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
            try dataset.write(to: target,
                              options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            Self.log.info("Installed the bundled geosite domain list into the App Group container")
        } catch {
            Self.log.error("Cannot install the bundled geosite dataset: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Cleanup

    /// Keeps the current asset plus the newest few (Xray may still hold matchers for
    /// a previous file until the next config load; pruning only old ones is safe).
    private func cleanupAssetsLocked(keeping fileName: String) {
        guard let containerURL else { return }
        let urls = (try? fileManager.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let assets = urls.filter {
            $0.lastPathComponent.hasPrefix(Self.assetPrefix) && $0.pathExtension == Self.assetExtension
        }
        guard assets.count > Self.retainedAssetCount else { return }
        let ordered = assets.sorted { modificationDate($0) > modificationDate($1) }
        var keep = Set(ordered.prefix(Self.retainedAssetCount).map(\.lastPathComponent))
        keep.insert(fileName)
        for url in assets where !keep.contains(url.lastPathComponent) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    // MARK: - Hashing

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
