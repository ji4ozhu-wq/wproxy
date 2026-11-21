import Foundation
import os

/// Traffic/expiry metadata advertised by a subscription server through the
/// `Subscription-Userinfo` response header.
struct SubscriptionUserInfo: Equatable, Sendable {
    var upload: Int64?
    var download: Int64?
    var total: Int64?
    var expireAt: Date?
    /// Optional refresh interval advertised by the server (`profile-update-interval`).
    var profileUpdateInterval: TimeInterval?
}

struct SubscriptionFetchResult: Sendable {
    var nodes: [NodeProfile]
    var trafficUpload: Int64?
    var trafficDownload: Int64?
    var trafficTotal: Int64?
    var expireAt: Date?
    var updatedAt: Date
    var userInfo: SubscriptionUserInfo = SubscriptionUserInfo()

    var userInfoSummary: SubscriptionUserInfo {
        SubscriptionUserInfo(upload: trafficUpload, download: trafficDownload, total: trafficTotal,
                             expireAt: expireAt, profileUpdateInterval: userInfo.profileUpdateInterval)
    }
}

/// Serializes subscription fetches per URL so auto-update, pull-to-refresh and a
/// manual "Update" can never run the same subscription twice at the same time (B8).
actor SubscriptionFetchGate {
    static let shared = SubscriptionFetchGate()

    private var inFlight: Set<String> = []

    /// Returns `false` when another fetch for the same key is already running.
    func begin(_ key: String) -> Bool {
        inFlight.insert(key).inserted
    }

    func end(_ key: String) {
        inFlight.remove(key)
    }

    /// Test/teardown helper: forget every in-flight key.
    func reset() {
        inFlight.removeAll()
    }
}

/// Fetches and parses user subscription URLs (spec §5.7, docs/impl-plan.md B6).
/// Owned by the data role.
final class SubscriptionService {
    private let parser: URIParser
    private static let log = Logger(subsystem: "com.juejin.ios.wuji", category: "SubscriptionService")
    private let session: URLSession

    /// User agent required by the spec (`Wuji/1.0`).
    static let userAgent = "Wuji/1.0 (iOS)"
    static let defaultTimeout: TimeInterval = 20
    /// Subscriptions are small text files; refuse anything absurd to protect memory.
    static let maximumBodySize = 8 * 1024 * 1024

    init(session: URLSession = .shared, parser: URIParser = URIParser()) {
        self.session = session
        self.parser = parser
    }

    /// `true` for hosts that can only be reached on this device itself. Plain HTTP is
    /// rejected for every other host: without TLS the subscription credentials and
    /// node list travel in clear text. Loopback stays allowed so the DEBUG/UI-test
    /// harness can serve fixture subscriptions locally.
    static func isLoopbackHost(_ host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed == "localhost"
            || trimmed == "::1"
            || trimmed == "0.0.0.0"
            || trimmed.hasPrefix("127.")
    }

