import XCTest
@testable import Wuji

/// Covers the Xray configuration generation used by the tunnel extension
/// (impl-plan C1) plus the small pure helpers that can run in the simulator.
final class EngineTests: XCTestCase {
    private let uuid = "b831381d-6324-4d53-ad4f-8cda48b30811"
    private let realityKey = "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"

    // MARK: - Outbounds

    func testVMessOutboundUsesProfileFields() throws {
        var profile = baseProfile(proto: .vmess)
        profile.alterID = 64
        profile.vmessSecurity = "aes-128-gcm"

        let outbound = try proxyOutbound(for: profile)
        XCTAssertEqual(outbound["protocol"] as? String, "vmess")

        let settings = try XCTUnwrap(outbound["settings"] as? [String: Any])
        let vnext = try XCTUnwrap(settings["vnext"] as? [[String: Any]])
        XCTAssertEqual(vnext.count, 1)
        XCTAssertEqual(vnext.first?["address"] as? String, "example.com")
        XCTAssertEqual(vnext.first?["port"] as? Int, 443)

        let user = try XCTUnwrap((vnext.first?["users"] as? [[String: Any]])?.first)
        XCTAssertEqual(user["id"] as? String, uuid)
        XCTAssertEqual(user["alterId"] as? Int, 64)
        XCTAssertEqual(user["security"] as? String, "aes-128-gcm")
        XCTAssertEqual(user["level"] as? Int, 0)
    }

    func testVMessSecurityFallsBackToAutoWhenEmpty() throws {
        var profile = baseProfile(proto: .vmess)
        profile.vmessSecurity = ""

        let outbound = try proxyOutbound(for: profile)
        let settings = try XCTUnwrap(outbound["settings"] as? [String: Any])
        let vnext = try XCTUnwrap(settings["vnext"] as? [[String: Any]])
        let user = try XCTUnwrap((vnext.first?["users"] as? [[String: Any]])?.first)
        XCTAssertEqual(user["security"] as? String, "auto")
    }

    func testVLESSOutboundWithVisionFlow() throws {
        var profile = baseProfile(proto: .vless)
        profile.flow = "xtls-rprx-vision"
        profile.security = .tls
        profile.sni = "cdn.example.com"

        let outbound = try proxyOutbound(for: profile)
        XCTAssertEqual(outbound["protocol"] as? String, "vless")

        let settings = try XCTUnwrap(outbound["settings"] as? [String: Any])
        let vnext = try XCTUnwrap(settings["vnext"] as? [[String: Any]])
        let user = try XCTUnwrap((vnext.first?["users"] as? [[String: Any]])?.first)
        XCTAssertEqual(user["id"] as? String, uuid)
        XCTAssertEqual(user["encryption"] as? String, "none")
        XCTAssertEqual(user["flow"] as? String, "xtls-rprx-vision")

        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
        XCTAssertEqual(stream["security"] as? String, "tls")
        let tls = try XCTUnwrap(stream["tlsSettings"] as? [String: Any])
        XCTAssertEqual(tls["serverName"] as? String, "cdn.example.com")
    }

    // MARK: - TLS / REALITY server name fallback (B12)

    func testTLSServerNameFallsBackToWebSocketHost() throws {
        var profile = baseProfile(proto: .vmess)
        profile.network = .ws
        profile.security = .tls
        profile.sni = ""
        profile.wsHost = "chrome.example.com"
        profile.server = "203.0.113.10"

        let outbound = try proxyOutbound(for: profile)
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
        let tls = try XCTUnwrap(stream["tlsSettings"] as? [String: Any])
        XCTAssertEqual(tls["serverName"] as? String, "chrome.example.com",
                       "An empty SNI falls back to the ws/xhttp Host header, not the server IP")
    }

