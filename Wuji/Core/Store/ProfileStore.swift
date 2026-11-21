import Foundation

/// CRUD access to node groups (`groups`) and nodes (`profiles`).
/// Owned by the data role; see docs/impl-plan.md (B1/B2).
final class ProfileStore {
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    /// Database backing this store (used by `DemoSeed`).
    var database: AppDatabase { db }

    /// ID of the always-present manual group.
    static let manualGroupID = "manual"

    // MARK: - Groups

    /// Returns the manual group, creating it on first use.
    @discardableResult
    func ensureManualGroup() throws -> NodeGroup {
        if let existing = try groups().first(where: { $0.id == Self.manualGroupID }) {
            return existing
        }
        let group = NodeGroup(id: Self.manualGroupID, name: "Manual", kind: .manual, subscriptionID: nil, sortOrder: 0)
        try upsert(group: group)
        return group
    }

    func groups() throws -> [NodeGroup] {
        let rows = try db.query("SELECT * FROM groups ORDER BY sort_order ASC, created_at ASC;")
        return rows.compactMap(Self.group(from:))
    }

    func group(id: String) throws -> NodeGroup? {
        try db.query("SELECT * FROM groups WHERE id = ? LIMIT 1;", [id]).first.flatMap(Self.group(from:))
    }

    func group(forSubscription subscriptionID: String) throws -> NodeGroup? {
        try db.query("SELECT * FROM groups WHERE subscription_id = ? ORDER BY sort_order ASC LIMIT 1;",
                     [subscriptionID]).first.flatMap(Self.group(from:))
    }

    func upsert(group: NodeGroup) throws {
        try db.execute("""
        INSERT INTO groups (id, name, type, subscription_id, sort_order, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET name=excluded.name, type=excluded.type,
          subscription_id=excluded.subscription_id, sort_order=excluded.sort_order;
        """, [group.id, group.name, group.kind.rawValue, group.subscriptionID, group.sortOrder, Date()])
    }

    func delete(groupID: String) throws {
        try db.execute("DELETE FROM groups WHERE id = ?;", [groupID])
    }

    func nextGroupSortOrder() throws -> Int {
        let rows = try db.query("SELECT COALESCE(MAX(sort_order), 0) AS max_order FROM groups;")
        return (rows.first?["max_order"] as? Int ?? 0) + 1
    }

    // MARK: - Profiles

    func profiles() throws -> [NodeProfile] {
        let rows = try db.query("SELECT * FROM profiles ORDER BY sort_order ASC, created_at ASC;")
        return rows.compactMap(Self.profile(from:))
    }

    func profiles(inGroup groupID: String) throws -> [NodeProfile] {
        let rows = try db.query("SELECT * FROM profiles WHERE group_id = ? ORDER BY sort_order ASC, created_at ASC;",
                                [groupID])
        return rows.compactMap(Self.profile(from:))
    }

    func profile(id: String) throws -> NodeProfile? {
        let rows = try db.query("SELECT * FROM profiles WHERE id = ? LIMIT 1;", [id])
        return rows.first.flatMap(Self.profile(from:))
    }

    func count() throws -> Int {
        let rows = try db.query("SELECT COUNT(*) AS count FROM profiles;")
        return rows.first?["count"] as? Int ?? 0
    }

    func upsert(profile: NodeProfile) throws {
        var profile = profile
        profile.updatedAt = Date()
        try db.execute(Self.upsertSQL, Self.upsertBinds(profile))
    }

    /// Inserts or updates several profiles atomically.
    func upsert(profiles: [NodeProfile]) throws {
        guard !profiles.isEmpty else { return }
        try db.transaction {
            for profile in profiles {
                try db.execute(Self.upsertSQL, Self.upsertBinds(profile))
            }
        }
    }

