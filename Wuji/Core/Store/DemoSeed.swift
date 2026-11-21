import Foundation

/// Seeds the DEBUG-only demo catalogue (spec §4.4, docs/impl-plan.md B10).
///
/// Nine nodes in two groups — the manual group and a demo subscription group —
/// using TEST-NET addresses (`192.0.2.0/24`, `198.51.100.0/24`) so they can never
/// reach a real host. Release builds never seed anything.
///
/// Seeding is idempotent: a small sidecar marker file next to the database records
/// that it already happened, so clearing the data in Settings does not resurrect the
/// demo nodes and repeated `AppState.reload()` calls are free.
enum DemoSeed {
    static let subscriptionGroupID = "demo-group-airport"
    static let subscriptionGroupName = "Airport"
    static let demoSubscriptionID = "demo-subscription-airport"
    static let demoNodeCount = 9

    private static let markerExtension = "demo-seeded"

    /// Seeds the demo catalogue into `db` once. Safe to call from every reload.
    static func seedIfNeeded(db: AppDatabase) {
        #if DEBUG
        let markerURL = db.fileURL.appendingPathExtension(markerExtension)
        if FileManager.default.fileExists(atPath: markerURL.path) { return }
        do {
            if try isEmpty(db: db) {
                try insertDemoData(db: db)
            }
            writeMarker(at: markerURL)
        } catch {
            // Demo data is a convenience for screenshots and UI work; a failed
            // seed must never prevent the app (or a test) from starting.
        }
        #endif
    }

    /// Compatibility entry point used by `AppState.reload()`.
    static func seedIfNeeded(store: ProfileStore) {
        seedIfNeeded(db: store.database)
    }

    /// Inserts the demo catalogue when the database has no user data.
    /// Returns `true` when rows were inserted.
    @discardableResult
    static func insertDemoDataIfEmpty(db: AppDatabase, now: Date = Date()) throws -> Bool {
        guard try isEmpty(db: db) else { return false }
        try insertDemoData(db: db, now: now)
        return true
    }

    private static func isEmpty(db: AppDatabase) throws -> Bool {
        // The manual group may already have been created by the caller
        // (`AppState.reload()`), so only real content counts: nodes or subscriptions.
        let rows = try db.query("""
        SELECT (SELECT COUNT(*) FROM profiles) AS profiles,
               (SELECT COUNT(*) FROM subscriptions) AS subscriptions;
        """)
        let row = rows.first ?? [:]
        return (row["profiles"] as? Int ?? 0) == 0 && (row["subscriptions"] as? Int ?? 0) == 0
    }

    private static func insertDemoData(db: AppDatabase, now: Date = Date()) throws {
        let profiles = makeProfiles(now: now)
        let subscription = makeSubscription(now: now)
        let profileStore = ProfileStore(db: db)
        let subscriptionStore = SubscriptionStore(db: db)

        try db.transaction {
            try profileStore.ensureManualGroup()
            try profileStore.upsert(group: NodeGroup(
                id: subscriptionGroupID,
                name: subscriptionGroupName,
                kind: .subscription,
                subscriptionID: demoSubscriptionID,
                sortOrder: 1
            ))
            try subscriptionStore.upsert(subscription)
            for profile in profiles {
                try profileStore.upsert(profile: profile)
            }
        }
    }

    private static func writeMarker(at url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? Data("1".utf8).write(to: url, options: .atomic)
    }

    // MARK: - Demo data

