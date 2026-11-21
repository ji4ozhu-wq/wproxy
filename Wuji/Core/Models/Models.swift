import Foundation

// MARK: - Enums

enum ProxyProtocol: String, Codable, CaseIterable, Sendable {
    case vmess, vless, trojan, shadowsocks, socks

    var displayName: String {
        switch self {
        case .vmess: return "VMess"
        case .vless: return "VLESS"
        case .trojan: return "Trojan"
        case .shadowsocks: return "Shadowsocks"
        case .socks: return "SOCKS5"
        }
    }

    var shortBadge: String {
        switch self {
        case .socks: return "SOCKS"
        case .vmess: return "VMess"
        case .vless: return "VLESS"
        case .trojan: return "Trojan"
        case .shadowsocks: return "SS"
        }
    }
}

enum Transport: String, Codable, CaseIterable, Sendable {
    case tcp, ws, grpc, h2, http

    var displayName: String {
        switch self {
        case .tcp: return "TCP"
        case .ws: return "WebSocket"
        case .grpc: return "gRPC"
        case .h2: return "HTTP/2"
        case .http: return "HTTP"
        }
    }
}

enum SecurityLayer: String, Codable, CaseIterable, Sendable {
    case none, tls, reality

    var displayName: String {
        switch self {
        case .none: return "None"
        case .tls: return "TLS"
        case .reality: return "REALITY"
        }
    }
}

enum GroupKind: String, Codable, Sendable {
    case manual, subscription
}

enum RoutingMode: String, Codable, CaseIterable, Sendable {
    case rule, global
}

enum OnDemandMode: String, Codable, CaseIterable, Sendable {
    case off, always, wifi, cellular
}

// MARK: - Entities

struct NodeGroup: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var kind: GroupKind
    var subscriptionID: String?
    var sortOrder: Int
}

struct NodeProfile: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var groupID: String
    var name: String
    var proto: ProxyProtocol
    var server: String
    var port: Int
    var uuid: String = ""
    var password: String = ""
    /// SOCKS5 username; empty means no authentication (password may still be empty).
    var socksUsername: String = ""
    var ssMethod: String = ""
    var vmessSecurity: String = "auto"
    var alterID: Int = 0
    var network: Transport = .tcp
    var security: SecurityLayer = .none
    var sni: String = ""
    var wsPath: String = ""
    var wsHost: String = ""
    var grpcService: String = ""
    var fingerprint: String = ""
    var allowInsecure: Bool = false
    var realityPublicKey: String = ""
    var realityShortID: String = ""
    var flow: String = ""
    var rawURI: String = ""
    var latencyMs: Int?
    var latencyAt: Date?
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var displayName: String { name.isEmpty ? "\(server):\(port)" : name }
    var endpoint: String { "\(server):\(port)" }
}

struct Subscription: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var url: String
    var name: String
    var autoUpdateInterval: TimeInterval? // nil / 0 = off
    var lastUpdatedAt: Date?
    var trafficUpload: Int64?
    var trafficDownload: Int64?
    var trafficTotal: Int64?
    var expireAt: Date?
    var lastError: String?
    var createdAt: Date

    var trafficUsed: Int64? {
        guard let up = trafficUpload, let down = trafficDownload else { return nil }
        return up + down
    }
}

/// How DNS queries are answered while the tunnel is active (spec §5.10).
enum DNSMode: String, Codable, CaseIterable, Sendable {
    /// DNS-over-HTTPS through the proxy. Hides queries from the local network but
    /// resolves names from the proxy's point of view (CDN IPs may be far away).
    case proxyDoH
    /// Local direct DNS (8.8.8.8 / 1.1.1.1). Accurate region routing, but the
    /// local network/resolver can see the queries.
    case local

    var displayNameKey: String {
        switch self {
        case .proxyDoH: return "routing.dns.doh"
        case .local: return "routing.dns.local"
        }
    }
}