    /// Replaces every node of a group in one transaction (used when a
    /// subscription refresh succeeds; the old nodes stay until then).
    func replaceProfiles(inGroup groupID: String, with profiles: [NodeProfile]) throws {
        try db.transaction {
            try db.execute("DELETE FROM profiles WHERE group_id = ?;", [groupID])
            for profile in profiles {
                var profile = profile
                profile.groupID = groupID
                try db.execute(Self.upsertSQL, Self.upsertBinds(profile))
            }
        }
    }

    func delete(profileID: String) throws {
        try db.execute("DELETE FROM profiles WHERE id = ?;", [profileID])
    }

    func deleteProfiles(inGroup groupID: String) throws {
        try db.execute("DELETE FROM profiles WHERE group_id = ?;", [groupID])
    }

    /// Deletes a subscription and its group/nodes in one transaction.
    func delete(subscriptionID: String) throws {
        try db.transaction {
            try db.execute("DELETE FROM groups WHERE subscription_id = ?;", [subscriptionID])
            try db.execute("DELETE FROM subscriptions WHERE id = ?;", [subscriptionID])
        }
    }

    func nextSortOrder(inGroup groupID: String) throws -> Int {
        let rows = try db.query("SELECT COALESCE(MAX(sort_order), -1) AS max_order FROM profiles WHERE group_id = ?;",
                                [groupID])
        return (rows.first?["max_order"] as? Int ?? -1) + 1
    }

    func updateLatency(profileID: String, latencyMs: Int?) throws {
        try db.execute("UPDATE profiles SET latency_ms = ?, latency_at = ? WHERE id = ?;",
                       [latencyMs as Any, Date(), profileID])
    }

    /// Writes back the results of a latency test run in one transaction.
    func updateLatencies(_ results: [String: Int?], at date: Date = Date()) throws {
        guard !results.isEmpty else { return }
        try db.transaction {
            for (profileID, latency) in results {
                try db.execute("UPDATE profiles SET latency_ms = ?, latency_at = ? WHERE id = ?;",
                               [latency as Any, date, profileID])
            }
        }
    }

    /// Checks whether the same connection already exists (the manual form uses
    /// this to block duplicate nodes). The profile's own ID is ignored.
    func findDuplicate(of profile: NodeProfile) throws -> NodeProfile? {
        let rows = try db.query("""
        SELECT * FROM profiles WHERE protocol = ? AND server = ? AND port = ? AND id <> ?;
        """, [profile.proto.rawValue, profile.server, profile.port, profile.id])
        let candidates = rows.compactMap(Self.profile(from:))
        return candidates.first { candidate in
            switch profile.proto {
            case .vmess, .vless:
                return candidate.uuid.caseInsensitiveCompare(profile.uuid) == .orderedSame
            case .trojan:
                return candidate.password == profile.password
            case .shadowsocks:
                return candidate.password == profile.password && candidate.ssMethod == profile.ssMethod
            case .socks:
                return candidate.socksUsername == profile.socksUsername && candidate.password == profile.password
            }
        }
    }

    func setActiveProfile(id: String?) throws {
        try SettingsStore(db: db).update { settings in
            settings.activeProfileID = id
        }
    }

    // MARK: - Row mapping

    static func group(from row: [String: Any]) -> NodeGroup? {
        guard let id = row["id"] as? String else { return nil }
        return NodeGroup(
            id: id,
            name: row["name"] as? String ?? "",
            kind: GroupKind(rawValue: row["type"] as? String ?? "manual") ?? .manual,
            subscriptionID: row["subscription_id"] as? String,
            sortOrder: row["sort_order"] as? Int ?? 0
        )
    }

