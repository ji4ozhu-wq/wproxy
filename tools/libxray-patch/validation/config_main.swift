import Foundation

/// Generates one Xray config per supported protocol/transport combination into
/// `<output dir>/*.json`. `run_validation.sh` compiles this together with the
/// app's real `Models.swift` + `XrayConfigBuilder.swift`, so the files that the
/// Xray kernel validates come from exactly the code the app ships.
@main
struct ValidationConfigMain {
    static func main() {
        let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/wuji-xray-validation"
        let assetDirectory = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
        let geoIPTargets = ["ext:wuji-geoip-validate.dat:cn", "ext:wuji-geoip-validate.dat:private"]
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        let uuid = "b831381d-6324-4d53-ad4f-8cda48b30811"

        func base(_ proto: ProxyProtocol) -> NodeProfile {
            var profile = NodeProfile(id: proto.rawValue, groupID: "manual", name: "validate",
                                      proto: proto, server: "203.0.113.10", port: 443)
            profile.uuid = uuid
            profile.password = "secret-pass"
            profile.ssMethod = "aes-256-gcm"
            return profile
        }

        func write(_ name: String, _ json: String) {
            let path = (outputDir as NSString).appendingPathComponent(name + ".json")
            try? json.write(toFile: path, atomically: true, encoding: .utf8)
            print("wrote \(name).json (\(json.utf8.count) bytes)")
        }

        let settings = AppSettings.default
        let geoIPInput = { (profile: NodeProfile, settings: AppSettings) in
            XrayBuildInput(profile: profile,
                           settings: settings,
                           geoIPRuleTargets: geoIPTargets,
                           geoIPAssetDirectory: assetDirectory.isEmpty ? nil : assetDirectory)
        }

        do {
            var vmessTCP = base(.vmess)
            vmessTCP.security = .tls
            vmessTCP.sni = "cdn.example.com"
            write("vmess-tcp-tls", try XrayConfigBuilder.build(geoIPInput(vmessTCP, settings)))

            var vmessWS = base(.vmess)
            vmessWS.network = .ws
            vmessWS.security = .tls
            vmessWS.wsPath = "/ray"
            vmessWS.wsHost = "front.example.com"
            vmessWS.vmessSecurity = "aes-128-gcm"
            write("vmess-ws-tls", try XrayConfigBuilder.build(geoIPInput(vmessWS, settings)))

            var vlessReality = base(.vless)
            vlessReality.security = .reality
            vlessReality.sni = "www.microsoft.com"
            vlessReality.fingerprint = "chrome"
            vlessReality.realityPublicKey = "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"
            vlessReality.realityShortID = "6ba85179e30d4fc2"
            vlessReality.flow = "xtls-rprx-vision"
            write("vless-tcp-reality", try XrayConfigBuilder.build(geoIPInput(vlessReality, settings)))

            var vlessGRPC = base(.vless)
            vlessGRPC.network = .grpc
            vlessGRPC.grpcService = "grpc-service"
            vlessGRPC.security = .tls
            write("vless-grpc-tls", try XrayConfigBuilder.build(geoIPInput(vlessGRPC, settings)))

            var trojanTCP = base(.trojan)
            trojanTCP.security = .tls
            trojanTCP.sni = "trojan.example.com"
            write("trojan-tcp-tls", try XrayConfigBuilder.build(geoIPInput(trojanTCP, settings)))

            var trojanH2 = base(.trojan)
            trojanH2.network = .h2
            trojanH2.security = .tls
            trojanH2.wsPath = "/h2"
            trojanH2.wsHost = "h2.example.com"
            write("trojan-h2-tls", try XrayConfigBuilder.build(geoIPInput(trojanH2, settings)))

            let shadowsocks = base(.shadowsocks)
            write("ss-tcp", try XrayConfigBuilder.build(geoIPInput(shadowsocks, settings)))

            var globalSettings = AppSettings.default
            globalSettings.routingMode = .global
            write("global-mode", try XrayConfigBuilder.build(geoIPInput(vmessTCP, globalSettings)))

            // GeoIP asset rule: Xray must resolve xray.location.asset + ext:<file>:cc.
            write("geoip-asset-rule", try XrayConfigBuilder.build(geoIPInput(vmessTCP, settings)))

            var socks = base(.socks)
            socks.socksUsername = "alice"
            socks.password = "s3cret"
            write("socks5-auth", try XrayConfigBuilder.build(geoIPInput(socks, settings)))

            var socksOpen = base(.socks)
            socksOpen.password = ""
            write("socks5-open", try XrayConfigBuilder.build(geoIPInput(socksOpen, settings)))

            var localDNS = settings
            localDNS.dnsMode = .local
            write("dns-local", try XrayConfigBuilder.build(geoIPInput(vmessTCP, localDNS)))
        } catch {
            FileHandle.standardError.write(Data("configuration generation failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
