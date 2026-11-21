import Foundation

struct XrayBuildInput: Sendable {
    var profile: NodeProfile
    var settings: AppSettings
    /// Xray GeoIP rule targets for the selected "direct" countries, e.g.
    /// `["ext:wuji-geoip-<hash>.dat:cn", "ext:wuji-geoip-<hash>.dat:private"]`.
    /// Xray resolves them at runtime against the dataset exposed through
    /// `xray.location.asset`; no per-CIDR expansion happens in the config.
    var geoIPRuleTargets: [String] = []
    /// Directory exposed to Xray as `xray.location.asset`; contains the
    /// per-connection GeoIP asset plus the bundled geosite.dat used by split DNS.
    var geoIPAssetDirectory: String? = nil
    var dnsServer: String = "https://1.1.1.1/dns-query"
    /// Additional DoH upstreams tried in order. Both are pinned to the proxy.
    static let defaultDoHServers = ["https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"]
    var mtu: Int = 1380
    /// Literal IPs of the proxy server when the main app already resolved the host.
    /// Routing sends them direct so connections to the proxy endpoint never re-enter
    /// the proxy (loop guard). Empty is fine: the hostname rule below still covers it.
    var serverIPs: [String] = []
}

/// Builds the full Xray-core JSON config that the tunnel extension hands to
/// `libXray.Invoke(runXray)`.
///
/// Shape of the generated config (see docs/ids-engine.md for the annotated copy):
/// - one `tun` inbound (`tun-in`) whose fd is injected by the extension through
///   the root `env["xray.tun.fd"]` field before `runXray`; sniffing is off so
///   routing decisions use the packet's literal IP destination.
/// - `proxy` outbound for the selected node (VMess / VLESS / Trojan / Shadowsocks,
///   tcp / ws / grpc / h2 transport, none / tls / REALITY security).
/// - `direct` (freedom) and `dns-out` (protocol dns) outbounds.
/// - root `dns` uses DoH so DNS answers travel through the proxy, and the system
///   resolver is pointed at `198.18.0.2` by the packet tunnel settings; queries
///   arriving on port 53 are hijacked to `dns-out`.
/// - routing: port 53 -> dns-out, DoH upstream IP -> proxy, proxy server -> direct,
///   ONE direct rule for the selected GeoIP countries + LAN (resolved by Xray from
///   the per-connection `geoip.dat` asset), everything else -> proxy.
/// - `policy.system` enables the inbound byte counters that the forked libXray
///   `getTrafficStats` method reads; logging is disabled for memory reasons.
enum XrayConfigBuilder {
    static let tunInboundTag = "tun-in"
    static let proxyOutboundTag = "proxy"
    static let directOutboundTag = "direct"
    static let dnsOutboundTag = "dns-out"

    /// DNS endpoint advertised to the system by the packet tunnel provider.
    /// The address lives inside the tun subnet; the packet lands in the tun and
    /// is answered by the `dns` app through the port 53 routing rule.
    static let tunnelDNSv4Address = "198.18.0.2"
    static let tunnelDNSv6Address = "fd00:1234::2"

    /// libXray refuses Invoke requests larger than 16 MiB; keep a safety margin.
    static let maxConfigBytes = 15 * 1024 * 1024