    private static func makeProfiles(now: Date) -> [NodeProfile] {
        let testedAt = now.addingTimeInterval(-600)
        var manual = [NodeProfile]()
        var airport = [NodeProfile]()

        func node(id: String, groupID: String, name: String, proto: ProxyProtocol,
                  server: String, port: Int, sortOrder: Int) -> NodeProfile {
            NodeProfile(id: id, groupID: groupID, name: name, proto: proto, server: server, port: port,
                        sortOrder: sortOrder,
                        createdAt: now.addingTimeInterval(-Double(3600 * (10 - sortOrder))),
                        updatedAt: now.addingTimeInterval(-Double(600)))
        }

        var vmess = node(id: "demo-node-01", groupID: ProfileStore.manualGroupID, name: "Tokyo Edge 01",
                         proto: .vmess, server: "192.0.2.11", port: 443, sortOrder: 0)
        vmess.uuid = "8f1c0f0e-2a3b-4c5d-9e6f-1a2b3c4d5e6f"
        vmess.vmessSecurity = "auto"
        vmess.alterID = 0
        vmess.network = .ws
        vmess.security = .tls
        vmess.sni = "jp1.wuji-demo.example"
        vmess.wsHost = "jp1.wuji-demo.example"
        vmess.wsPath = "/ray"
        vmess.fingerprint = "chrome"
        vmess.latencyMs = 42
        vmess.latencyAt = testedAt
        manual.append(vmess)

        var reality = node(id: "demo-node-02", groupID: ProfileStore.manualGroupID, name: "Seoul Edge 02",
                           proto: .vless, server: "192.0.2.12", port: 443, sortOrder: 1)
        reality.uuid = "3c1d5e7f-9a2b-4c6d-8e0f-1a3b5c7d9e2f"
        reality.network = .tcp
        reality.security = .reality
        reality.sni = "www.wuji-demo.example"
        reality.fingerprint = "chrome"
        reality.realityPublicKey = "jNXHt1o0Yp1lGk2sQz8cVb4eRf6tYu7iOp9aS3dF5gH"
        reality.realityShortID = "a1b2c3d4"
        reality.flow = "xtls-rprx-vision"
        reality.latencyMs = 88
        reality.latencyAt = testedAt
        manual.append(reality)

        var trojan = node(id: "demo-node-03", groupID: ProfileStore.manualGroupID, name: "Osaka Edge 03",
                          proto: .trojan, server: "192.0.2.13", port: 8443, sortOrder: 2)
        trojan.password = "demo-trojan-01"
        trojan.network = .ws
        trojan.security = .tls
        trojan.sni = "osaka.wuji-demo.example"
        trojan.wsHost = "osaka.wuji-demo.example"
        trojan.wsPath = "/tr"
        trojan.latencyMs = 120
        trojan.latencyAt = testedAt
        manual.append(trojan)

        var shadowsocks = node(id: "demo-node-04", groupID: ProfileStore.manualGroupID, name: "Taipei Edge 04",
                               proto: .shadowsocks, server: "192.0.2.14", port: 8388, sortOrder: 3)
        shadowsocks.ssMethod = "chacha20-ietf-poly1305"
        shadowsocks.password = "demo-ss-pass-01"
        shadowsocks.latencyMs = 210
        shadowsocks.latencyAt = testedAt
        manual.append(shadowsocks)

        var singapore = node(id: "demo-node-05", groupID: subscriptionGroupID, name: "Singapore 01",
                             proto: .vmess, server: "198.51.100.21", port: 443, sortOrder: 0)
        singapore.uuid = "5a4b3c2d-1e0f-4a9b-8c7d-6e5f4a3b2c1d"
        singapore.vmessSecurity = "auto"
        singapore.network = .ws
        singapore.security = .tls
        singapore.sni = "sg1.wuji-demo.example"
        singapore.wsHost = "sg1.wuji-demo.example"
        singapore.wsPath = "/vmess"
        singapore.latencyMs = 63
        singapore.latencyAt = testedAt
        airport.append(singapore)

        var frankfurt = node(id: "demo-node-06", groupID: subscriptionGroupID, name: "Frankfurt 01",
                             proto: .vless, server: "198.51.100.22", port: 443, sortOrder: 1)
        frankfurt.uuid = "7d6e5f4a-3b2c-4d1e-9f8a-7b6c5d4e3f2a"
        frankfurt.network = .tcp
        frankfurt.security = .reality
        frankfurt.sni = "www.wuji-demo.example"
        frankfurt.fingerprint = "chrome"
        frankfurt.realityPublicKey = "qP5rT8vW2xY6zA9bC3dE7fG1hJ4kL8mN2oQ6sU0wZ9aB"
        frankfurt.realityShortID = "7f3a9c1e"
        frankfurt.flow = "xtls-rprx-vision"
        frankfurt.latencyMs = 141
        frankfurt.latencyAt = testedAt
        airport.append(frankfurt)

        var losAngeles = node(id: "demo-node-07", groupID: subscriptionGroupID, name: "Los Angeles 01",
                              proto: .trojan, server: "198.51.100.23", port: 443, sortOrder: 2)
        losAngeles.password = "demo-trojan-02"
        losAngeles.network = .ws
        losAngeles.security = .tls
        losAngeles.sni = "la1.wuji-demo.example"
        losAngeles.wsHost = "la1.wuji-demo.example"
        losAngeles.wsPath = "/trojan"
        losAngeles.latencyMs = 265
        losAngeles.latencyAt = testedAt
        airport.append(losAngeles)

        var hongKong = node(id: "demo-node-08", groupID: subscriptionGroupID, name: "Hong Kong 01",
                            proto: .shadowsocks, server: "198.51.100.24", port: 8388, sortOrder: 3)
        hongKong.ssMethod = "aes-256-gcm"
        hongKong.password = "demo-ss-pass-02"
        hongKong.latencyMs = nil // demonstrates the "timed out" row state
        hongKong.latencyAt = nil
        airport.append(hongKong)

        var sydney = node(id: "demo-node-09", groupID: subscriptionGroupID, name: "Sydney 01",
                          proto: .vless, server: "198.51.100.25", port: 443, sortOrder: 4)
        sydney.uuid = "2b3c4d5e-6f7a-4b9c-8d1e-3f5a7b9c1d2e"
        sydney.network = .ws
        sydney.security = .tls
        sydney.sni = "syd1.wuji-demo.example"
        sydney.wsHost = "syd1.wuji-demo.example"
        sydney.wsPath = "/ws"
        sydney.fingerprint = "chrome"
        sydney.latencyMs = 355
        sydney.latencyAt = testedAt
        airport.append(sydney)

        let all = manual + airport
        // Demo nodes ship a working share link so "copy URI" and QR sharing are
        // demonstrable without a real server.
        return all.map { profile in
            var profile = profile
            profile.rawURI = URIParserCore.shared.encode(profile)
            return profile
        }
    }

    private static func makeSubscription(now: Date) -> Subscription {
        let gib: Int64 = 1024 * 1024 * 1024
        return Subscription(
            id: demoSubscriptionID,
            url: "https://demo.invalid/wuji/airport",
            name: subscriptionGroupName,
            autoUpdateInterval: 86_400,
            lastUpdatedAt: now.addingTimeInterval(-3_600),
            trafficUpload: 3 * gib + gib / 5,
            trafficDownload: 20 * gib + 2 * gib / 5,
            trafficTotal: 100 * gib,
            expireAt: now.addingTimeInterval(45 * 86_400),
            lastError: nil,
            createdAt: now.addingTimeInterval(-7 * 86_400)
        )
    }
}