    static func profile(from row: [String: Any]) -> NodeProfile? {
        guard let id = row["id"] as? String,
              let protoRaw = row["protocol"] as? String,
              let proto = ProxyProtocol(rawValue: protoRaw) else { return nil }
        return NodeProfile(
            id: id,
            groupID: row["group_id"] as? String ?? ProfileStore.manualGroupID,
            name: row["name"] as? String ?? "",
            proto: proto,
            server: row["server"] as? String ?? "",
            port: row["port"] as? Int ?? 0,
            uuid: row["uuid"] as? String ?? "",
            password: row["password"] as? String ?? "",
            socksUsername: row["socks_username"] as? String ?? "",
            ssMethod: row["ss_method"] as? String ?? "",
            vmessSecurity: row["vmess_security"] as? String ?? "auto",
            alterID: row["alter_id"] as? Int ?? 0,
            network: Transport(rawValue: row["network"] as? String ?? "tcp") ?? .tcp,
            security: SecurityLayer(rawValue: row["security"] as? String ?? "none") ?? .none,
            sni: row["sni"] as? String ?? "",
            wsPath: row["ws_path"] as? String ?? "",
            wsHost: row["ws_host"] as? String ?? "",
            grpcService: row["grpc_service"] as? String ?? "",
            fingerprint: row["fingerprint"] as? String ?? "",
            allowInsecure: (row["allow_insecure"] as? Int ?? 0) != 0,
            realityPublicKey: row["reality_public_key"] as? String ?? "",
            realityShortID: row["reality_short_id"] as? String ?? "",
            flow: row["flow"] as? String ?? "",
            rawURI: row["raw_uri"] as? String ?? "",
            latencyMs: row["latency_ms"] as? Int,
            latencyAt: (row["latency_at"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) },
            sortOrder: row["sort_order"] as? Int ?? 0,
            createdAt: (row["created_at"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
            updatedAt: (row["updated_at"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        )
    }

    private static let upsertSQL = """
    INSERT INTO profiles (id, group_id, name, protocol, server, port, uuid, password, socks_username, ss_method,
      vmess_security, alter_id, network, tls, security, sni, ws_path, ws_host, grpc_service,
      fingerprint, allow_insecure, reality_public_key, reality_short_id, flow, raw_uri,
      latency_ms, latency_at, sort_order, created_at, updated_at)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ON CONFLICT(id) DO UPDATE SET
      group_id=excluded.group_id, name=excluded.name, protocol=excluded.protocol,
      server=excluded.server, port=excluded.port, uuid=excluded.uuid, password=excluded.password,
      socks_username=excluded.socks_username, ss_method=excluded.ss_method, vmess_security=excluded.vmess_security,
      alter_id=excluded.alter_id, network=excluded.network,
      tls=excluded.tls, security=excluded.security, sni=excluded.sni, ws_path=excluded.ws_path,
      ws_host=excluded.ws_host, grpc_service=excluded.grpc_service, fingerprint=excluded.fingerprint,
      allow_insecure=excluded.allow_insecure, reality_public_key=excluded.reality_public_key,
      reality_short_id=excluded.reality_short_id, flow=excluded.flow, raw_uri=excluded.raw_uri,
      latency_ms=excluded.latency_ms, latency_at=excluded.latency_at, sort_order=excluded.sort_order,
      updated_at=excluded.updated_at;
    """

    private static func upsertBinds(_ profile: NodeProfile) -> [Any?] {
        // `tls` is a legacy mirror of `security` kept for older readers; `security`
        // is the column the data layer and the config builder read.
        let tlsFlag = profile.security == .none ? 0 : 1
        return [
            profile.id, profile.groupID, profile.name, profile.proto.rawValue, profile.server, profile.port,
            profile.uuid, profile.password, profile.socksUsername, profile.ssMethod, profile.vmessSecurity, profile.alterID,
            profile.network.rawValue, tlsFlag, profile.security.rawValue, profile.sni, profile.wsPath,
            profile.wsHost, profile.grpcService, profile.fingerprint, profile.allowInsecure ? 1 : 0,
            profile.realityPublicKey, profile.realityShortID, profile.flow, profile.rawURI,
            profile.latencyMs as Any, profile.latencyAt as Any,
            profile.sortOrder, profile.createdAt, profile.updatedAt
        ]
    }
}
