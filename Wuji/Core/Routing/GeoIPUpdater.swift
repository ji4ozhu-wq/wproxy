import CryptoKit
import Foundation
import os

/// Provenance/status metadata for the installed GeoIP dataset (`geoip_meta.json`).
///
/// `lastUpdatedAt` is the timestamp the 7-day refresh policy uses (nil while the
/// app still runs on the bundled snapshot). `lastAttemptAt` + `lastError` persist
/// the most recent failure so Settings can explain why the data is stale. All
/// fields are optional so a meta file written by an older build still decodes.
struct GeoIPMeta: Codable, Equatable, Sendable {
    var lastUpdatedAt: Date?
    var lastAttemptAt: Date?
    var dataVersion: String?
    var source: String?
    var etag: String?
    var generated: String?
    var countryCount: Int?
    var cidrCount: Int?
    var lastError: String?
}

/// Read model handed to the Settings screen (docs/app-spec.md §5.11).
struct GeoIPUpdateStatus: Equatable, Sendable {
    var lastUpdatedAt: Date?
    var lastAttemptAt: Date?
    var dataVersion: String?
    var source: String?
    var lastError: String?
    var isUpdating: Bool = false
    var countryCount: Int?
    var cidrCount: Int?
    var generated: String?
    var isUsingDownloadedData: Bool = false

    /// Whether the 7-day refresh is already due (Settings can hint "Update available").
    var isRefreshDue: Bool = false
}

enum GeoIPUpdaterError: Error, Equatable, LocalizedError {
    case appGroupUnavailable
    case invalidResponse(URL)
    case httpStatus(Int, URL)
    case invalidChecksumFile
    case checksumMismatch(expected: String, actual: String)
    case emptyDataset
    case allMirrorsFailed([String])

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "the App Group container is unavailable"
        case .invalidResponse(let url):
            return "unexpected response from \(url.host ?? "the data server")"
        case .httpStatus(let status, let url):
            return "HTTP \(status) from \(url.host ?? "the data server")"
        case .invalidChecksumFile:
            return "the published sha256sum file is malformed"
        case .checksumMismatch(let expected, let actual):
            return "sha256 mismatch (expected \(expected.prefix(12))…, got \(actual.prefix(12))…)"
        case .emptyDataset:
            return "the downloaded GeoIP database contains no lists"
        case .allMirrorsFailed(let reasons):
            return "GeoIP download failed: " + reasons.joined(separator: "; ")
        }
    }
}

/// One HTTP payload fetched by the updater.
struct GeoIPDownload: Sendable {
    var data: Data
    var etag: String?
}

protocol GeoIPDownloading: AnyObject {
    func fetch(_ url: URL) async throws -> GeoIPDownload
}

/// Real HTTPS downloader: short request timeout, no local cache so a 7-day refresh
/// always revalidates against the mirror.
final class URLSessionGeoIPDownloader: GeoIPDownloading {
    static let userAgent = "Wuji/1.0 (iOS; GeoIP data updater)"

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        session = URLSession(configuration: configuration)
    }

    func fetch(_ url: URL) async throws -> GeoIPDownload {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeoIPUpdaterError.invalidResponse(url)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GeoIPUpdaterError.httpStatus(http.statusCode, url)
        }
        return GeoIPDownload(data: data, etag: http.value(forHTTPHeaderField: "ETag"))
    }
}

/// Installs a fresh `geoip.dat` into the App Group container (docs/deps.md).
///
/// Data source: v2fly/geoip `release` branch `geoip.dat` (v2ray GeoIPList protobuf,
/// geolocation from DB-IP Lite; see docs/licenses-geoip.md). Mirrors are tried in
/// order (jsDelivr first, then raw.githubusercontent) and the payload is verified
/// against the mirror's `geoip.dat.sha256sum` — and scanned as a valid GeoIPList —
/// before it replaces the installed dataset, so a corrupt download can never
/// replace a working one.
///
/// Refresh policy (product decision):
///  * the caller invokes `updateIfNeeded(vpnConnected:)` on launch/foreground and
///    whenever the tunnel state changes;
///  * an automatic attempt only happens while the VPN is connected — the device
///    reaches GitHub through the proxy, and the same connection is what makes the
///    downloaded list correct for the user's network;
///  * a fresh dataset is downloaded when the installed one is older than 7 days;
///  * a failed attempt is retried at most once per hour (fixed interval, no
///    exponential backoff) and stops while disconnected; the previous dataset is
///    kept in the meantime.
///
/// On success the dataset + metadata sidecar are written atomically to the App
/// Group container, `CountryDirectory` is reloaded and a notification is posted.
/// `manualUpdate()` is the Settings "Update Now" action and bypasses the
/// connectivity/interval gates because the user explicitly asked for it.
final class GeoIPUpdater {
    static let shared = GeoIPUpdater()

