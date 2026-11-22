import XCTest
import Network
@testable import Wuji

// MARK: - Data layer tests (docs/impl-plan.md B1–B10, F1)

final class DataTests: XCTestCase {
    // MARK: - Fixtures

    private struct DatabaseFixture {
        let db: AppDatabase
        let url: URL
    }

    private func makeDatabase() throws -> DatabaseFixture {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wuji-data-tests-\(UUID().uuidString).sqlite3")
        let db = AppDatabase(databaseURL: url, allowsDemoSeed: false)
        try db.openIfNeeded()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + ".demo-seeded"))
        }
        return DatabaseFixture(db: db, url: url)
    }

    private func makeEvidenceProfile(id: String = UUID().uuidString,
                                     groupID: String = ProfileStore.manualGroupID,
                                     proto: ProxyProtocol = .vless) -> NodeProfile {
        var profile = NodeProfile(id: id, groupID: groupID, name: "Tokyo 01", proto: proto,
                                  server: "203.0.113.24", port: 443)
        profile.uuid = "b9d3f7e2-6a4c-4f5d-8e91-2c7a0e4b9f3d"
        profile.password = "secret"
        profile.ssMethod = "chacha20-ietf-poly1305"
        profile.vmessSecurity = "aes-128-gcm"
        profile.alterID = 0
        profile.network = .ws
        profile.security = .reality
        profile.sni = "example.com"
        profile.wsPath = "/ray"
        profile.wsHost = "example.com"
        profile.grpcService = "grpc-service"
        profile.fingerprint = "chrome"
        profile.allowInsecure = true
        profile.realityPublicKey = "jNXHt1o0Yp1lGk2sQz8cVb4eRf6tYu7iOp9aS3dF5gH"
        profile.realityShortID = "a1b2c3d4"
        profile.flow = "xtls-rprx-vision"
        profile.rawURI = "vless://b9d3f7e2-6a4c-4f5d-8e91-2c7a0e4b9f3d@203.0.113.24:443"
        profile.latencyMs = 88
        profile.latencyAt = Date(timeIntervalSince1970: 1_700_000_000)
        // Dates are stored as integer seconds; use a second-precision timestamp so
        // the round-trip comparison is exact.
        profile.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        return profile
    }

    // MARK: - B1 database

    func testDatabaseOpensAndRunsMultiStatementScript() throws {
        let fixture = try makeDatabase()
        let store = ProfileStore(db: fixture.db)
        let group = try store.ensureManualGroup()
        var profile = makeEvidenceProfile(groupID: group.id)
        try store.upsert(profile: profile)
        XCTAssertEqual(try store.count(), 1)

        // The clear-data action in Settings uses one multi-statement script.
        try fixture.db.execute("DELETE FROM profiles; DELETE FROM groups; DELETE FROM subscriptions; DELETE FROM settings;")
        XCTAssertEqual(try store.count(), 0)
        XCTAssertEqual(try store.groups().count, 0)

        // Reopening the same file keeps the schema and settings.
        let settingsStore = SettingsStore(db: fixture.db)
        var settings = AppSettings.default
        settings.routingMode = .global
        try settingsStore.save(settings)
        try fixture.db.close()
        try fixture.db.openIfNeeded()
        XCTAssertEqual(settingsStore.load().routingMode, .global)
        XCTAssertTrue(profile.name.isEmpty == false)
    }

    func testTransactionRollback() throws {
        let fixture = try makeDatabase()
        let store = ProfileStore(db: fixture.db)
        _ = try store.ensureManualGroup()
        struct Expected: Error {}
        XCTAssertThrowsError(try fixture.db.transaction {
            try fixture.db.execute("INSERT INTO groups (id, name, type, sort_order, created_at) VALUES ('x', 'X', 'manual', 0, 0);")
            try fixture.db.execute("INSERT INTO groups (id, name, type, sort_order, created_at) VALUES ('y', 'Y', 'manual', 0, 0);")
            throw Expected()
        })
        XCTAssertEqual(try store.groups().count, 1, "outer manual group only; the transaction must roll back")
    }

    func testForeignKeysCascadeWhenGroupIsDeleted() throws {
        let fixture = try makeDatabase()
        let store = ProfileStore(db: fixture.db)
        let group = NodeGroup(id: "sub-group", name: "Airport", kind: .subscription,
                              subscriptionID: "sub-1", sortOrder: 1)
        try store.upsert(group: group)
        try store.upsert(profile: makeEvidenceProfile(groupID: group.id))
        try store.upsert(profile: makeEvidenceProfile(groupID: group.id))
        XCTAssertEqual(try store.profiles(inGroup: group.id).count, 2)
        try store.delete(groupID: group.id)
        XCTAssertEqual(try store.profiles(inGroup: group.id).count, 0)
    }

    // MARK: - B2/B3 profiles + settings

    func testSettingsRoundTrip() throws {
        let fixture = try makeDatabase()
        let store = SettingsStore(db: fixture.db)
        var settings = AppSettings.default
        settings.bypassLAN = false
        settings.bypassCountryCodes = ["CN", "JP"]
        settings.routingMode = .global
        settings.onDemandMode = .wifi
        settings.latencyTestURL = "https://example.com/generate_204"
        settings.latencyTimeout = 3
        settings.activeProfileID = "profile-1"
        settings.onboardingDone = true
        settings.consentAccepted = true
        settings.firstConnectExplained = true
        settings.sortField = "name"
        settings.sortAscending = false
        settings.subscriptionAutoUpdateEnabled = false
        try store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    func testProfileRoundTripAllProtocols() throws {
        let fixture = try makeDatabase()
        let store = ProfileStore(db: fixture.db)
        let group = try store.ensureManualGroup()

        for (index, proto) in ProxyProtocol.allCases.enumerated() {
            var profile = makeEvidenceProfile(groupID: group.id, proto: proto)
            profile.id = "profile-\(index)"
            profile.name = "\(proto.displayName) node"
            profile.server = "203.0.113.\(10 + index)"
            profile.port = 443 + index
            try store.upsert(profile: profile)

            var expected = profile
            guard let loaded = try store.profile(id: profile.id) else {
                XCTFail("Missing \(proto) profile after round trip")
                continue
            }
            expected.updatedAt = loaded.updatedAt
            XCTAssertEqual(loaded, expected, "\(proto) round trip must preserve every column")
            XCTAssertEqual(loaded.vmessSecurity, "aes-128-gcm")
            XCTAssertEqual(loaded.rawURI, expected.rawURI)
            XCTAssertEqual(loaded.latencyMs, 88)
        }
        XCTAssertEqual(try store.count(), ProxyProtocol.allCases.count)
    }

    func testProfileUpdateKeepsIDAndRefreshesTimestamp() throws {
        let fixture = try makeDatabase()
        let store = ProfileStore(db: fixture.db)
        let group = try store.ensureManualGroup()
        var profile = makeEvidenceProfile(groupID: group.id)
        try store.upsert(profile: profile)
        let first = try XCTUnwrap(try store.profile(id: profile.id))

        profile.name = "Renamed"
        profile.port = 8443
        try store.upsert(profile: profile)
        let second = try XCTUnwrap(try store.profile(id: profile.id))
        XCTAssertEqual(second.name, "Renamed")
        XCTAssertEqual(second.port, 8443)
        XCTAssertEqual(try store.count(), 1)
        XCTAssertGreaterThanOrEqual(second.updatedAt, first.updatedAt)
    }

    func testFindDuplicateAndBatchLatencyWriteBack() throws {
        let fixture = try makeDatabase()
        let store = ProfileStore(db: fixture.db)
        let group = try store.ensureManualGroup()
        let profile = makeEvidenceProfile(groupID: group.id)
        try store.upsert(profile: profile)

        var duplicate = profile
        duplicate.id = UUID().uuidString
        XCTAssertNotNil(try store.findDuplicate(of: duplicate))
        var different = duplicate
        different.uuid = UUID().uuidString
        XCTAssertNil(try store.findDuplicate(of: different))

        let other = makeEvidenceProfile(id: "other", groupID: group.id)
        try store.upsert(profile: other)
        try store.updateLatencies([profile.id: 25, other.id: nil])
        XCTAssertEqual(try store.profile(id: profile.id)?.latencyMs, 25)
        XCTAssertNil(try store.profile(id: other.id)?.latencyMs)
        let rawLatency = try fixture.db.query("SELECT latency_ms FROM profiles WHERE id = ?;", [other.id])
        XCTAssertNil(rawLatency.first?["latency_ms"],
                     "A nil optional must be stored as SQL NULL, not the text Optional(nil)")
    }

    func testGroupOrderingAndManualGroupIsStable() throws {
        let fixture = try makeDatabase()
        let store = ProfileStore(db: fixture.db)
        let manual = try store.ensureManualGroup()
        XCTAssertEqual(manual.id, ProfileStore.manualGroupID)
        XCTAssertEqual(try store.ensureManualGroup().id, manual.id, "manual group must be idempotent")
        try store.upsert(group: NodeGroup(id: "a", name: "A", kind: .subscription, subscriptionID: "s", sortOrder: 3))
        try store.upsert(group: NodeGroup(id: "b", name: "B", kind: .subscription, subscriptionID: "t", sortOrder: 2))
        XCTAssertEqual(try store.groups().map(\.id), [ProfileStore.manualGroupID, "b", "a"])
        XCTAssertNil(try store.group(id: ProfileStore.manualGroupID)?.subscriptionID,
                     "The manual group is not attached to a subscription")
    }

    // MARK: - B4 subscriptions

    func testSubscriptionRoundTripAndDueLogic() throws {
        let fixture = try makeDatabase()
        let store = SubscriptionStore(db: fixture.db)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let subscription = Subscription(
            id: "sub-1", url: "https://example.com/sub", name: "Airport",
            autoUpdateInterval: 21_600, lastUpdatedAt: now.addingTimeInterval(-7_200),
            trafficUpload: 1_000, trafficDownload: 2_000, trafficTotal: 100_000,
            expireAt: now.addingTimeInterval(86_400), lastError: nil,
            createdAt: now.addingTimeInterval(-86_400)
        )
        try store.upsert(subscription)
        XCTAssertEqual(try store.all(), [subscription])
        XCTAssertEqual(subscription.trafficUsed, 3_000)
        let rawSubscription = try fixture.db.query("SELECT * FROM subscriptions WHERE id = 'sub-1';")
        XCTAssertNil(rawSubscription.first?["last_error"],
                     "A nil optional must be stored as SQL NULL, not the text Optional(nil)")

        XCTAssertFalse(SubscriptionStore.isDue(subscription, now: now))
        XCTAssertTrue(SubscriptionStore.isDue(subscription, now: now.addingTimeInterval(21_600)))
        XCTAssertEqual(try store.dueForAutoUpdate(globalEnabled: true, now: now.addingTimeInterval(21_600)).count, 1)
        XCTAssertEqual(try store.dueForAutoUpdate(globalEnabled: false, now: now.addingTimeInterval(21_600)).count, 0)

        try store.recordFailure(subscription, error: "Network error", now: now)
        XCTAssertEqual(try store.subscription(id: "sub-1")?.lastError, "Network error")
        XCTAssertNotNil(try store.subscription(id: "sub-1"))
    }

    func testDeletingSubscriptionRemovesGroupAndNodes() throws {
        let fixture = try makeDatabase()
        let profileStore = ProfileStore(db: fixture.db)
        let subscriptionStore = SubscriptionStore(db: fixture.db)
        let subscription = Subscription(id: "sub-1", url: "https://example.com/sub", name: "Airport",
                                        autoUpdateInterval: nil, lastUpdatedAt: nil, trafficUpload: nil,
                                        trafficDownload: nil, trafficTotal: nil, expireAt: nil,
                                        lastError: nil, createdAt: Date())
        try subscriptionStore.upsert(subscription)
        try profileStore.upsert(group: NodeGroup(id: "group-1", name: "Airport", kind: .subscription,
                                                 subscriptionID: "sub-1", sortOrder: 1))
        try profileStore.upsert(profile: makeEvidenceProfile(groupID: "group-1"))
        XCTAssertEqual(try profileStore.count(), 1)

        try subscriptionStore.delete(subscriptionID: "sub-1")
        XCTAssertEqual(try subscriptionStore.count(), 0)
        XCTAssertEqual(try profileStore.count(), 0)
        XCTAssertEqual(try profileStore.group(id: "group-1"), nil)
    }

    // MARK: - B5 URI parsing

    private let vmessLink: String = {
        let json: [String: Any] = [
            "v": "2", "ps": "Tokyo VMess", "add": "192.0.2.11", "port": "443",
            "id": "8f1c0f0e-2a3b-4c5d-9e6f-1a2b3c4d5e6f", "aid": "0", "scy": "auto",
            "net": "ws", "type": "none", "host": "jp1.example.com", "path": "/ray",
            "tls": "tls", "sni": "jp1.example.com", "fp": "chrome"
        ]
        let data = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        return "vmess://" + data.base64EncodedString()
    }()

    /// Legacy VMess payloads are base64 JSON with string numbers and a `ps` name.
    private let legacyVMessLink: String = {
        let json: [String: Any] = [
            "v": "2", "ps": "Legacy VMess", "add": "198.51.100.99", "port": "8443",
            "id": "5a4b3c2d-1e0f-4a9b-8c7d-6e5f4a3b2c1d", "aid": "0", "scy": "auto",
            "net": "grpc", "type": "none", "host": "", "path": "legacy-service",
            "tls": "tls", "sni": "legacy.example.com", "fp": ""
        ]
        let data = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        return "vmess://" + data.base64EncodedString()
    }()

    private let vlessRealityLink = "vless://3c1d5e7f-9a2b-4c6d-8e0f-1a3b5c7d9e2f@192.0.2.12:443"
        + "?encryption=none&security=reality&sni=www.example.com&fp=chrome"
        + "&pbk=jNXHt1o0Yp1lGk2sQz8cVb4eRf6tYu7iOp9aS3dF5gH&sid=a1b2c3d4&type=tcp&flow=xtls-rprx-vision#Seoul%20Reality"

    private let vlessWebSocketLink = "vless://3c1d5e7f-9a2b-4c6d-8e0f-1a3b5c7d9e2f@198.51.100.7:443"
        + "?encryption=none&security=tls&sni=cdn.example.com&type=ws&host=cdn.example.com&path=%2Fws%3Fed%3D2048#Frankfurt%20WS"

    private let trojanWebSocketLink = "trojan://demo-pass%40word@198.51.100.8:443"
        + "?security=tls&sni=t.example.com&type=ws&path=%2Ftr&host=t.example.com#LA%20Trojan"

    private let trojanTCPLink = "trojan://simple-pass@198.51.100.9:8443#Osaka%20Trojan"

    private var shadowsocksSIP002Link: String {
        let userinfo = URIParserCore.base64URLString("aes-256-gcm:demo-pass")
        return "ss://\(userinfo)@198.51.100.10:8388#HK%20SS"
    }

    private var shadowsocksLegacyLink: String {
        let encoded = Data("aes-256-gcm:demo-pass@198.51.100.11:8388".utf8).base64EncodedString()
        return "ss://\(encoded)#Legacy%20SS"
    }

    private let shadowsocksPlainLink = "ss://chacha20-ietf-poly1305:plain-pass@198.51.100.12:8388#Plain%20SS"

    private var socksBase64Link: String {
        let userinfo = URIParserCore.base64URLString("socks-user:socks-pass")
        return "socks://\(userinfo)@198.51.100.20:1080#Base64%20SOCKS"
    }

    private let socksPlainLink = "socks://socks-user:socks-pass@198.51.100.21:1080#Plain%20SOCKS"
    private let socksNoAuthLink = "socks5://198.51.100.22:1080#No%20Auth%20SOCKS"
    private let socksIPv6Link = "socks://socks-user:socks-pass@[2001:db8::5]:1080#IPv6%20SOCKS"

    func testParsesVMsgShareLinks() throws {
        let parser = URIParserCore.shared
        let modern = try parser.parseLink(vmessLink, groupID: "manual")
        XCTAssertEqual(modern.proto, .vmess)
        XCTAssertEqual(modern.server, "192.0.2.11")
        XCTAssertEqual(modern.port, 443)
        XCTAssertEqual(modern.name, "Tokyo VMess")
        XCTAssertEqual(modern.uuid, "8f1c0f0e-2a3b-4c5d-9e6f-1a2b3c4d5e6f")
        XCTAssertEqual(modern.vmessSecurity, "auto")
        XCTAssertEqual(modern.network, .ws)
        XCTAssertEqual(modern.security, .tls)
        XCTAssertEqual(modern.sni, "jp1.example.com")
        XCTAssertEqual(modern.wsHost, "jp1.example.com")
        XCTAssertEqual(modern.wsPath, "/ray")
        XCTAssertEqual(modern.fingerprint, "chrome")
        XCTAssertFalse(modern.rawURI.isEmpty)

        let legacy = try parser.parseLink(legacyVMessLink, groupID: "manual")
        XCTAssertEqual(legacy.name, "Legacy VMess")
        XCTAssertEqual(legacy.server, "198.51.100.99")
        XCTAssertEqual(legacy.port, 8443)
        XCTAssertEqual(legacy.network, .grpc)
        XCTAssertEqual(legacy.grpcService, "legacy-service")
        XCTAssertEqual(legacy.security, .tls)
        XCTAssertEqual(legacy.vmessSecurity, "auto")
    }

    func testParsesVLessShareLinks() throws {
        let parser = URIParserCore.shared
        let reality = try parser.parseLink(vlessRealityLink, groupID: "manual")
        XCTAssertEqual(reality.proto, .vless)
        XCTAssertEqual(reality.name, "Seoul Reality")
        XCTAssertEqual(reality.uuid, "3c1d5e7f-9a2b-4c6d-8e0f-1a3b5c7d9e2f")
        XCTAssertEqual(reality.network, .tcp)
        XCTAssertEqual(reality.security, .reality)
        XCTAssertEqual(reality.sni, "www.example.com")
        XCTAssertEqual(reality.fingerprint, "chrome")
        XCTAssertEqual(reality.realityPublicKey, "jNXHt1o0Yp1lGk2sQz8cVb4eRf6tYu7iOp9aS3dF5gH")
        XCTAssertEqual(reality.realityShortID, "a1b2c3d4")
        XCTAssertEqual(reality.flow, "xtls-rprx-vision")

        let websocket = try parser.parseLink(vlessWebSocketLink, groupID: "manual")
        XCTAssertEqual(websocket.name, "Frankfurt WS")
        XCTAssertEqual(websocket.network, .ws)
        XCTAssertEqual(websocket.security, .tls)
        XCTAssertEqual(websocket.wsPath, "/ws?ed=2048")
        XCTAssertEqual(websocket.wsHost, "cdn.example.com")
    }

    func testParsesTrojanShareLinks() throws {
        let parser = URIParserCore.shared
        let websocket = try parser.parseLink(trojanWebSocketLink, groupID: "manual")
        XCTAssertEqual(websocket.proto, .trojan)
        XCTAssertEqual(websocket.name, "LA Trojan")
        XCTAssertEqual(websocket.password, "demo-pass@word")
        XCTAssertEqual(websocket.network, .ws)
        XCTAssertEqual(websocket.security, .tls)
        XCTAssertEqual(websocket.sni, "t.example.com")
        XCTAssertEqual(websocket.wsPath, "/tr")
        XCTAssertEqual(websocket.wsHost, "t.example.com")

        let tcp = try parser.parseLink(trojanTCPLink, groupID: "manual")
        XCTAssertEqual(tcp.name, "Osaka Trojan")
        XCTAssertEqual(tcp.port, 8443)
        XCTAssertEqual(tcp.password, "simple-pass")
        XCTAssertEqual(tcp.network, .tcp)
        XCTAssertEqual(tcp.security, .tls, "Trojan links without security= are TLS by definition")
    }

    func testParsesShadowsocksShareLinks() throws {
        let parser = URIParserCore.shared
        let sip002 = try parser.parseLink(shadowsocksSIP002Link, groupID: "manual")
        XCTAssertEqual(sip002.proto, .shadowsocks)
        XCTAssertEqual(sip002.name, "HK SS")
        XCTAssertEqual(sip002.server, "198.51.100.10")
        XCTAssertEqual(sip002.port, 8388)
        XCTAssertEqual(sip002.ssMethod, "aes-256-gcm")
        XCTAssertEqual(sip002.password, "demo-pass")

        let legacy = try parser.parseLink(shadowsocksLegacyLink, groupID: "manual")
        XCTAssertEqual(legacy.name, "Legacy SS")
        XCTAssertEqual(legacy.server, "198.51.100.11")
        XCTAssertEqual(legacy.ssMethod, "aes-256-gcm")
        XCTAssertEqual(legacy.password, "demo-pass")

        let plain = try parser.parseLink(shadowsocksPlainLink, groupID: "manual")
        XCTAssertEqual(plain.name, "Plain SS")
        XCTAssertEqual(plain.ssMethod, "chacha20-ietf-poly1305")
        XCTAssertEqual(plain.password, "plain-pass")
    }

    func testEncodeRoundTripsAllProtocols() throws {
        let parser = URIParserCore.shared
        let links = [vmessLink, legacyVMessLink, vlessRealityLink, vlessWebSocketLink,
                     trojanWebSocketLink, trojanTCPLink, shadowsocksSIP002Link,
                     shadowsocksLegacyLink, shadowsocksPlainLink]
        for link in links {
            var profile = try parser.parseLink(link, groupID: "manual")
            profile.rawURI = "" // force a rebuild instead of echoing the original link
            let encoded = parser.encode(profile)
            XCTAssertTrue(encoded.hasPrefix(profile.proto == .shadowsocks ? "ss://" : "\(profile.proto.rawValue)://"),
                          "Unexpected encode output: \(encoded)")
            let reparsed = try parser.parseLink(encoded, groupID: "manual")
            XCTAssertEqual(reparsed.proto, profile.proto)
            XCTAssertEqual(reparsed.name, profile.name)
            XCTAssertEqual(reparsed.server, profile.server)
            XCTAssertEqual(reparsed.port, profile.port)
            XCTAssertEqual(reparsed.uuid, profile.uuid)
            XCTAssertEqual(reparsed.password, profile.password)
            XCTAssertEqual(reparsed.ssMethod, profile.ssMethod)
            XCTAssertEqual(reparsed.network, profile.network)
            XCTAssertEqual(reparsed.security, profile.security)
            XCTAssertEqual(reparsed.sni, profile.sni)
            XCTAssertEqual(reparsed.wsPath, profile.wsPath)
            XCTAssertEqual(reparsed.wsHost, profile.wsHost)
            XCTAssertEqual(reparsed.grpcService, profile.grpcService)
            XCTAssertEqual(reparsed.vmessSecurity, profile.vmessSecurity)
            XCTAssertEqual(reparsed.flow, profile.flow)
        }
    }

    // MARK: - SOCKS5 parsing / encoding

    func testParsesSOCKS5ShareLinks() throws {
        let parser = URIParserCore.shared

        // SIP002-style base64 userinfo.
        let base64 = try parser.parseLink(socksBase64Link, groupID: "manual")
        XCTAssertEqual(base64.proto, .socks)
        XCTAssertEqual(base64.server, "198.51.100.20")
        XCTAssertEqual(base64.port, 1080)
        XCTAssertEqual(base64.name, "Base64 SOCKS")
        XCTAssertEqual(base64.socksUsername, "socks-user")
        XCTAssertEqual(base64.password, "socks-pass")

        // Plain userinfo (percent-decoding applies before the colon split).
        let plain = try parser.parseLink("socks://user%40mail:p%40ss%3Aword@198.51.100.23:1080#Plain",
                                         groupID: "manual")
        XCTAssertEqual(plain.socksUsername, "user@mail")
        XCTAssertEqual(plain.password, "p@ss:word")

        // No authentication, but still a valid node.
        let noAuth = try parser.parseLink(socksNoAuthLink, groupID: "manual")
        XCTAssertEqual(noAuth.proto, .socks)
        XCTAssertEqual(noAuth.server, "198.51.100.22")
        XCTAssertEqual(noAuth.port, 1080)
        XCTAssertEqual(noAuth.socksUsername, "")
        XCTAssertEqual(noAuth.password, "")
        XCTAssertEqual(noAuth.name, "No Auth SOCKS")

        // `socks5://` is an accepted alias.
        let alias = try parser.parseLink("socks5://socks-user:socks-pass@198.51.100.24:1080#Alias",
                                         groupID: "manual")
        XCTAssertEqual(alias.proto, .socks)
        XCTAssertEqual(alias.socksUsername, "socks-user")

        // IPv6 hosts keep the brackets out of the parsed address.
        let ipv6 = try parser.parseLink(socksIPv6Link, groupID: "manual")
        XCTAssertEqual(ipv6.server, "2001:db8::5")

        // Paste import / subscription bodies pick the socks links up too.
        let body = [socksNoAuthLink, vmessLink].joined(separator: "\n")
        XCTAssertEqual(parser.parseSubscriptionBody(body).count, 2)
        let report = parser.parseDetailed(body, groupID: "manual")
        XCTAssertEqual(report.profiles.map(\.proto).sorted { $0.rawValue < $1.rawValue }, [.socks, .vmess])
    }

    func testSOCKS5EncodeRoundTrip() throws {
        let parser = URIParserCore.shared
        // Plain links must be re-encoded into the canonical base64 userinfo form.
        for link in [socksBase64Link, socksPlainLink, socksNoAuthLink, socksIPv6Link] {
            var profile = try parser.parseLink(link, groupID: "manual")
            profile.rawURI = ""
            let encoded = parser.encode(profile)
            XCTAssertTrue(encoded.hasPrefix("socks://"), "Unexpected SOCKS encode output: \(encoded)")
            if profile.socksUsername.isEmpty {
                XCTAssertFalse(encoded.contains("@"), "No-auth SOCKS links must not carry a userinfo: \(encoded)")
            } else {
                let userinfo = String(encoded.dropFirst("socks://".count).prefix { $0 != "@" })
                let decoded = String(data: URIParserCore.base64Data(userinfo) ?? Data(), encoding: .utf8)
                XCTAssertEqual(decoded, "\(profile.socksUsername):\(profile.password)")
            }
            let reparsed = try parser.parseLink(encoded, groupID: "manual")
            XCTAssertEqual(reparsed.proto, .socks)
            XCTAssertEqual(reparsed.server, profile.server)
            XCTAssertEqual(reparsed.port, profile.port)
            XCTAssertEqual(reparsed.name, profile.name)
            XCTAssertEqual(reparsed.socksUsername, profile.socksUsername)
            XCTAssertEqual(reparsed.password, profile.password)
        }

        // A freshly built profile encodes to a canonical link as well.
        var profile = NodeProfile(id: "socks-1", groupID: "manual", name: "Built SOCKS",
                                  proto: .socks, server: "203.0.113.30", port: 1080)
        profile.socksUsername = "alice"
        profile.password = "s3cret"
        let encoded = parser.encode(profile)
        XCTAssertTrue(encoded.hasPrefix("socks://"))
        let reparsed = try parser.parseLink(encoded, groupID: "manual")
        XCTAssertEqual(reparsed.socksUsername, "alice")
        XCTAssertEqual(reparsed.password, "s3cret")
        XCTAssertEqual(reparsed.name, "Built SOCKS")
    }

    func testSOCKS5InvalidLinksThrowAndWarn() {
        let parser = URIParserCore.shared
        // Username without a password (and not valid base64) is not a usable link.
        XCTAssertThrowsError(try parser.parseLink("socks://user-only@192.0.2.1:1080", groupID: "manual"))
        // Half-filled credential pairs are rejected like the config builder does.
        XCTAssertThrowsError(try parser.parseLink("socks://user:@192.0.2.1:1080", groupID: "manual")) { error in
            XCTAssertEqual(error as? URIParseError, .malformed("error.uri.malformed.socksCredentials"))
        }
        // Port is mandatory.
        XCTAssertThrowsError(try parser.parseLink("socks://192.0.2.1", groupID: "manual"))
        // No auth is allowed.
        XCTAssertNoThrow(try parser.parseLink("socks://192.0.2.1:1080", groupID: "manual"))

        // Unknown query parameters are reported as warnings but do not block import.
        let report = parser.parseDetailed("socks://192.0.2.1:1080?udp=1&foo=bar#Warn", groupID: "manual")
        XCTAssertEqual(report.profiles.count, 1)
        XCTAssertEqual(report.warnings.count, 1)
        XCTAssertEqual(report.warnings.first?.parameters, ["foo", "udp"])
    }

    func testSOCKS5DuplicateDetection() throws {
        let parser = URIParserCore.shared
        let first = try parser.parseLink("socks://user:pass@192.0.2.1:1080", groupID: "manual")
        let same = try parser.parseLink("socks://user:pass@192.0.2.1:1080#Renamed", groupID: "manual")
        let differentUser = try parser.parseLink("socks://other:pass@192.0.2.1:1080", groupID: "manual")
        let differentPassword = try parser.parseLink("socks://user:other@192.0.2.1:1080", groupID: "manual")
        let noAuth = try parser.parseLink("socks://192.0.2.1:1080", groupID: "manual")
        let noAuthSame = try parser.parseLink("socks://192.0.2.1:1080#Other name", groupID: "manual")

        XCTAssertTrue(URIParserCore.isDuplicate(first, of: same))
        XCTAssertFalse(URIParserCore.isDuplicate(first, of: differentUser))
        XCTAssertFalse(URIParserCore.isDuplicate(first, of: differentPassword))
        XCTAssertTrue(URIParserCore.isDuplicate(noAuth, of: noAuthSame))
        XCTAssertFalse(URIParserCore.isDuplicate(first, of: noAuth))
    }

    func testSOCKS5ProfileRoundTripThroughDatabase() throws {
        let fixture = try makeDatabase()
        let store = ProfileStore(db: fixture.db)
        _ = try store.ensureManualGroup()
        var profile = makeEvidenceProfile(proto: .socks)
        profile.socksUsername = "db-user"
        profile.password = "db-pass"
        profile.uuid = ""
        profile.network = .tcp
        profile.security = .none
        try store.upsert(profile: profile)

        let reloaded = try XCTUnwrap(try store.profile(id: profile.id))
        XCTAssertEqual(reloaded.proto, .socks)
        XCTAssertEqual(reloaded.socksUsername, "db-user")
        XCTAssertEqual(reloaded.password, "db-pass")
        XCTAssertNil(try store.findDuplicate(of: reloaded),
                     "The same id must not count as its own duplicate")
    }

    func testInvalidLinksThrowTypedErrors() {
        let parser = URIParserCore.shared
        XCTAssertThrowsError(try parser.parseLink("https://example.com", groupID: "manual")) { error in
            XCTAssertEqual(error as? URIParseError, .unsupportedScheme)
        }
        XCTAssertThrowsError(try parser.parseLink("vmess://not-base64!!!", groupID: "manual"))
        XCTAssertThrowsError(try parser.parseLink("vless://@192.0.2.1:443?security=tls", groupID: "manual"))
        XCTAssertThrowsError(try parser.parseLink("vless://3c1d5e7f-9a2b-4c6d-8e0f-1a3b5c7d9e2f@host:99999", groupID: "manual"))
        XCTAssertThrowsError(try parser.parseLink("trojan://@192.0.2.1:443", groupID: "manual"))
        XCTAssertThrowsError(try parser.parseLink("ss://bad-userinfo@192.0.2.1:8388", groupID: "manual"))
        XCTAssertThrowsError(try parser.parse("garbage that is not a link", groupID: "manual")) { error in
            XCTAssertEqual(error as? URIParseError, .noRecognizedLinks)
        }
    }

    func testParseMultipleLinksAndReportFailures() throws {
        let parser = URIParserCore.shared
        let text = [vmessLink, vlessWebSocketLink, "https://example.com/not-a-share-link", trojanTCPLink]
            .joined(separator: "\n")
        let report = parser.parseDetailed(text, groupID: "manual")
        XCTAssertEqual(report.profiles.count, 3)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertEqual(report.profiles.map(\.proto).sorted { $0.rawValue < $1.rawValue },
                       [.trojan, .vless, .vmess])

        let profiles = try parser.parse(text, groupID: "manual")
        XCTAssertEqual(profiles.count, 3)
        XCTAssertTrue(profiles.allSatisfy { $0.groupID == "manual" })
    }

    // MARK: - B6 subscription body parsing

    func testSubscriptionBodyBase64StandardAndURLSafe() throws {
        let parser = URIParserCore.shared
        let plain = [vmessLink, vlessWebSocketLink, trojanTCPLink, shadowsocksSIP002Link].joined(separator: "\n")
        XCTAssertEqual(parser.parseSubscriptionBody(plain).count, 4)

        let standard = Data(plain.utf8).base64EncodedString()
        XCTAssertEqual(parser.parseSubscriptionBody(standard).count, 4)

        let urlSafe = standard
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(parser.parseSubscriptionBody(urlSafe).count, 4)

        // A body wrapped in whitespace lines (common in panel output).
        let wrapped = "\n\n  \(urlSafe)\n\n"
        XCTAssertEqual(parser.parseSubscriptionBody(wrapped).count, 4)

        XCTAssertTrue(parser.parseSubscriptionBody("just some text").isEmpty)
    }

    func testSubscriptionUserInfoParsing() throws {
        let info = SubscriptionService.parseUserInfo(
            "upload=1024; download=2048; total=1048576; expire=1700000000; profile-update-interval=12"
        )
        XCTAssertEqual(info.upload, 1024)
        XCTAssertEqual(info.download, 2048)
        XCTAssertEqual(info.total, 1_048_576)
        XCTAssertEqual(info.expireAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(info.profileUpdateInterval, 12 * 3_600)

        let millis = SubscriptionService.parseUserInfo("expire=1700000000000")
        XCTAssertEqual(millis.expireAt, Date(timeIntervalSince1970: 1_700_000_000))

        let base64Header = Data("upload=1; download=2; total=3; expire=1700000000".utf8).base64EncodedString()
        let decoded = SubscriptionService.parseUserInfo(base64Header)
        XCTAssertEqual(decoded.upload, 1)
        XCTAssertEqual(decoded.total, 3)

        XCTAssertEqual(SubscriptionService.parseUserInfo(nil), SubscriptionUserInfo())
    }

    // MARK: - B6 subscription fetch (mocked transport)

    func testSubscriptionFetchWithMockedTransport() async throws {
        let plain = [vmessLink, vlessWebSocketLink].joined(separator: "\n")
        let body = Data(plain.utf8).base64EncodedString()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), SubscriptionService.userAgent)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: [
                                               "Content-Type": "text/plain",
                                               "Subscription-Userinfo": "upload=100; download=200; total=1000; expire=1700000000"
                                           ])!
            return (response, Data(body.utf8))
        }
        addTeardownBlock { MockURLProtocol.handler = nil }

        let service = SubscriptionService(session: makeMockSession())
        let result = try await service.fetch(url: "https://sub.example.com/link", groupID: "group-1", name: "Airport")
        XCTAssertEqual(result.nodes.count, 2)
        XCTAssertTrue(result.nodes.allSatisfy { $0.groupID == "group-1" })
        XCTAssertEqual(result.trafficUpload, 100)
        XCTAssertEqual(result.trafficDownload, 200)
        XCTAssertEqual(result.trafficTotal, 1000)
        XCTAssertEqual(result.expireAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(result.userInfoSummary.total, 1000)
    }

    func testSubscriptionFetchErrorsAreClassified() async throws {
        let service = SubscriptionService(session: makeMockSession())

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: "HTTP/1.1",
                                           headerFields: nil)!
            return (response, Data())
        }
        await assertSubscriptionError(service, expected: .httpStatus(404))

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: nil)!
            return (response, Data("there are no nodes here".utf8))
        }
        await assertSubscriptionError(service, expected: .emptySubscription)
        addTeardownBlock { MockURLProtocol.handler = nil }

        await assertSubscriptionError(service, expected: .invalidURL, url: "not a url")
        await assertSubscriptionError(service, expected: .invalidURL, url: "ftp://example.com/sub")
    }

    private func assertSubscriptionError(_ service: SubscriptionService, expected: SubscriptionError,
                                         url: String = "https://sub.example.com/link",
                                         file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await service.fetch(url: url, groupID: "g", name: "n")
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? SubscriptionError, expected, file: file, line: line)
        }
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    // MARK: - B8 country list metadata (GeoIP pipeline, see GeoIPTests)

    func testCountryDirectoryLoadsBundledDataset() throws {
        let bundleMetadataURL = try XCTUnwrap(
            Bundle.main.url(forResource: CountryDirectory.resourceName,
                            withExtension: CountryDirectory.resourceExtension))
        let directory = CountryDirectory(metadataURL: bundleMetadataURL)
        XCTAssertGreaterThanOrEqual(directory.countries.count, 240,
                                    "The bundled dataset must cover 240+ countries/territories")
        XCTAssertGreaterThan(directory.totalCIDRCount, 1_000_000)
        XCTAssertFalse(directory.datasetSource.isEmpty)
        XCTAssertEqual(directory.datasetDataVersion?.count, 12)
        XCTAssertEqual(directory.isUsingDownloadedSnapshot, false)

        for code in ["CN", "JP", "US", "DE", "GB", "SG", "HK"] {
            XCTAssertGreaterThan(directory.cidrCount(for: code), 0, "\(code) must have prefixes")
            XCTAssertEqual(directory.cidrCount(for: code), directory.country(code: code)?.cidrCount)
        }

        XCTAssertTrue(directory.searchCountries("jap").contains { $0.code == "JP" },
                      "Search must match English names regardless of the device language")
        XCTAssertEqual(directory.country(code: "JP")?.englishName, "Japan")
        XCTAssertEqual(directory.country(code: "cn")?.code, "CN")
        XCTAssertEqual(CountryInfo(code: "JP", name: "Japan", cidrCount: 1).flag, "🇯🇵")
        XCTAssertFalse(directory.countries.contains { GeoIPMetadataStore.nonCountryCodes.contains($0.code) },
                       "PRIVATE/TEST/ZZ are not countries")
    }

    func testGeoIPAssetsAreCompact() throws {
        let datasetURL = try XCTUnwrap(
            Bundle.main.url(forResource: GeoIPAssetManager.bundleResourceName,
                            withExtension: GeoIPAssetManager.bundleResourceExtension))
        let datasetSize = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: datasetURL.path)[.size] as? Int)
        XCTAssertLessThan(datasetSize, 6 * 1024 * 1024,
                          "geoip.dat.gz must stay below 6 MB (the plain dataset is ~24 MB)")

        let metadataURL = try XCTUnwrap(
            Bundle.main.url(forResource: CountryDirectory.resourceName,
                            withExtension: CountryDirectory.resourceExtension))
        let metadataSize = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: metadataURL.path)[.size] as? Int)
        XCTAssertLessThan(metadataSize, 64 * 1024, "geoip_countries.json must stay a few KB")
    }

    // MARK: - B10 demo data

    func testDemoSeedIsIdempotentAndUsesTestNetAddresses() throws {
        let fixture = try makeDatabase()
        let store = ProfileStore(db: fixture.db)
        let subscriptionStore = SubscriptionStore(db: fixture.db)
        DemoSeed.seedIfNeeded(db: fixture.db)
        DemoSeed.seedIfNeeded(store: store)

        let profiles = try store.profiles()
        XCTAssertEqual(profiles.count, DemoSeed.demoNodeCount)
        XCTAssertEqual(try store.count(), DemoSeed.demoNodeCount)
        XCTAssertEqual(try store.groups().count, 2)
        XCTAssertEqual(try subscriptionStore.count(), 1)

        // The model gained SOCKS5 support; the demo seed still ships the four
        // original protocols (a socks demo entry is optional and owned by the shared
        // data layer), so assert coverage of those rather than "every allCases".
        let originalProtocols: Set<ProxyProtocol> = [.vmess, .vless, .trojan, .shadowsocks]
        let protocols = Set(profiles.map(\.proto))
        XCTAssertTrue(protocols.isSuperset(of: originalProtocols),
                      "Demo data must cover the original four protocols, got \(protocols)")
        XCTAssertTrue(protocols.subtracting(originalProtocols).isSubset(of: [.socks]),
                      "Only SOCKS5 may be added on top of the original four, got \(protocols)")

        let manual = profiles.filter { $0.groupID == ProfileStore.manualGroupID }
        let airport = profiles.filter { $0.groupID == DemoSeed.subscriptionGroupID }
        XCTAssertEqual(manual.count, 4)
        XCTAssertEqual(airport.count, 5)
        XCTAssertTrue(profiles.allSatisfy {
            $0.server.hasPrefix("192.0.2.") || $0.server.hasPrefix("198.51.100.")
        }, "Demo nodes must use TEST-NET addresses")
        XCTAssertTrue(profiles.compactMap(\.latencyMs).count >= 7, "Most demo nodes ship a latency")
        XCTAssertTrue(profiles.contains { $0.latencyMs == nil }, "One node demonstrates the timed-out state")
        XCTAssertTrue(profiles.allSatisfy { !$0.rawURI.isEmpty })

        let vmess = try XCTUnwrap(profiles.first { $0.proto == .vmess })
        XCTAssertFalse(vmess.vmessSecurity.isEmpty)

        let subscription = try XCTUnwrap(try subscriptionStore.all().first)
        XCTAssertEqual(subscription.name, DemoSeed.subscriptionGroupName)
        XCTAssertEqual(subscription.autoUpdateInterval, 86_400)
        XCTAssertNotNil(subscription.trafficTotal)
        XCTAssertNotNil(subscription.expireAt)

        let group = try XCTUnwrap(try store.group(id: DemoSeed.subscriptionGroupID))
        XCTAssertEqual(group.kind, .subscription)
        XCTAssertEqual(group.subscriptionID, subscription.id)

        // Every demo node must round trip through the share-link parser (QR share).
        for profile in profiles {
            let reparsed = try URIParserCore.shared.parseLink(profile.rawURI, groupID: profile.groupID)
            XCTAssertEqual(reparsed.proto, profile.proto)
            XCTAssertEqual(reparsed.server, profile.server)
            XCTAssertEqual(reparsed.port, profile.port)
        }
    }

    func testDemoSeedDoesNotOverwriteExistingData() throws {
        let fixture = try makeDatabase()
        let store = ProfileStore(db: fixture.db)
        let group = try store.ensureManualGroup()
        try store.upsert(profile: makeEvidenceProfile(groupID: group.id))
        DemoSeed.seedIfNeeded(db: fixture.db)
        XCTAssertEqual(try store.count(), 1, "Demo data must never replace user data")
    }

    // MARK: - B7 latency tester

    func testLatencyTesterMeasuresReachablePort() async throws {
        #if os(macOS)
        // The macOS test host runs inside the App Sandbox without the
        // network.server entitlement, so a loopback NWListener cannot bind here.
        // The same path is covered by the iOS test target.
        throw XCTSkip("macOS sandbox test host cannot bind a loopback listener")
        #endif
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "listener ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { connection in connection.cancel() }
        listener.start(queue: .global())
        await fulfillment(of: [ready], timeout: 5)
        defer { listener.cancel() }

        let port = try XCTUnwrap(listener.port?.rawValue)
        let profile = NodeProfile(id: "local", groupID: "manual", name: "Local", proto: .trojan,
                                  server: "127.0.0.1", port: Int(port))
        let latency = await LatencyTester().test(profile: profile, timeout: 3)
        let value = try XCTUnwrap(latency)
        XCTAssertGreaterThanOrEqual(value, 1)
        XCTAssertLessThan(value, 3_000)
    }

    func testLatencyTesterReturnsNilForClosedPort() async {
        let profile = NodeProfile(id: "closed", groupID: "manual", name: "Closed", proto: .trojan,
                                  server: "127.0.0.1", port: 1)
        let latency = await LatencyTester().test(profile: profile, timeout: 1)
        XCTAssertNil(latency)
    }

    func testLatencyTesterCancellationResolvesQuickly() async throws {
        let tester = LatencyTester()
        let profile = NodeProfile(id: "slow", groupID: "manual", name: "Slow", proto: .vmess,
                                  server: "10.255.255.1", port: 65000)
        let task = Task { await tester.test(profile: profile, timeout: 30) }
        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        let started = Date()
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "Cancellation must not wait for the timeout")
    }

    func testLatencyTesterBatchWritesResultsBack() async throws {
        let fixture = try makeDatabase()
        let store = ProfileStore(db: fixture.db)
        let group = try store.ensureManualGroup()
        let profiles = (0..<3).map { index -> NodeProfile in
            NodeProfile(id: "batch-\(index)", groupID: group.id, name: "Batch \(index)", proto: .trojan,
                        server: "127.0.0.1", port: 1)
        }
        try store.upsert(profiles: profiles)
        let results = await LatencyTester().testAndStore(profiles: profiles, store: store, timeout: 1)
        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.values.allSatisfy { $0 == nil }, "127.0.0.1:1 is closed")
        for profile in profiles {
            XCTAssertNotNil(try store.profile(id: profile.id)?.latencyAt,
                            "A failed probe still records latency_at for the row state")
        }
    }
}

// MARK: - Mock URL protocol

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