    func testTLSServerNameFallsBackToServerWhenNoHost() throws {
        var profile = baseProfile(proto: .vmess)
        profile.network = .tcp
        profile.security = .tls
        profile.sni = ""
        profile.wsHost = ""
        profile.server = "edge.example.net"

        let outbound = try proxyOutbound(for: profile)
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
        let tls = try XCTUnwrap(stream["tlsSettings"] as? [String: Any])
        XCTAssertEqual(tls["serverName"] as? String, "edge.example.net")
    }

    func testRealityServerNameFallsBackToWebSocketHost() throws {
        var profile = baseProfile(proto: .vless)
        profile.network = .ws
        profile.security = .reality
        profile.sni = ""
        profile.wsHost = "www.microsoft.com"
        profile.realityPublicKey = realityKey

        let outbound = try proxyOutbound(for: profile)
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
        let reality = try XCTUnwrap(stream["realitySettings"] as? [String: Any])
        XCTAssertEqual(reality["serverName"] as? String, "www.microsoft.com")
    }

    func testTrojanOutbound() throws {
        var profile = baseProfile(proto: .trojan)
        profile.password = "trojan-pass"

        let outbound = try proxyOutbound(for: profile)
        XCTAssertEqual(outbound["protocol"] as? String, "trojan")

        let settings = try XCTUnwrap(outbound["settings"] as? [String: Any])
        let servers = try XCTUnwrap(settings["servers"] as? [[String: Any]])
        XCTAssertEqual(servers.first?["address"] as? String, "example.com")
        XCTAssertEqual(servers.first?["port"] as? Int, 443)
        XCTAssertEqual(servers.first?["password"] as? String, "trojan-pass")
    }

    func testShadowsocksOutbound() throws {
        var profile = baseProfile(proto: .shadowsocks)
        profile.password = "ss-pass"
        profile.ssMethod = "aes-256-gcm"

        let outbound = try proxyOutbound(for: profile)
        XCTAssertEqual(outbound["protocol"] as? String, "shadowsocks")

        let settings = try XCTUnwrap(outbound["settings"] as? [String: Any])
        let servers = try XCTUnwrap(settings["servers"] as? [[String: Any]])
        XCTAssertEqual(servers.first?["method"] as? String, "aes-256-gcm")
        XCTAssertEqual(servers.first?["password"] as? String, "ss-pass")
    }

    // MARK: - Transports

    func testWebSocketTransport() throws {
        var profile = baseProfile(proto: .vmess)
        profile.network = .ws
        profile.security = .tls
        profile.wsPath = "ray"
        profile.wsHost = "front.example.com"

        let outbound = try proxyOutbound(for: profile)
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
        XCTAssertEqual(stream["network"] as? String, "ws")
        let ws = try XCTUnwrap(stream["wsSettings"] as? [String: Any])
        XCTAssertEqual(ws["path"] as? String, "/ray", "WebSocket paths are normalized with a leading slash")
        let headers = try XCTUnwrap(ws["headers"] as? [String: String])
        XCTAssertEqual(headers["Host"], "front.example.com")
    }

    func testGRPCTransport() throws {
        var profile = baseProfile(proto: .vless)
        profile.network = .grpc
        profile.grpcService = "grpc-service"

        let outbound = try proxyOutbound(for: profile)
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
        XCTAssertEqual(stream["network"] as? String, "grpc")
        let grpc = try XCTUnwrap(stream["grpcSettings"] as? [String: Any])
        XCTAssertEqual(grpc["serviceName"] as? String, "grpc-service")
        XCTAssertEqual(grpc["multiMode"] as? Bool, false)
    }

    func testHTTP2Transport() throws {
        var profile = baseProfile(proto: .trojan)
        profile.password = "pass"
        profile.network = .h2
        profile.security = .tls
        profile.wsPath = "/h2"
        profile.wsHost = "h2.example.com"

        let outbound = try proxyOutbound(for: profile)
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
        // Xray-core replaced the legacy HTTP/2 transport with XHTTP stream-one.
        XCTAssertEqual(stream["network"] as? String, "xhttp")
        let xhttp = try XCTUnwrap(stream["xhttpSettings"] as? [String: Any])
        XCTAssertEqual(xhttp["path"] as? String, "/h2")
        XCTAssertEqual(xhttp["host"] as? String, "h2.example.com")
        XCTAssertEqual(xhttp["mode"] as? String, "stream-one")
    }