    /// Automatic refresh interval requested by the product decision: 7 days.
    static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60
    /// Fixed retry interval after a failed attempt (1 hour, no exponential backoff).
    static let retryInterval: TimeInterval = 60 * 60

    static let metaFileName = "geoip_meta.json"

    static let didUpdateNotification = Notification.Name("WujiGeoIPDidUpdate")
    static let statusDidChangeNotification = Notification.Name("WujiGeoIPStatusDidChange")

    static let datasetLicense = "CC BY-SA 4.0 (v2fly/geoip compilation); underlying DB-IP Lite data CC BY 4.0"
    static let datasetSourceName = "v2fly/geoip release branch (https://github.com/v2fly/geoip)"

    /// Mirrors in preference order. Both are HTTPS; raw.githubusercontent is the
    /// canonical URL and jsDelivr covers networks where GitHub is throttled.
    struct Mirror: Sendable, Equatable {
        var datasetURL: URL
        var checksumURL: URL
        var host: String { datasetURL.host ?? datasetURL.absoluteString }
    }

    static let mirrors: [Mirror] = [
        Mirror(
            datasetURL: URL(string: "https://cdn.jsdelivr.net/gh/v2fly/geoip@release/geoip.dat")!,
            checksumURL: URL(string: "https://cdn.jsdelivr.net/gh/v2fly/geoip@release/geoip.dat.sha256sum")!
        ),
        Mirror(
            datasetURL: URL(string: "https://raw.githubusercontent.com/v2fly/geoip/release/geoip.dat")!,
            checksumURL: URL(string: "https://raw.githubusercontent.com/v2fly/geoip/release/geoip.dat.sha256sum")!
        )
    ]

    private let containerURL: URL?
    private let downloader: any GeoIPDownloading
    private let now: () -> Date
    private let fileManager: FileManager
    private let bundle: Bundle
    private let assetManager: GeoIPAssetManager
    private let datasetInstalledHandler: () -> Void
    private let lock = NSLock()
    private var meta: GeoIPMeta?
    private var lastError: String?
    private var updating = false
    private let log = Logger(subsystem: "com.juejin.ios.wuji", category: "geoip")

    /// - Parameters:
    ///   - containerURL: App Group container (injected in tests).
    ///   - downloader: HTTP transport (mock in tests; tests must never hit the network).
    ///   - now: injectable clock so the 7-day / 1-hour policies are testable.
    ///   - bundle: app bundle that carries `geoip.dat.gz` + `geoip_countries.json`.
    ///   - assetManager: same-container asset manager used for the first-launch install.
    ///   - datasetInstalledHandler: called after a successful install; the default
    ///     reloads `CountryDirectory` and posts `didUpdateNotification`.
    init(containerURL: URL? = AppGroup.containerURL,
         downloader: any GeoIPDownloading = URLSessionGeoIPDownloader(),
         now: @escaping () -> Date = Date.init,
         fileManager: FileManager = .default,
         bundle: Bundle = .main,
         assetManager: GeoIPAssetManager? = nil,
         datasetInstalledHandler: (() -> Void)? = nil) {
        self.containerURL = containerURL
        self.downloader = downloader
        self.now = now
        self.fileManager = fileManager
        self.bundle = bundle
        self.assetManager = assetManager ?? GeoIPAssetManager(containerURL: containerURL,
                                                              bundle: bundle,
                                                              fileManager: fileManager)
        self.datasetInstalledHandler = datasetInstalledHandler ?? {
            CountryDirectory.shared.reload()
            NotificationCenter.default.post(name: GeoIPUpdater.didUpdateNotification, object: nil)
        }
        let loadedMeta = Self.loadMeta(containerURL: containerURL, fileManager: fileManager)
        self.meta = loadedMeta
        self.lastError = loadedMeta?.lastError
    }

    // MARK: - Status

    /// Snapshot shown by Settings; cheap to read (no I/O).
    var status: GeoIPUpdateStatus {
        lock.lock()
        defer { lock.unlock() }
        let current = meta
        return GeoIPUpdateStatus(
            lastUpdatedAt: current?.lastUpdatedAt,
            lastAttemptAt: current?.lastAttemptAt,
            dataVersion: current?.dataVersion,
            source: current?.source,
            lastError: lastError,
            isUpdating: updating,
            countryCount: current?.countryCount,
            cidrCount: current?.cidrCount,
            generated: current?.generated,
            isUsingDownloadedData: containerURL.map { url in
                fileManager.fileExists(atPath: url.appendingPathComponent(GeoIPAssetManager.datasetFileName).path)
            } ?? false,
            isRefreshDue: Self.isUpdateDue(lastUpdatedAt: current?.lastUpdatedAt, now: now())
        )
    }