    static func build(_ input: XrayBuildInput) throws -> String {
        try validate(input.profile)

        var root: [String: Any] = [:]
        root["log"] = ["loglevel": "none"]
        // The stats app must exist for policy.system counters (traffic stats).
        root["stats"] = [String: Any]()
        root["policy"] = [
            "system": [
                "statsInboundUplink": true,
                "statsInboundDownlink": true
            ]
        ]
        root["inbounds"] = [tunInbound(mtu: input.mtu)]
        root["outbounds"] = [
            try proxyOutbound(for: input.profile),
            ["tag": directOutboundTag, "protocol": "freedom", "settings": [String: Any]()],
            ["tag": dnsOutboundTag, "protocol": "dns", "settings": [String: Any]()]
        ]
        root["dns"] = try dnsConfiguration(input)
        root["routing"] = routingConfiguration(input)
        if let assetDirectory = input.geoIPAssetDirectory, !assetDirectory.isEmpty {
            // Xray-core applies root `env` entries to the process environment before
            // building the router; `xray.location.asset` is where it looks for geoip.dat.
            var env: [String: String] = [:]
            if let existing = root["env"] as? [String: String] { env = existing }
            env["xray.location.asset"] = assetDirectory
            root["env"] = env
        }

        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        } catch {
            throw XrayBuildError.serialize(error.localizedDescription)
        }
        guard data.count <= maxConfigBytes else {
            throw XrayBuildError.configTooLarge(bytes: data.count, limit: maxConfigBytes)
        }
        guard let json = String(data: data, encoding: .utf8) else {
            throw XrayBuildError.invalidProfile("error.xray.utf8")
        }
        return json
    }

    // MARK: - Inbound

    private static func tunInbound(mtu: Int) -> [String: Any] {
        // The extension already configures the utun interface address, routes and
        // DNS; Xray only needs to read/write packets on the fd it is handed.
        var settings: [String: Any] = [
            "name": "utun",
            "mtu": mtu,
            "userLevel": 0
        ]
        settings["gateway"] = ["169.254.10.1/30"]
        var inbound: [String: Any] = [
            "tag": tunInboundTag,
            "protocol": "tun",
            "settings": settings
        ]
        // Sniffing stays disabled: routing rules match literal IPs/CIDRs from the
        // tun packets, so rewriting destinations to domains would only add work.
        inbound["sniffing"] = ["enabled": false]
        return inbound
    }

    // MARK: - Outbound

    private static func proxyOutbound(for profile: NodeProfile) throws -> [String: Any] {
        var outbound: [String: Any] = [
            "tag": proxyOutboundTag,
            "protocol": proxyProtocolName(profile.proto)
        ]
        outbound["settings"] = proxySettings(profile)
        if profile.proto != .socks {
            outbound["streamSettings"] = streamSettings(profile)
            // Multiplexing is off: one TCP stream per connection is the least
            // surprising behaviour across VMess/VLESS/Trojan/SS servers and keeps
            // memory flat on the ~50 MB Network Extension budget.
            outbound["mux"] = ["enabled": false, "concurrency": -1]
        }
        return outbound
    }

    private static func proxyProtocolName(_ proto: ProxyProtocol) -> String {
        switch proto {
        case .vmess: return "vmess"
        case .vless: return "vless"
        case .trojan: return "trojan"
        case .shadowsocks: return "shadowsocks"
        case .socks: return "socks"
        }
    }

    private static func proxySettings(_ profile: NodeProfile) -> [String: Any] {
        switch profile.proto {
        case .vmess:
            let vmessSecurity = profile.vmessSecurity.trimmingCharacters(in: .whitespacesAndNewlines)
            var user: [String: Any] = [
                "id": profile.uuid,
                "alterId": profile.alterID,
                "security": vmessSecurity.isEmpty ? "auto" : vmessSecurity,
                "level": 0
            ]
            if !profile.flow.isEmpty { user["flow"] = profile.flow }
            return [
                "vnext": [[
                    "address": profile.server,
                    "port": profile.port,
                    "users": [user]
                ]]
            ]
        case .vless:
            var user: [String: Any] = [
                "id": profile.uuid,
                "encryption": "none",
                "level": 0
            ]
            if !profile.flow.isEmpty { user["flow"] = profile.flow }
            return [
                "vnext": [[
                    "address": profile.server,
                    "port": profile.port,
                    "users": [user]
                ]]
            ]
        case .trojan:
            return [
                "servers": [[
                    "address": profile.server,
                    "port": profile.port,
                    "password": profile.password,
                    "level": 0
                ]]
            ]
        case .socks:
            var server: [String: Any] = [
                "address": profile.server,
                "port": profile.port
            ]
            let username = profile.socksUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            if !username.isEmpty {
                server["users"] = [[
                    "user": username,
                    "pass": profile.password
                ]]
            }
            return ["servers": [server]]
        case .shadowsocks:
            return [
                "servers": [[
                    "address": profile.server,
                    "port": profile.port,
                    "method": profile.ssMethod,
                    "password": profile.password,
                    "level": 0,
                    "uot": false
                ]]
            ]
        }
    }

    // MARK: - Stream settings

    private static func streamSettings(_ profile: NodeProfile) -> [String: Any] {
        var settings: [String: Any] = [:]
        settings["network"] = networkName(profile.network)

        switch profile.security {
        case .none:
            break
        case .tls:
            settings["security"] = "tls"
            settings["tlsSettings"] = tlsSettings(profile)
        case .reality:
            settings["security"] = "reality"
            settings["realitySettings"] = realitySettings(profile)
        }

        switch profile.network {
        case .ws:
            settings["wsSettings"] = webSocketSettings(profile)
        case .grpc:
            var grpc: [String: Any] = ["multiMode": false]
            grpc["serviceName"] = profile.grpcService
            settings["grpcSettings"] = grpc
        case .h2, .http:
            // Xray-core removed the legacy HTTP/2 transport (network "http" / "h2");
            // its replacement is XHTTP stream-one over H2, which keeps the same
            // path/host node fields working.
            settings["xhttpSettings"] = xhttpSettings(profile)
        case .tcp:
            break
        }
        return settings
    }

    private static func networkName(_ transport: Transport) -> String {
        switch transport {
        case .tcp: return "tcp"
        case .ws: return "ws"
        case .grpc: return "grpc"
        case .h2, .http: return "xhttp"
        }
    }

    /// TLS/REALITY `serverName` fallback order: explicit SNI, then the
    /// WebSocket / XHTTP host header, then the server address. Falling straight back
    /// to the server means every ws/xhttp node without an explicit SNI would present
    /// the bare address (often an IP) in the ClientHello, which servers reject.
    private static func serverName(for profile: NodeProfile) -> String {
        let sni = profile.sni.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sni.isEmpty { return sni }
        let host = profile.wsHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.isEmpty { return host }
        return profile.server
    }

    private static func tlsSettings(_ profile: NodeProfile) -> [String: Any] {
        var tls: [String: Any] = [:]
        tls["serverName"] = serverName(for: profile)
        tls["allowInsecure"] = profile.allowInsecure
        // Fingerprint is a uTLS ClientHello preset (chrome / firefox / safari / ...).
        // Xray falls back to its own default when the field is left out.
        if !profile.fingerprint.isEmpty {
            tls["fingerprint"] = profile.fingerprint
        }
        return tls
    }

    private static func realitySettings(_ profile: NodeProfile) -> [String: Any] {
        var reality: [String: Any] = [:]
        reality["serverName"] = serverName(for: profile)
        reality["fingerprint"] = profile.fingerprint.isEmpty ? "chrome" : profile.fingerprint
        reality["publicKey"] = profile.realityPublicKey
        reality["shortId"] = profile.realityShortID
        reality["spiderX"] = "/"
        return reality
    }

    private static func webSocketSettings(_ profile: NodeProfile) -> [String: Any] {
        var ws: [String: Any] = ["path": normalizedPath(profile.wsPath)]
        if !profile.wsHost.isEmpty {
            ws["headers"] = ["Host": profile.wsHost]
        }
        return ws
    }

    private static func xhttpSettings(_ profile: NodeProfile) -> [String: Any] {
        var xhttp: [String: Any] = [
            "path": normalizedPath(profile.wsPath),
            // stream-one is the XHTTP mode that maps to the legacy HTTP/2 transport.
            "mode": "stream-one"
        ]
        if !profile.wsHost.isEmpty {
            xhttp["host"] = profile.wsHost
        }
        return xhttp
    }

    private static func normalizedPath(_ path: String) -> String {
        if path.isEmpty { return "/" }
        return path.hasPrefix("/") ? path : "/" + path
    }

    // MARK: - DNS

    /// Public DNS resolvers used by `.local` DNS mode; they answer from the local
    /// network so country CDN IPs match the user's actual location.
    static let localDNSServers = ["8.8.8.8", "1.1.1.1"]
    /// Domestic resolvers used only for `geosite:cn` domains in remote-DoH mode.
    /// Resolving Chinese sites from the proxy's location makes them return foreign
    /// CDN IPs, which then get proxied and hit anti-proxy redirect pages.
    static let cnDNSServers = ["223.5.5.5", "119.29.29.29"]

    private static func dnsConfiguration(_ input: XrayBuildInput) throws -> [String: Any] {
        let servers: [[String: Any]]
        switch input.settings.dnsMode {
        case .proxyDoH:
            let upstreams = dnsUpstreamURLs(input)
            guard !upstreams.isEmpty else {
                throw XrayBuildError.invalidDNS(input.dnsServer)
            }
            // Chinese domains use domestic DNS (direct); everything else goes
            // through the proxied DoH servers so blocked domains are not poisoned.
            var combined: [[String: Any]] = cnDNSServers.map {
                ["address": $0, "domains": ["geosite:cn"], "skipFallback": true]
            }
            combined.append(contentsOf: upstreams.map { ["address": $0] })
            servers = combined
        case .local:
            servers = localDNSServers.map { ["address": $0] }
        }
        var dns: [String: Any] = [
            "servers": servers,
            // IPv4-only answers match the IPv4-only tunnel/settings. See
            // TunnelNetworkSettingsFactory.dnsServers.
            "queryStrategy": "UseIPv4",
            "tag": "dns"
        ]
        dns["disableFallback"] = true
        return dns
    }

    /// Deduplicated DoH upstream URLs: the configured primary first, then the
    /// built-in 1.1.1.1 / 8.8.8.8 fallbacks.
    private static func dnsUpstreamURLs(_ input: XrayBuildInput) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in [input.dnsServer] + XrayBuildInput.defaultDoHServers {
            guard let url = dnsUpstreamURL(raw), seen.insert(url).inserted else { continue }
            result.append(url)
        }
        return result
    }

    private static func dnsUpstreamURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return nil
        }
        switch scheme {
        case "https", "h2c", "quic+local": return trimmed
        case "tcp", "udp": return trimmed
        default: return nil
        }
    }

    /// Literal host of the DoH server, when it is an IP. Pinned to the proxy so a
    /// "direct" country selection can never leak DNS around the tunnel.
    private static func dnsUpstreamIPs(_ input: XrayBuildInput) -> [String] {
        guard input.settings.dnsMode == .proxyDoH else { return [] }
        var result: [String] = []
        var seen = Set<String>()
        for raw in dnsUpstreamURLs(input) {
            guard let url = URL(string: raw), let host = url.host else { continue }
            let bareHost = host.hasPrefix("[") && host.hasSuffix("]")
                ? String(host.dropFirst().dropLast())
                : host
            let target: String?
            if bareHost.contains(":") {
                target = bareHost + "/128"
            } else {
                let parts = bareHost.split(separator: ".", omittingEmptySubsequences: false)
                let isIPv4 = parts.count == 4 && parts.allSatisfy { part in
                    guard let value = Int(part), value >= 0, value <= 255 else { return false }
                    return !part.isEmpty
                }
                target = isIPv4 ? bareHost + "/32" : nil
            }
            if let target, seen.insert(target).inserted { result.append(target) }
        }
        return result
    }

    // MARK: - Routing

    private static func routingConfiguration(_ input: XrayBuildInput) -> [String: Any] {
        let profile = input.profile
        var rules: [[String: Any]] = []

        // 1. All DNS traffic captured from the tun is answered by the dns app.
        rules.append([
            "type": "field",
            "port": "53",
            "outboundTag": dnsOutboundTag
        ])

        // 2. The DoH upstream itself must always use the proxy, otherwise a
        //    selected "direct" country containing the resolver IP would leak DNS.
        let upstreamIPs = dnsUpstreamIPs(input)
        if !upstreamIPs.isEmpty {
            rules.append([
                "type": "field",
                "ip": upstreamIPs,
                "outboundTag": proxyOutboundTag
            ])
        }
        if input.settings.dnsMode == .local {
            // Local resolvers must answer directly; otherwise the catch-all below
            // would send the DNS queries through the proxy and defeat the mode.
            rules.append([
                "type": "field",
                "ip": localDNSServers.map { "\($0)/32" },
                "outboundTag": directOutboundTag
            ])
        } else {
            // In remote-DoH mode the `geosite:cn` upstreams are domestic resolvers
            // and must answer directly.
            rules.append([
                "type": "field",
                "ip": cnDNSServers.map { "\($0)/32" },
                "outboundTag": directOutboundTag
            ])
        }

        // 3. Proxy endpoint is direct: prevents a connection to the server from
        //    being fed back into the proxy that is dialing it (loop guard).
        let serverTargets = serverAddressRuleTargets(profile: profile, serverIPs: input.serverIPs)
        if !serverTargets.isEmpty {
            var rule: [String: Any] = [
                "type": "field",
                "outboundTag": directOutboundTag
            ]
            if !serverTargets.ip.isEmpty { rule["ip"] = serverTargets.ip }
            if !serverTargets.domain.isEmpty { rule["domain"] = serverTargets.domain }
            rules.append(rule)
        }

        // 4. The one global direct rule: selected GeoIP countries (+ LAN/private
        //    when enabled) are matched by Xray at runtime from the per-connection
        //    geoip asset, so the config never grows with the size of the dataset.
        //    Global mode deliberately ignores it.
        let bypass = input.settings.routingMode == .rule
            ? input.geoIPRuleTargets.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            : []
        if !bypass.isEmpty {
            rules.append([
                "type": "field",
                "ip": bypass,
                "outboundTag": directOutboundTag
            ])
        }

        // 5. Everything else goes through the proxy.
        rules.append([
            "type": "field",
            "network": "tcp,udp",
            "outboundTag": proxyOutboundTag
        ])

        return [
            // Destinations arrive as literal IPs from the tun; no domain resolution
            // is needed for routing (and adding it would leak queries).
            "domainStrategy": "AsIs",
            "rules": rules
        ]
    }

    private struct ServerTargets {
        var ip: [String] = []
        var domain: [String] = []
        var isEmpty: Bool { ip.isEmpty && domain.isEmpty }
    }

    private static func serverAddressRuleTargets(profile: NodeProfile, serverIPs: [String]) -> ServerTargets {
        var targets = ServerTargets()
        let server = profile.server.trimmingCharacters(in: .whitespacesAndNewlines)
        if isIPLiteral(server) {
            targets.ip = [server.contains(":") ? "\(server)/128" : "\(server)/32"]
        } else if !server.isEmpty {
            // "domain:" prefix keeps Xray from interpreting the name as a plain
            // substring match (full match is what we want here).
            targets.domain = ["domain:\(server.lowercased())"]
        }
        for ip in serverIPs {
            let bare = ip.split(separator: "/").first.map(String.init) ?? ip
            let cidr = isIPLiteral(bare)
                ? (bare.contains(":") ? "\(bare)/128" : "\(bare)/32")
                : ip
            if isIPLiteral(bare) && !targets.ip.contains(cidr) {
                targets.ip.append(cidr)
            }
        }
        return targets
    }

    private static func isIPLiteral(_ value: String) -> Bool {
        var address = in_addr()
        if value.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 { return true }
        var address6 = in6_addr()
        return value.withCString({ inet_pton(AF_INET6, $0, &address6) }) == 1
    }

    // MARK: - Validation

    private static func validate(_ profile: NodeProfile) throws {
        let server = profile.server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !server.isEmpty else {
            throw XrayBuildError.invalidProfile("error.xray.noServer")
        }
        guard profile.port >= 1 && profile.port <= 65535 else {
            throw XrayBuildError.invalidProfile("error.xray.badPort")
        }
        switch profile.proto {
        case .vmess, .vless:
            guard isUUID(profile.uuid) else {
                throw XrayBuildError.invalidProfile("error.xray.noUUID")
            }
        case .trojan:
            guard !profile.password.isEmpty else {
                throw XrayBuildError.invalidProfile("error.xray.noTrojanPassword")
            }
        case .shadowsocks:
            guard !profile.ssMethod.isEmpty else {
                throw XrayBuildError.invalidProfile("error.xray.noSSMethod")
            }
            guard !profile.password.isEmpty else {
                throw XrayBuildError.invalidProfile("error.xray.noSSPassword")
            }
        case .socks:
            let username = profile.socksUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            guard username.isEmpty == profile.password.isEmpty else {
                throw XrayBuildError.invalidProfile("error.xray.socksCredentials")
            }
        }
        if profile.security == .reality {
            guard !profile.realityPublicKey.isEmpty else {
                throw XrayBuildError.invalidProfile("error.xray.noRealityKey")
            }
            guard profile.proto != .shadowsocks else {
                throw XrayBuildError.invalidProfile("error.xray.ssReality")
            }
        }
        if profile.network == .grpc && profile.grpcService.isEmpty {
            throw XrayBuildError.invalidProfile("error.xray.noGrpcService")
        }
    }

    private static func isUUID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 36 else { return false }
        return UUID(uuidString: trimmed) != nil
    }
}

enum XrayBuildError: LocalizedError {
    /// Static validation message; the associated value is a localization key.
    case invalidProfile(String)
    case configTooLarge(bytes: Int, limit: Int)
    case invalidDNS(String)
    case serialize(String)

    var errorDescription: String? {
        switch self {
        case .invalidProfile(let key):
            return NSLocalizedString(key, comment: "")
        case .configTooLarge(let bytes, let limit):
            return String(format: NSLocalizedString("error.xray.tooLarge", comment: ""), bytes / 1024, limit / 1024)
        case .invalidDNS(let server):
            return String(format: NSLocalizedString("error.xray.dns", comment: ""), server)
        case .serialize(let detail):
            return String(format: NSLocalizedString("error.xray.serialize", comment: ""), detail)
        }
    }
}