    func testRealityTransport() throws {
        var profile = baseProfile(proto: .vless)
        profile.security = .reality
        profile.sni = "www.microsoft.com"
        profile.fingerprint = "chrome"
        profile.realityPublicKey = realityKey
        profile.realityShortID = "6ba85179e30d4fc2"

        let outbound = try proxyOutbound(for: profile)
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
        XCTAssertEqual(stream["security"] as? String, "reality")
        let reality = try XCTUnwrap(stream["realitySettings"] as? [String: Any])
        XCTAssertEqual(reality["serverName"] as? String, "www.microsoft.com")
        XCTAssertEqual(reality["fingerprint"] as? String, "chrome")
        XCTAssertEqual(reality["publicKey"] as? String, realityKey)
        XCTAssertEqual(reality["shortId"] as? String, "6ba85179e30d4fc2")
        XCTAssertNil(stream["tlsSettings"])
    }

    // MARK: - Inbound / DNS / policy

    func testTunInbound() throws {
        let root = try buildConfig(profile: baseProfile(proto: .vmess), mtu: 1400)
        let inbounds = try XCTUnwrap(root["inbounds"] as? [[String: Any]])
        XCTAssertEqual(inbounds.count, 1)
        let inbound = try XCTUnwrap(inbounds.first)
        XCTAssertEqual(inbound["tag"] as? String, XrayConfigBuilder.tunInboundTag)
        XCTAssertEqual(inbound["protocol"] as? String, "tun")

        let settings = try XCTUnwrap(inbound["settings"] as? [String: Any])
        XCTAssertEqual(settings["mtu"] as? Int, 1400)
        XCTAssertEqual(settings["name"] as? String, "utun")
        // The fd is injected by the extension at runtime, never baked into the file.
        XCTAssertNil(root["env"])
    }

    func testDNSConfigurationUsesDoH() throws {
        let root = try buildConfig(profile: baseProfile(proto: .vmess))
        let dns = try XCTUnwrap(root["dns"] as? [String: Any])
        let servers = try XCTUnwrap(dns["servers"] as? [[String: Any]])
        XCTAssertEqual(servers.count, 4)
        XCTAssertEqual(servers[0]["address"] as? String, "223.5.5.5")
        XCTAssertEqual(servers[1]["address"] as? String, "119.29.29.29")
        XCTAssertEqual(servers[2]["address"] as? String, "https://1.1.1.1/dns-query")
        XCTAssertEqual(servers[3]["address"] as? String, "https://8.8.8.8/dns-query")
        XCTAssertEqual(servers[0]["domains"] as? [String], ["geosite:cn"])
        XCTAssertEqual(dns["queryStrategy"] as? String, "UseIPv4")

        let tags = try outboundTags(root)
        XCTAssertEqual(tags.dns, "dns-out")
        let dnsOutbound = try outbound(tagged: "dns-out", in: root)
        XCTAssertEqual(dnsOutbound["protocol"] as? String, "dns")
    }

    func testPolicyEnablesInboundStatsForTrafficReporting() throws {
        let root = try buildConfig(profile: baseProfile(proto: .vmess))
        let policy = try XCTUnwrap(root["policy"] as? [String: Any])
        let system = try XCTUnwrap(policy["system"] as? [String: Any])
        XCTAssertEqual(system["statsInboundUplink"] as? Bool, true)
        XCTAssertEqual(system["statsInboundDownlink"] as? Bool, true)
        XCTAssertNotNil(root["stats"], "The stats app must exist for the policy counters to be created")

        let log = try XCTUnwrap(root["log"] as? [String: Any])
        XCTAssertEqual(log["loglevel"] as? String, "none")
    }