    /// Re-reads `geoip_meta.json` (e.g. after the container was cleaned).
    func reloadStatusFromDisk() {
        let loaded = Self.loadMeta(containerURL: containerURL, fileManager: fileManager)
        lock.lock()
        meta = loaded
        lastError = loaded?.lastError
        lock.unlock()
    }

    // MARK: - Triggers

    /// First-launch / post-update preparation: decompresses the bundled
    /// `geoip.dat.gz` into the App Group container and installs its metadata.
    /// The caller invokes this from a background task on launch; it is a no-op once
    /// the dataset exists.
    @discardableResult
    func prepareIfNeeded() async -> Bool {
        let installed = assetManager.prepareDatasetIfNeeded()
        guard installed else { return false }
        if Self.loadMeta(containerURL: containerURL, fileManager: fileManager) == nil,
           let bundled = GeoIPMetadataStore.bundled(bundle) {
            // Baseline status while the app still runs on the bundled snapshot.
            let baseline = GeoIPMeta(
                lastUpdatedAt: nil,
                lastAttemptAt: nil,
                dataVersion: bundled.dataVersion,
                source: bundled.source,
                etag: nil,
                generated: bundled.generated,
                countryCount: bundled.countryCount,
                cidrCount: GeoIPMetadataStore.totalCIDRCount(bundled),
                lastError: nil
            )
            try? writeMeta(baseline)
            withLock {
                meta = baseline
                lastError = nil
            }
        }
        postStatusDidChange()
        return true
    }

    /// Called by AppState on launch/foreground and on tunnel state changes.
    /// Non-blocking: returns immediately after starting a background refresh when one
    /// is due, and never throws (failures are recorded in `status.lastError`).
    ///
    /// - Parameter vpnConnected: automatic refresh only runs inside an established
    ///   tunnel, because that is the network path that can reach the GitHub mirrors.
    func updateIfNeeded(vpnConnected: Bool) async {
        guard shouldAttemptUpdate(vpnConnected: vpnConnected) else { return }
        guard beginUpdate() else { return }
        defer { endUpdate() }
        do {
            try await performUpdate()
        } catch {
            recordFailure(error)
        }
    }

    /// "Update Now" from Settings. Ignores the connectivity/interval gates because
    /// the user explicitly requested the download.
    @discardableResult
    func manualUpdate() async -> Bool {
        guard beginUpdate() else { return false }
        defer { endUpdate() }
        do {
            try await performUpdate()
            return true
        } catch {
            recordFailure(error)
            return false
        }
    }

    // MARK: - Policy

    static func isUpdateDue(lastUpdatedAt: Date?,
                            now: Date,
                            interval: TimeInterval = GeoIPUpdater.refreshInterval) -> Bool {
        guard let lastUpdatedAt else { return true }
        return now.timeIntervalSince(lastUpdatedAt) >= interval
    }

    /// 7-day freshness check + "only while connected" + 1-hour failure backoff.
    private func shouldAttemptUpdate(vpnConnected: Bool) -> Bool {
        guard vpnConnected else { return false }
        lock.lock()
        let current = meta
        lock.unlock()
        let currentDate = now()
        guard Self.isUpdateDue(lastUpdatedAt: current?.lastUpdatedAt, now: currentDate) else { return false }
        if current?.lastError != nil,
           let lastAttempt = current?.lastAttemptAt,
           currentDate.timeIntervalSince(lastAttempt) < Self.retryInterval {
            return false
        }
        return true
    }

    // MARK: - Update pipeline

    private struct VerifiedDataset {
        var data: Data
        var checksum: String
        var etag: String?
        var mirror: Mirror
        var counts: [String: Int]
        var generated: String
    }

