import Foundation

/// Persists `AppSettings` as one JSON row in the `settings` table (spec §4.2).
/// Owned by the data role; see docs/impl-plan.md (B3).
final class SettingsStore {
    private let db: AppDatabase

    /// Key of the single JSON row holding `AppSettings`.
    static let settingsKey = "app_settings"

    init(db: AppDatabase) {
        self.db = db
    }

    func load() -> AppSettings {
        guard let rows = try? db.query("SELECT value FROM settings WHERE key = ? LIMIT 1;", [Self.settingsKey]),
              let json = rows.first?["value"] as? String,
              let data = json.data(using: .utf8),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        try db.execute("""
        INSERT INTO settings (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;
        """, [Self.settingsKey, json])
    }

    /// Loads, mutates and saves the settings in one call. Returns the new value.
    @discardableResult
    func update(_ mutate: (inout AppSettings) -> Void) throws -> AppSettings {
        var settings = load()
        mutate(&settings)
        try save(settings)
        return settings
    }

    /// Deletes the persisted settings; `load()` then returns `.default`.
    func reset() throws {
        try db.execute("DELETE FROM settings WHERE key = ?;", [Self.settingsKey])
    }

    // MARK: - Raw key/value access

    func rawValue(forKey key: String) throws -> String? {
        try db.query("SELECT value FROM settings WHERE key = ? LIMIT 1;", [key]).first?["value"] as? String
    }

    func setRawValue(_ value: String?, forKey key: String) throws {
        guard let value else {
            try db.execute("DELETE FROM settings WHERE key = ?;", [key])
            return
        }
        try db.execute("""
        INSERT INTO settings (key, value) VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;
        """, [key, value])
    }
}