    // MARK: - Routing

    func testRoutingPort53IsHandledFirst() throws {
        let root = try buildConfig(profile: baseProfile(proto: .vmess),
                                   geoIPRuleTargets: ["ext:wuji-geoip-test.dat:cn"])
        let routing = try XCTUnwrap(root["routing"] as? [String: Any])
        XCTAssertEqual(routing["domainStrategy"] as? String, "AsIs")
        let rules = try XCTUnwrap(routing["rules"] as? [[String: Any]])
        XCTAssertEqual(rules.first?["port"] as? String, "53")
        XCTAssertEqual(rules.first?["outboundTag"] as? String, "dns-out")
    }

    func testRoutingSendsDNSUpstreamThroughProxy() throws {
        // 1.1.1.1 is the DoH upstream; a "direct" country containing it must not
        // bypass the proxy, otherwise DNS would leak.
        let input = XrayBuildInput(profile: baseProfile(proto: .vmess),
                                   settings: .default,
                                   geoIPRuleTargets: ["ext:wuji-geoip-test.dat:cn"],
                                   geoIPAssetDirectory: "/tmp/wuji-geoip-asset")
        let root = try parse(XrayConfigBuilder.build(input))
        let rules = try XCTUnwrap((try XCTUnwrap(root["routing"] as? [String: Any]))["rules"] as? [[String: Any]])
        let pinned = try XCTUnwrap(rules.first { ($0["ip"] as? [String])?.contains("1.1.1.1/32") == true })
        XCTAssertEqual(pinned["outboundTag"] as? String, "proxy")
        let directRule = try XCTUnwrap(rules.first { ($0["ip"] as? [String])?.contains("ext:wuji-geoip-test.dat:cn") == true })
        XCTAssertEqual(directRule["outboundTag"] as? String, "direct")
        let env = try XCTUnwrap(root["env"] as? [String: String])
        XCTAssertEqual(env["xray.location.asset"], "/tmp/wuji-geoip-asset",
                       "Xray must be told where the per-connection geoip asset lives")
    }

    func testRoutingSendsProxyEndpointDirect() throws {
        var profile = baseProfile(proto: .trojan)
        profile.password = "pass"
        profile.server = "203.0.113.9"
        let input = XrayBuildInput(profile: profile, settings: .default, serverIPs: ["203.0.113.9"])
        let root = try parse(XrayConfigBuilder.build(input))
        let rules = try XCTUnwrap((try XCTUnwrap(root["routing"] as? [String: Any]))["rules"] as? [[String: Any]])
        let serverRule = try XCTUnwrap(rules.first { ($0["ip"] as? [String])?.contains("203.0.113.9/32") == true })
        XCTAssertEqual(serverRule["outboundTag"] as? String, "direct")
    }

    func testRoutingSendsHostnameProxyEndpointDirect() throws {
        var profile = baseProfile(proto: .vless)
        profile.server = "Node.Example.com"
        let input = XrayBuildInput(profile: profile, settings: .default)
        let root = try parse(XrayConfigBuilder.build(input))
        let rules = try XCTUnwrap((try XCTUnwrap(root["routing"] as? [String: Any]))["rules"] as? [[String: Any]])
        let domainRule = try XCTUnwrap(rules.first { ($0["domain"] as? [String])?.contains("domain:node.example.com") == true })
        XCTAssertEqual(domainRule["outboundTag"] as? String, "direct")
    }