/// In-app language selection. `.system` follows the device language, the other
/// cases force one of the bundled localizations without restarting the app.
enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case japanese = "ja"
    case korean = "ko"
    case russian = "ru"
    case thai = "th"
    case vietnamese = "vi"

    /// Locale used for dates/numbers; nil means "follow the system".
    var localeIdentifier: String? {
        self == .system ? nil : rawValue
    }

    /// Endonym shown in the language picker (native script, independent of the
    /// current UI language). `.system` has no endonym; callers show a localized
    /// "Follow System" row instead.
    var nativeName: String {
        switch self {
        case .system: return ""
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .russian: return "Русский"
        case .thai: return "ไทย"
        case .vietnamese: return "Tiếng Việt"
        }
    }

    /// English name used as a secondary label in the picker (helps people who
    /// cannot read the endonym yet).
    var englishName: String {
        switch self {
        case .system: return ""
        case .english: return "English"
        case .simplifiedChinese: return "Simplified Chinese"
        case .traditionalChinese: return "Traditional Chinese"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .russian: return "Russian"
        case .thai: return "Thai"
        case .vietnamese: return "Vietnamese"
        }
    }

    /// Map a resolved language code (e.g. the device language when following the
    /// system) back to a case, so the menu can show the effective language.
    static func matching(code: String) -> AppLanguage? {
        let normalized = code.lowercased()
        if normalized.hasPrefix("zh") {
            return normalized.contains("hant") || normalized.contains("tw") || normalized.contains("hk")
                ? .traditionalChinese : .simplifiedChinese
        }
        return allCases.first { $0 != .system && $0.rawValue == normalized }
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var routingMode: RoutingMode = .rule
    var dnsMode: DNSMode = .proxyDoH
    var appLanguage: AppLanguage = .system
    var bypassLAN: Bool = true
    var bypassCountryCodes: [String] = []
    var onDemandMode: OnDemandMode = .off
    var latencyTestURL: String = "https://www.gstatic.com/generate_204"
    var latencyTimeout: TimeInterval = 5
    var subscriptionAutoUpdateEnabled: Bool = true
    var activeProfileID: String?
    var onboardingDone: Bool = false
    var networkPermissionPassed: Bool = false
    var consentAccepted: Bool = false
    var firstConnectExplained: Bool = false
    var sortField: String = "latency"
    var sortAscending: Bool = true

    static let `default` = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case routingMode, dnsMode, appLanguage, bypassLAN, bypassCountryCodes, onDemandMode
        case latencyTestURL, latencyTimeout, subscriptionAutoUpdateEnabled
        case activeProfileID, onboardingDone, networkPermissionPassed, consentAccepted, firstConnectExplained
        case sortField, sortAscending
    }

    /// Hand-written decoder so new settings never reset the user's existing
    /// configuration when an older `settings.json` is loaded.
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        routingMode = try c.decodeIfPresent(RoutingMode.self, forKey: .routingMode) ?? defaults.routingMode
        dnsMode = try c.decodeIfPresent(DNSMode.self, forKey: .dnsMode) ?? defaults.dnsMode
        appLanguage = try c.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? defaults.appLanguage
        bypassLAN = try c.decodeIfPresent(Bool.self, forKey: .bypassLAN) ?? defaults.bypassLAN
        bypassCountryCodes = try c.decodeIfPresent([String].self, forKey: .bypassCountryCodes) ?? defaults.bypassCountryCodes
        onDemandMode = try c.decodeIfPresent(OnDemandMode.self, forKey: .onDemandMode) ?? defaults.onDemandMode
        latencyTestURL = try c.decodeIfPresent(String.self, forKey: .latencyTestURL) ?? defaults.latencyTestURL
        latencyTimeout = try c.decodeIfPresent(TimeInterval.self, forKey: .latencyTimeout) ?? defaults.latencyTimeout
        subscriptionAutoUpdateEnabled = try c.decodeIfPresent(Bool.self, forKey: .subscriptionAutoUpdateEnabled) ?? defaults.subscriptionAutoUpdateEnabled
        activeProfileID = try c.decodeIfPresent(String.self, forKey: .activeProfileID)
        onboardingDone = try c.decodeIfPresent(Bool.self, forKey: .onboardingDone) ?? defaults.onboardingDone
        networkPermissionPassed = try c.decodeIfPresent(Bool.self, forKey: .networkPermissionPassed) ?? defaults.networkPermissionPassed
        consentAccepted = try c.decodeIfPresent(Bool.self, forKey: .consentAccepted) ?? defaults.consentAccepted
        firstConnectExplained = try c.decodeIfPresent(Bool.self, forKey: .firstConnectExplained) ?? defaults.firstConnectExplained
        sortField = try c.decodeIfPresent(String.self, forKey: .sortField) ?? defaults.sortField
        sortAscending = try c.decodeIfPresent(Bool.self, forKey: .sortAscending) ?? defaults.sortAscending
    }
}

// MARK: - Tunnel

enum TunnelState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case error(String)

    var isBusy: Bool {
        switch self {
        case .connecting, .disconnecting: return true
        default: return false
        }
    }
}

struct TunnelSessionStats: Codable, Equatable, Sendable {
    var uploadBytes: Int64 = 0
    var downloadBytes: Int64 = 0
    var connectedAt: Date?
    var uplinkRate: Double = 0
    var downlinkRate: Double = 0
}