    private func performUpdate() async throws {
        guard let containerURL else { throw GeoIPUpdaterError.appGroupUnavailable }

        let verified = try await downloadVerifiedDataset()
        let source = "\(Self.datasetSourceName) via \(verified.mirror.host)"
        let metadata = GeoIPMetadataStore.make(
            source: source,
            license: Self.datasetLicense,
            dataVersion: String(verified.checksum.prefix(12)),
            sha256: verified.checksum,
            generated: verified.generated,
            counts: verified.counts
        )

        try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
        let datasetURL = containerURL.appendingPathComponent(GeoIPAssetManager.datasetFileName, isDirectory: false)
        try verified.data.write(to: datasetURL,
                                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try GeoIPMetadataStore.write(metadata, to: containerURL, fileManager: fileManager)

        let attempt = now()
        let newMeta = GeoIPMeta(
            lastUpdatedAt: attempt,
            lastAttemptAt: attempt,
            dataVersion: metadata.dataVersion,
            source: source,
            etag: verified.etag,
            generated: metadata.generated,
            countryCount: metadata.countryCount,
            cidrCount: GeoIPMetadataStore.totalCIDRCount(metadata),
            lastError: nil
        )
        try writeMeta(newMeta)

        withLock {
            meta = newMeta
            lastError = nil
        }

        log.info("GeoIP dataset updated: \(metadata.countryCount ?? 0) countries, version \(metadata.dataVersion ?? "", privacy: .public)")
        datasetInstalledHandler()
        postStatusDidChange()
    }

    private func downloadVerifiedDataset() async throws -> VerifiedDataset {
        var failures: [String] = []
        for mirror in Self.mirrors {
            do {
                let checksumPayload = try await downloader.fetch(mirror.checksumURL)
                let expected = try Self.parseChecksum(checksumPayload.data)
                let payload = try await downloader.fetch(mirror.datasetURL)
                let actual = Self.sha256Hex(payload.data)
                guard actual == expected else {
                    throw GeoIPUpdaterError.checksumMismatch(expected: expected, actual: actual)
                }
                let counts = try GeoIPProtoParser.countryCounts(in: payload.data)
                guard !counts.isEmpty else { throw GeoIPUpdaterError.emptyDataset }
                return VerifiedDataset(
                    data: payload.data,
                    checksum: actual,
                    etag: payload.etag,
                    mirror: mirror,
                    counts: counts,
                    generated: Self.generatedDateString(at: now())
                )
            } catch {
                failures.append("\(mirror.host): \(Self.describe(error))")
                log.error("GeoIP mirror \(mirror.host, privacy: .public) failed: \(Self.describe(error), privacy: .public)")
            }
        }
        throw GeoIPUpdaterError.allMirrorsFailed(failures)
    }

    // MARK: - Persistence

    private func writeMeta(_ meta: GeoIPMeta) throws {
        guard let containerURL else { throw GeoIPUpdaterError.appGroupUnavailable }
        try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(meta)
        let url = containerURL.appendingPathComponent(Self.metaFileName, isDirectory: false)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func loadMeta(containerURL: URL?, fileManager: FileManager) -> GeoIPMeta? {
        guard let containerURL else { return nil }
        let url = containerURL.appendingPathComponent(GeoIPUpdater.metaFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GeoIPMeta.self, from: data)
    }

    // MARK: - Update slot / status notifications

    /// Synchronous critical-section helper: keeps the `NSLock` calls out of the
    /// `async` function bodies (Swift 6 flags direct lock/unlock in async contexts).
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func beginUpdate() -> Bool {
        lock.lock()
        guard !updating else {
            lock.unlock()
            return false
        }
        updating = true
        lock.unlock()
        postStatusDidChange()
        return true
    }

    private func endUpdate() {
        lock.lock()
        updating = false
        lock.unlock()
        postStatusDidChange()
    }

    private func recordFailure(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let attempt = now()
        var newMeta = meta ?? GeoIPMeta()
        newMeta.lastAttemptAt = attempt
        newMeta.lastError = message
        if containerURL != nil {
            do {
                try writeMeta(newMeta)
            } catch {
                log.error("Could not persist GeoIP failure metadata: \(error.localizedDescription, privacy: .public)")
            }
        }
        lock.lock()
        meta = newMeta
        lastError = message
        lock.unlock()
        log.error("GeoIP update failed: \(message, privacy: .public)")
        postStatusDidChange()
    }

    private func postStatusDidChange() {
        NotificationCenter.default.post(name: Self.statusDidChangeNotification, object: self)
    }

    // MARK: - Helpers

    static func parseChecksum(_ data: Data) throws -> String {
        let text = String(decoding: data, as: UTF8.self)
        guard let token = text.split(whereSeparator: { $0.isWhitespace }).first else {
            throw GeoIPUpdaterError.invalidChecksumFile
        }
        let checksum = String(token).lowercased()
        guard checksum.count == 64, checksum.allSatisfy({ $0.isHexDigit }) else {
            throw GeoIPUpdaterError.invalidChecksumFile
        }
        return checksum
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func generatedDateString(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