    func testRoutingUsesOneGlobalGeoIPDirectRule() throws {
        // The user-facing rule: selected countries + LAN are expressed as ONE rule
        // whose IP values are Xray GeoIP asset targets, not expanded CIDRs.
        let targets = ["ext:wuji-geoip-test.dat:cn",
                       "ext:wuji-geoip-test.dat:jp",
                       "ext:wuji-geoip-test.dat:private",
                       ""]
        let root = try buildConfig(profile: baseProfile(proto: .vmess),
                                   geoIPRuleTargets: targets,
                                   geoIPAssetDirectory: "/tmp/wuji-geoip-asset")
        let rules = try XCTUnwrap((try XCTUnwrap(root["routing"] as? [String: Any]))["rules"] as? [[String: Any]])
        let geoRules = rules.filter { rule in
            guard let ips = rule["ip"] as? [String] else { return false }
            return ips.contains { $0.hasPrefix("ext:") }
        }
        XCTAssertEqual(geoRules.count, 1, "There must be exactly one global GeoIP direct rule")
        let directRule = try XCTUnwrap(geoRules.first)
        XCTAssertEqual(directRule["outboundTag"] as? String, "direct")
        let values = try XCTUnwrap(directRule["ip"] as? [String])
        XCTAssertEqual(values, ["ext:wuji-geoip-test.dat:cn",
                                "ext:wuji-geoip-test.dat:jp",
                                "ext:wuji-geoip-test.dat:private"],
                       "Empty targets are dropped and the rest keep their order")
        XCTAssertFalse(values.contains { $0.contains("/") }, "CIDRs must not be expanded into the config")

        let catchAll = try XCTUnwrap(rules.last)
        XCTAssertEqual(catchAll["network"] as? String, "tcp,udp")
        XCTAssertEqual(catchAll["outboundTag"] as? String, "proxy")
    }

    func testGlobalModeIgnoresGeoIPTargets() throws {
        var settings = AppSettings.default
        settings.routingMode = .global
        settings.bypassLAN = true
        let input = XrayBuildInput(profile: baseProfile(proto: .vmess),
                                   settings: settings,
                                   geoIPRuleTargets: ["ext:wuji-geoip-test.dat:cn",
                                                      "ext:wuji-geoip-test.dat:private"],
                                   geoIPAssetDirectory: "/tmp/wuji-geoip-asset")
        let root = try parse(XrayConfigBuilder.build(input))
        let routing = try XCTUnwrap(root["routing"] as? [String: Any])
        let rules = try XCTUnwrap(routing["rules"] as? [[String: Any]])
        let allIPs = rules.compactMap { $0["ip"] as? [String] }.flatMap { $0 }
        XCTAssertFalse(allIPs.contains { $0.hasPrefix("ext:") },
                       "Global mode must not emit bypass GeoIP rules")
        XCTAssertEqual(outboundTag(of: rules.last), "proxy")
    }

    // MARK: - Config shape helpers

    func testOutboundOrderAndTags() throws {
        let root = try buildConfig(profile: baseProfile(proto: .vmess))
        let outbounds = try XCTUnwrap(root["outbounds"] as? [[String: Any]])
        XCTAssertEqual(outbounds.map { $0["tag"] as? String }, ["proxy", "direct", "dns-out"])
        XCTAssertEqual(outbounds.first?["protocol"] as? String, "vmess")
        XCTAssertEqual(outbounds[1]["protocol"] as? String, "freedom")
        XCTAssertEqual(outbounds[2]["protocol"] as? String, "dns")
        // The first outbound is the default route of the router.
        let mux = outbounds.first?["mux"] as? [String: Any]
        XCTAssertEqual(mux?["enabled"] as? Bool, false)
    }

    func testConfigurationIsDeterministic() throws {
        let profile = baseProfile(proto: .vmess)
        let input = XrayBuildInput(profile: profile, settings: .default,
                                   geoIPRuleTargets: ["ext:wuji-geoip-test.dat:cn"],
                                   geoIPAssetDirectory: "/tmp/wuji-geoip-asset")
        let first = try XrayConfigBuilder.build(input)
        let second = try XrayConfigBuilder.build(input)
        XCTAssertEqual(first, second)
        let root = try parse(first)
        XCTAssertNotNil(root["inbounds"])
        XCTAssertNotNil(root["outbounds"])
        XCTAssertNotNil(root["routing"])
        XCTAssertNotNil(root["dns"])
    }

