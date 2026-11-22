import Foundation

/// Shared App Group container used to hand the tunnel configuration to the
/// Network Extension and to read status back.
enum AppGroup {
    /// Shared container identifier.
    ///
    /// iOS uses the registered `group.` identifier. macOS app groups use the
    /// `<TeamID>.<group name>` form (Apple: "Configure app groups"), which macOS
    /// validates against the code signing team and which does not need to be
    /// registered on the developer website. The identifier is injected into both
    /// macOS Info.plists as `WujiAppGroupIdentifier` so it stays in sync with the
    /// signing team (`$(TeamIdentifierPrefix)` expands to e.g. `R6748V42K5.`).
    static var identifier: String {
        #if os(iOS)
        return "group.com.youqu.wuji.appgroup"
        #else
        if let value = Bundle.main.object(forInfoDictionaryKey: "WujiAppGroupIdentifier") as? String,
           !value.isEmpty,
           !value.contains("$("),
           !value.hasPrefix("group.") {
            return value
        }
        // Fallback for unsigned builds, where `$(TeamIdentifierPrefix)` expands to
        // nothing and the plist value would be the registered iOS group name. The
        // macOS app group must carry the signing team's prefix.
        return "R6748V42K5.group.com.youqu.wuji.appgroup"
        #endif
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var activeTunnelURL: URL? {
        containerURL?.appendingPathComponent("active_tunnel.json", isDirectory: false)
    }

    static var tunnelStatusURL: URL? {
        containerURL?.appendingPathComponent("tunnel_status.json", isDirectory: false)
    }

    static var trafficURL: URL? {
        containerURL?.appendingPathComponent("tunnel_traffic.json", isDirectory: false)
    }

    /// Copy of the sqlite database path readable by the extension (extension opens read-only).
    static var databaseURL: URL? {
        containerURL?.appendingPathComponent("wuji.sqlite3", isDirectory: false)
    }

    static let tunnelBundleIdentifier = "com.juejin.ios.wuji.tunnel-ext"
    static let providerConfigurationKey = "wujiTunnelConfig"
}

/// Configuration handed from the app to the extension through `active_tunnel.json`.
///
/// It travels: app writes the file → `startVPNTunnel()` → extension reads the file at
/// the beginning of `startTunnel`. The file holds the full Xray JSON and the few
/// values the extension needs to build `NEPacketTunnelNetworkSettings`.
struct TunnelLaunchConfig: Codable, Sendable {
    var xrayJSON: String
    var onDemandEnabled: Bool
    var onDemandMode: OnDemandMode
    /// B1 (audit): when `true` the extension keeps RFC1918 / IPv6 ULA traffic outside
    /// the tunnel (LAN direct). When `false` LAN destinations are routed into the
    /// tunnel and follow the Xray routing rules. The proxy server address is excluded
    /// from the tunnel routes either way to prevent a routing loop.
    var bypassLAN: Bool = true
}

extension TunnelLaunchConfig {
    /// Tolerant decoding: a file written by a build that predates `bypassLAN` is still
    /// accepted (falling back to the default) instead of failing the tunnel start.
    init(from decoder: Decoder) throws {
        enum Key: String, CodingKey {
            case xrayJSON
            case onDemandEnabled
            case onDemandMode
            case bypassLAN
        }
        let container = try decoder.container(keyedBy: Key.self)
        xrayJSON = try container.decode(String.self, forKey: .xrayJSON)
        onDemandEnabled = try container.decodeIfPresent(Bool.self, forKey: .onDemandEnabled) ?? false
        onDemandMode = try container.decodeIfPresent(OnDemandMode.self, forKey: .onDemandMode) ?? .off
        bypassLAN = try container.decodeIfPresent(Bool.self, forKey: .bypassLAN) ?? true
    }
}

struct TunnelStatusFile: Codable, Sendable {
    var state: String
    var message: String?
    var updatedAt: Date
}
