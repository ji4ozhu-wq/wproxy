import Foundation

/// CRUD access to subscription records (`subscriptions` table).
/// Owned by the data role; see docs/impl-plan.md (B4).
final class SubscriptionStore {
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    var database: AppDatabase { db }

    func all() throws -> [Subscription] {
        let rows = try db.query("SELECT * FROM subscriptions ORDER BY created_at ASC;")
        return rows.compactMap(Self.subscription(from:))
    }

    func subscription(id: String) throws -> Subscription? {
        try db.query("SELECT * FROM subscriptions WHERE id = ? LIMIT 1;", [id])
            .first.flatMap(Self.subscription(from:))
    }

    func count() throws -> Int {
        let rows = try db.query("SELECT COUNT(*) AS count FROM subscriptions;")
        return rows.first?["count"] as? Int ?? 0
    }

    func upsert(_ subscription: Subscription) throws {
        try db.execute("""
        INSERT INTO subscriptions (id, url, name, auto_update_interval, last_updated_at, traffic_upload,
          traffic_download, traffic_total, expire_at, last_error, created_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
          url=excluded.url, name=excluded.name, auto_update_interval=excluded.auto_update_interval,
          last_updated_at=excluded.last_updated_at, traffic_upload=excluded.traffic_upload,
          traffic_download=excluded.traffic_download, traffic_total=excluded.traffic_total,
          expire_at=excluded.expire_at, last_error=excluded.last_error;
        """, [
            subscription.id, subscription.url, subscription.name,
            subscription.autoUpdateInterval.map { Int($0) } as Any,
            subscription.lastUpdatedAt as Any,
            subscription.trafficUpload as Any, subscription.trafficDownload as Any,
            subscription.trafficTotal as Any, subscription.expireAt as Any,
            subscription.lastError as Any, subscription.createdAt
        ])
    }

    func delete(_ id: String) throws {
        try db.execute("DELETE FROM subscriptions WHERE id = ?;", [id])
    }

    /// Deletes a subscription together with its group and nodes in one transaction.
    func delete(subscriptionID: String) throws {
        try db.transaction {
            try db.execute("DELETE FROM groups WHERE subscription_id = ?;", [subscriptionID])
            try db.execute("DELETE FROM subscriptions WHERE id = ?;", [subscriptionID])
        }
    }

    /// Subscriptions whose auto-update interval has elapsed.
    func dueForAutoUpdate(globalEnabled: Bool, now: Date = Date()) throws -> [Subscription] {
        guard globalEnabled else { return [] }
        return try all().filter { Self.isDue($0, now: now) }
    }

    /// `true` when the subscription has an interval and the interval has elapsed
    /// since the last refresh (or since creation when never refreshed).
    static func isDue(_ subscription: Subscription, now: Date = Date()) -> Bool {
        guard let interval = subscription.autoUpdateInterval, interval > 0 else { return false }
        let reference = subscription.lastUpdatedAt ?? subscription.createdAt
        return now.timeIntervalSince(reference) >= interval
    }

    /// Records the outcome of a failed refresh while keeping the previous nodes.
    func recordFailure(_ subscription: Subscription, error: String, now: Date = Date()) throws {
        var subscription = subscription
        subscription.lastError = error
        subscription.lastUpdatedAt = now
        try upsert(subscription)
    }

    static func subscription(from row: [String: Any]) -> Subscription? {
        guard let id = row["id"] as? String else { return nil }
        return Subscription(
            id: id,
            url: row["url"] as? String ?? "",
            name: row["name"] as? String ?? "",
            autoUpdateInterval: (row["auto_update_interval"] as? Int).map { TimeInterval($0) },
            lastUpdatedAt: (row["last_updated_at"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) },
            trafficUpload: (row["traffic_upload"] as? Int).map { Int64($0) },
            trafficDownload: (row["traffic_download"] as? Int).map { Int64($0) },
            trafficTotal: (row["traffic_total"] as? Int).map { Int64($0) },
            expireAt: (row["expire_at"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) },
            lastError: row["last_error"] as? String,
            createdAt: (row["created_at"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        )
    }
}