    func testNilFdIsNeverEmbedded() throws {
        let json = try XrayConfigBuilder.build(XrayBuildInput(profile: baseProfile(proto: .vmess),
                                                             settings: .default))
        XCTAssertFalse(json.contains("xray.tun.fd"))
    }

    // MARK: - Validation

    func testInvalidProfilesThrow() {
        assertInvalid { $0.server = "" }
        assertInvalid { $0.port = 0 }
        assertInvalid { $0.port = 70000 }
        assertInvalid { $0.uuid = "not-a-uuid" }

        assertInvalid(proto: .trojan) { $0.password = "" }
        assertInvalid(proto: .shadowsocks) { $0.password = "" }
        assertInvalid(proto: .shadowsocks) { $0.ssMethod = "" }
        assertInvalid(proto: .vless) { $0.security = .reality; $0.realityPublicKey = "" }
        assertInvalid(proto: .vless) { $0.network = .grpc; $0.grpcService = "" }
        assertInvalid(proto: .shadowsocks) { $0.security = .reality; $0.realityPublicKey = realityKey }
    }

    // MARK: - Fixtures

    private func baseProfile(proto: ProxyProtocol) -> NodeProfile {
        var profile = NodeProfile(id: "test-\(proto.rawValue)",
                                  groupID: "manual",
                                  name: "Test node",
                                  proto: proto,
                                  server: "example.com",
                                  port: 443)
        profile.uuid = uuid
        profile.password = proto == .trojan || proto == .shadowsocks ? "secret" : ""
        profile.ssMethod = proto == .shadowsocks ? "aes-256-gcm" : ""
        profile.network = .tcp
        profile.security = .none
        return profile
    }

    // MARK: - SOCKS5

    func testSOCKS5OutboundWithAuthentication() throws {
        var profile = NodeProfile(id: "socks-auth", groupID: "manual", name: "socks",
                                  proto: .socks, server: "198.51.100.20", port: 1080)
        profile.socksUsername = "alice"
        profile.password = "s3cret"
        let root = try buildConfig(profile: profile)
        let outbound = try outbound(tagged: "proxy", in: root)
        XCTAssertEqual(outbound["protocol"] as? String, "socks")
        XCTAssertNil(outbound["streamSettings"], "SOCKS5 must not carry transport/TLS settings")
        XCTAssertNil(outbound["mux"], "SOCKS5 must not carry mux settings")
        let settings = try XCTUnwrap(outbound["settings"] as? [String: Any])
        let server = try XCTUnwrap((settings["servers"] as? [[String: Any]])?.first)
        XCTAssertEqual(server["address"] as? String, "198.51.100.20")
        XCTAssertEqual(server["port"] as? Int, 1080)
        let user = try XCTUnwrap((server["users"] as? [[String: Any]])?.first)
        XCTAssertEqual(user["user"] as? String, "alice")
        XCTAssertEqual(user["pass"] as? String, "s3cret")
    }

    func testSOCKS5WithoutAuthenticationOmitsUsers() throws {
        let profile = NodeProfile(id: "socks-open", groupID: "manual", name: "socks",
                                  proto: .socks, server: "198.51.100.21", port: 1080)
        let root = try buildConfig(profile: profile)
        let outbound = try outbound(tagged: "proxy", in: root)
        let settings = try XCTUnwrap(outbound["settings"] as? [String: Any])
        let server = try XCTUnwrap((settings["servers"] as? [[String: Any]])?.first)
        XCTAssertNil(server["users"], "An unauthenticated SOCKS5 node must not emit a users array")
    }

    func testSOCKS5CredentialPairIsValidated() throws {
        var profile = NodeProfile(id: "socks-bad", groupID: "manual", name: "socks",
                                  proto: .socks, server: "198.51.100.22", port: 1080)
        profile.socksUsername = "alice" // password missing
        XCTAssertThrowsError(try XrayConfigBuilder.build(.init(profile: profile, settings: .default)))
        profile.socksUsername = ""
        profile.password = "s3cret" // username missing
        XCTAssertThrowsError(try XrayConfigBuilder.build(.init(profile: profile, settings: .default)))
    }