    /// Fetches and parses a subscription URL. Throws `SubscriptionError` for
    /// invalid/insecure URLs, HTTP failures and bodies without usable nodes;
    /// transport errors are re-thrown as `URLError`.
    func fetch(url: String, groupID: String, name: String) async throws -> SubscriptionFetchResult {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty,
              let components = URLComponents(string: trimmedURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              let requestURL = components.url else {
            throw SubscriptionError.invalidURL
        }
        if scheme == "http", !Self.isLoopbackHost(host) {
            throw SubscriptionError.insecureURL
        }

        let gateKey = "\(groupID)|\(requestURL.absoluteString)"
        guard await SubscriptionFetchGate.shared.begin(gateKey) else {
            throw SubscriptionError.refreshInProgress
        }
        defer {
            // The deferred block cannot await; hop to the gate in a detached task.
            Task { await SubscriptionFetchGate.shared.end(gateKey) }
        }

        var request = URLRequest(url: requestURL)
        // Some panels reject requests without a browser-like Accept header.
        request.timeoutInterval = Self.defaultTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        Self.log.info("Fetching subscription \(requestURL.absoluteString, privacy: .private)")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SubscriptionError.httpStatus(http.statusCode)
        }
        guard data.count <= Self.maximumBodySize else { throw SubscriptionError.invalidBody }
        guard let body = String(data: data, encoding: .utf8) else { throw SubscriptionError.invalidBody }

        let links = parser.parseSubscriptionBody(body)
        Self.log.info("Subscription body: \(data.count) bytes, \(links.count) links")
        guard !links.isEmpty else { throw SubscriptionError.emptySubscription }

        let report = parser.parseDetailed(links.joined(separator: "\n"), groupID: groupID)
        guard !report.profiles.isEmpty else { throw SubscriptionError.emptySubscription }

        let userInfo = Self.parseUserInfo((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Subscription-Userinfo"))
        return SubscriptionFetchResult(
            nodes: report.profiles,
            trafficUpload: userInfo.upload,
            trafficDownload: userInfo.download,
            trafficTotal: userInfo.total,
            expireAt: userInfo.expireAt,
            updatedAt: Date(),
            userInfo: userInfo
        )
    }

    /// Convenience wrapper for refreshing an existing subscription.
    func fetch(subscription: Subscription) async throws -> SubscriptionFetchResult {
        try await fetch(url: subscription.url, groupID: subscription.id, name: subscription.name)
    }

    /// Parses a `Subscription-Userinfo` header:
    /// `upload=123; download=456; total=789; expire=1700000000; profile-update-interval=24`
    /// Panels occasionally base64-encode the header value; both forms are accepted.
    static func parseUserInfo(_ header: String?) -> SubscriptionUserInfo {
        guard var value = header?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return SubscriptionUserInfo()
        }
        var info = parseUserInfoPairs(value)
        if info == SubscriptionUserInfo(), let data = URIParserCore.base64Data(value),
           let decoded = String(data: data, encoding: .utf8) {
            value = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            info = parseUserInfoPairs(value)
        }
        return info
    }

    private static func parseUserInfoPairs(_ value: String) -> SubscriptionUserInfo {
        var info = SubscriptionUserInfo()
        for part in value.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else { continue }
            let key = pieces[0].trimmingCharacters(in: .whitespaces).lowercased()
            let raw = pieces[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "upload": info.upload = parseByteCount(raw)
            case "download": info.download = parseByteCount(raw)
            case "total": info.total = parseByteCount(raw)
            case "expire": info.expireAt = parseTimestamp(raw)
            case "profile-update-interval": info.profileUpdateInterval = TimeInterval(raw).map { $0 * 3600 }
            default: break
            }
        }
        return info
    }

    private static func parseByteCount(_ raw: String) -> Int64? {
        guard let value = Int64(raw.trimmingCharacters(in: .whitespaces)) else { return nil }
        return max(0, value)
    }

    /// Accepts seconds or milliseconds since the Unix epoch.
    private static func parseTimestamp(_ raw: String) -> Date? {
        guard let value = TimeInterval(raw.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        let seconds = value > 1_000_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}

enum SubscriptionError: LocalizedError, Equatable {
    case invalidURL
    case insecureURL
    case refreshInProgress
    case httpStatus(Int)
    case invalidBody
    case emptySubscription

    var errorDescription: String? {
        switch self {
        case .invalidURL: return NSLocalizedString("error.subscription.url", comment: "")
        case .insecureURL: return NSLocalizedString("error.subscription.insecure", comment: "")
        case .refreshInProgress: return NSLocalizedString("error.subscription.inFlight", comment: "")
        case .httpStatus(let code): return String(format: NSLocalizedString("error.subscription.http", comment: ""), code)
        case .invalidBody: return NSLocalizedString("error.subscription.body", comment: "")
        case .emptySubscription: return NSLocalizedString("error.subscription.empty", comment: "")
        }
    }
}