    // MARK: - DNS handling

    func testProxyDoHIsTheDefaultDNSMode() throws {
        let root = try buildConfig(profile: baseProfile(proto: .vmess))
        let dns = try XCTUnwrap(root["dns"] as? [String: Any])
        let serverAddresses = try XCTUnwrap((dns["servers"] as? [[String: Any]])?
            .compactMap { $0["address"] as? String })
        XCTAssertEqual(serverAddresses, ["223.5.5.5", "119.29.29.29", "https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"])
        XCTAssertEqual(AppSettings.default.dnsMode, .proxyDoH)
    }

    func testLocalDNSModeUsesDirectResolvers() throws {
        var settings = AppSettings.default
        settings.dnsMode = .local
        let input = XrayBuildInput(profile: baseProfile(proto: .vmess), settings: settings)
        let root = try parse(XrayConfigBuilder.build(input))
        let dns = try XCTUnwrap(root["dns"] as? [String: Any])
        let addresses = try XCTUnwrap(dns["servers"] as? [[String: Any]])
            .compactMap { $0["address"] as? String }
        XCTAssertEqual(addresses, ["8.8.8.8", "1.1.1.1"])
        let rules = try XCTUnwrap((try XCTUnwrap(root["routing"] as? [String: Any]))["rules"] as? [[String: Any]])
        let dnsRule = try XCTUnwrap(rules.first {
            ($0["ip"] as? [String])?.contains("8.8.8.8/32") == true
        })
        XCTAssertEqual(dnsRule["outboundTag"] as? String, "direct",
                       "Local resolvers must answer directly, not through the proxy")
        let localPins = rules.filter { ($0["ip"] as? [String])?.contains("1.1.1.1/32") == true }
        XCTAssertFalse(localPins.contains { $0["outboundTag"] as? String == "proxy" },
                       "Local mode must not pin the DoH upstream through the proxy")
    }

    private func buildConfig(profile: NodeProfile,
                             geoIPRuleTargets: [String] = [],
                             geoIPAssetDirectory: String? = nil,
                             mtu: Int = 1380) throws -> [String: Any] {
        let input = XrayBuildInput(profile: profile,
                                   settings: .default,
                                   geoIPRuleTargets: geoIPRuleTargets,
                                   geoIPAssetDirectory: geoIPAssetDirectory,
                                   mtu: mtu)
        return try parse(XrayConfigBuilder.build(input))
    }

    private func parse(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func proxyOutbound(for profile: NodeProfile) throws -> [String: Any] {
        let root = try buildConfig(profile: profile)
        return try outbound(tagged: "proxy", in: root)
    }

    private func outbound(tagged tag: String, in root: [String: Any]) throws -> [String: Any] {
        let outbounds = try XCTUnwrap(root["outbounds"] as? [[String: Any]])
        return try XCTUnwrap(outbounds.first { $0["tag"] as? String == tag })
    }

    private func outboundTags(_ root: [String: Any]) throws -> (proxy: String, direct: String, dns: String) {
        let outbounds = try XCTUnwrap(root["outbounds"] as? [[String: Any]])
        let tags = outbounds.compactMap { $0["tag"] as? String }
        return (tags[0], tags[1], tags[2])
    }

    private func outboundTag(of rule: [String: Any]?) -> String? {
        rule?["outboundTag"] as? String
    }

    private func assertInvalid(proto: ProxyProtocol = .vmess,
                               _ mutate: (inout NodeProfile) -> Void,
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        var profile = baseProfile(proto: proto)
        mutate(&profile)
        let input = XrayBuildInput(profile: profile, settings: .default)
        XCTAssertThrowsError(try XrayConfigBuilder.build(input), file: file, line: line)
    }
}
