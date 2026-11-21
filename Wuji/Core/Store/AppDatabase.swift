import Foundation
import SQLite3

/// Thin, thread-safe wrapper around a single SQLite connection.
///
/// All public methods are safe to call from any thread and from inside
/// `transaction(_:)`; the connection is serialised through a private queue that
/// re-enters when the caller is already executing on it. WAL mode, foreign keys
/// and a busy timeout are enabled when the database is opened.
final class AppDatabase {
    static let shared = AppDatabase()

    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "com.juejin.ios.wuji.db")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let databaseURL: URL

    /// Whether DEBUG demo data may be seeded into this database. Only the app's
    /// default database location participates; databases created by tests with an
    /// explicit URL are left untouched.
    let allowsDemoSeed: Bool

    init(databaseURL: URL? = nil, allowsDemoSeed: Bool? = nil) {
        if let databaseURL {
            self.databaseURL = databaseURL
        } else if let group = AppGroup.databaseURL {
            self.databaseURL = group
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.databaseURL = support.appendingPathComponent("wuji.sqlite3")
        }
        self.allowsDemoSeed = allowsDemoSeed ?? (databaseURL == nil)
        queue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    /// On-disk location of the database file. Used for sidecar marker files.
    var fileURL: URL { databaseURL }

    // MARK: - Setup

    /// Opens the database if it is not open yet and runs the migrations.
    ///
    /// In DEBUG builds the first successful open also seeds the demo catalogue
    /// (see `DemoSeed`), so the app never needs a separate bootstrap step.
    func openIfNeeded() throws {
        var didOpen = false
        try withoutDeadlock {
            guard handle == nil else { return }
            try openUnsafe()
            didOpen = true
        }
        #if DEBUG
        if didOpen, allowsDemoSeed {
            DemoSeed.seedIfNeeded(db: self)
        }
        #endif
    }

    private func openUnsafe() throws {
        if databaseURL.path != ":memory:" {
            let parent = databaseURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        var db: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &db,
                                     SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite error \(result)"
            if let db { sqlite3_close(db) }
            throw DatabaseError.openFailed(message)
        }
        handle = db
        do {
            try configureUnsafe()
            try migrateUnsafe()
        } catch {
            sqlite3_close(db)
            handle = nil
            throw error
        }
    }

    private func configureUnsafe() throws {
        try executeScriptUnsafe("PRAGMA journal_mode=WAL;")
        try executeScriptUnsafe("PRAGMA synchronous=NORMAL;")
        try executeScriptUnsafe("PRAGMA foreign_keys=ON;")
        try executeScriptUnsafe("PRAGMA busy_timeout=5000;")
    }

    private func migrateUnsafe() throws {
        try executeScriptUnsafe("""
        CREATE TABLE IF NOT EXISTS groups (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          subscription_id TEXT,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        );
        """)
        try executeScriptUnsafe("""
        CREATE TABLE IF NOT EXISTS profiles (
          id TEXT PRIMARY KEY,
          group_id TEXT NOT NULL,
          name TEXT NOT NULL,
          protocol TEXT NOT NULL,
          server TEXT NOT NULL,
          port INTEGER NOT NULL,
          uuid TEXT,
          password TEXT,
          socks_username TEXT,
          ss_method TEXT,
          vmess_security TEXT NOT NULL DEFAULT 'auto',
          alter_id INTEGER NOT NULL DEFAULT 0,
          network TEXT NOT NULL DEFAULT 'tcp',
          tls INTEGER NOT NULL DEFAULT 0,
          security TEXT NOT NULL DEFAULT 'none',
          sni TEXT,
          ws_path TEXT,
          ws_host TEXT,
          grpc_service TEXT,
          fingerprint TEXT,
          allow_insecure INTEGER NOT NULL DEFAULT 0,
          reality_public_key TEXT,
          reality_short_id TEXT,
          flow TEXT,
          raw_uri TEXT,
          latency_ms INTEGER,
          latency_at INTEGER,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          FOREIGN KEY(group_id) REFERENCES groups(id) ON DELETE CASCADE
        );
        """)
        try executeScriptUnsafe("""
        CREATE TABLE IF NOT EXISTS subscriptions (
          id TEXT PRIMARY KEY,
          url TEXT NOT NULL,
          name TEXT NOT NULL,
          auto_update_interval INTEGER,
          last_updated_at INTEGER,
          traffic_upload INTEGER,
          traffic_download INTEGER,
          traffic_total INTEGER,
          expire_at INTEGER,
          last_error TEXT,
          created_at INTEGER NOT NULL
        );
        """)
        try executeScriptUnsafe("""
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        """)

        // Databases created by older builds can miss columns added later; ALTER
        // TABLE keeps user data instead of recreating the schema.
        try ensureColumnUnsafe(table: "profiles", column: "security", definition: "TEXT NOT NULL DEFAULT 'none'")
        for (column, definition) in [
            ("uuid", "TEXT"), ("password", "TEXT"), ("socks_username", "TEXT"), ("ss_method", "TEXT"),
            ("vmess_security", "TEXT NOT NULL DEFAULT 'auto'"),
            ("alter_id", "INTEGER NOT NULL DEFAULT 0"), ("network", "TEXT NOT NULL DEFAULT 'tcp'"),
            ("tls", "INTEGER NOT NULL DEFAULT 0"), ("sni", "TEXT"), ("ws_path", "TEXT"),
            ("ws_host", "TEXT"), ("grpc_service", "TEXT"), ("fingerprint", "TEXT"),
            ("allow_insecure", "INTEGER NOT NULL DEFAULT 0"), ("reality_public_key", "TEXT"),
            ("reality_short_id", "TEXT"), ("flow", "TEXT"), ("raw_uri", "TEXT"),
            ("latency_ms", "INTEGER"), ("latency_at", "INTEGER"),
            ("sort_order", "INTEGER NOT NULL DEFAULT 0"),
            ("created_at", "INTEGER NOT NULL DEFAULT 0"),
            ("updated_at", "INTEGER NOT NULL DEFAULT 0")
        ] {
            try ensureColumnUnsafe(table: "profiles", column: column, definition: definition)
        }
        try ensureColumnUnsafe(table: "groups", column: "subscription_id", definition: "TEXT")
        try ensureColumnUnsafe(table: "groups", column: "sort_order", definition: "INTEGER NOT NULL DEFAULT 0")
        try ensureColumnUnsafe(table: "groups", column: "created_at", definition: "INTEGER NOT NULL DEFAULT 0")

        try executeScriptUnsafe("""
        CREATE INDEX IF NOT EXISTS idx_profiles_group_id ON profiles(group_id);
        CREATE INDEX IF NOT EXISTS idx_profiles_sort ON profiles(sort_order, created_at);
        CREATE INDEX IF NOT EXISTS idx_groups_subscription_id ON groups(subscription_id);
        CREATE INDEX IF NOT EXISTS idx_subscriptions_updated ON subscriptions(last_updated_at);
        """)
        try executeScriptUnsafe("PRAGMA user_version=1;")
    }

    private func ensureColumnUnsafe(table: String, column: String, definition: String) throws {
        let columns = try queryUnsafe("PRAGMA table_info(\(table));")
        let names = Set(columns.compactMap { $0["name"] as? String })
        guard !names.contains(column) else { return }
        try executeScriptUnsafe("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
    }

    // MARK: - Execution helpers

    /// Executes one or more `;`-separated statements and returns the number of
    /// rows changed by the last statement. Bindings only apply to single statements.
    @discardableResult
    func execute(_ sql: String, _ binds: [Any?] = []) throws -> Int {
        try openIfNeeded()
        return try withoutDeadlock { try executeScriptUnsafe(sql, binds) }
    }

    /// Runs a `SELECT` (or any statement producing rows) and returns the rows as
    /// dictionaries keyed by column name. SQLite `NULL` values are omitted.
    func query(_ sql: String, _ binds: [Any?] = []) throws -> [[String: Any]] {
        try openIfNeeded()
        return try withoutDeadlock { try queryUnsafe(sql, binds) }
    }

    /// Runs `work` inside a single write transaction. Calls to `execute`/`query`
    /// on the same instance from inside the closure join the transaction.
    func transaction(_ work: () throws -> Void) throws {
        try openIfNeeded()
        try withoutDeadlock {
            try executeScriptUnsafe("BEGIN IMMEDIATE;")
            do {
                try work()
                try executeScriptUnsafe("COMMIT;")
            } catch {
                _ = try? executeScriptUnsafe("ROLLBACK;")
                throw error
            }
        }
    }

    /// Removes every row from every table (settings, nodes, groups, subscriptions).
    func deleteAllData() throws {
        try transaction {
            try executeScriptUnsafe("DELETE FROM profiles;")
            try executeScriptUnsafe("DELETE FROM groups;")
            try executeScriptUnsafe("DELETE FROM subscriptions;")
            try executeScriptUnsafe("DELETE FROM settings;")
        }
    }

    func close() {
        withoutDeadlock {
            if let handle { sqlite3_close(handle) }
            handle = nil
        }
    }

    // MARK: - Unsafe primitives (call on the database queue)

    @discardableResult
    private func executeScriptUnsafe(_ sql: String, _ binds: [Any?] = []) throws -> Int {
        var changed = 0
        return try sql.withCString { pointer in
            var cursor: UnsafePointer<CChar>? = pointer
            var statements = 0
            while let current = cursor, current.pointee != 0 {
                if statements > 0, !binds.isEmpty {
                    throw DatabaseError.prepareFailed("Bindings are only supported for single-statement SQL.")
                }
                var statement: OpaquePointer?
                let result = sqlite3_prepare_v2(handle, current, -1, &statement, &cursor)
                guard result == SQLITE_OK else { throw DatabaseError.prepareFailed(lastErrorMessage) }
                guard let statement else { continue }
                defer { sqlite3_finalize(statement) }
                try bind(statement, binds)
                while true {
                    let step = sqlite3_step(statement)
                    if step == SQLITE_DONE { break }
                    if step == SQLITE_ROW { continue }
                    throw DatabaseError.stepFailed(lastErrorMessage)
                }
                changed += Int(sqlite3_changes(handle))
                statements += 1
            }
            return changed
        }
    }

    private func queryUnsafe(_ sql: String, _ binds: [Any?] = []) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }
        try bind(statement, binds)
        var rows: [[String: Any]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw DatabaseError.stepFailed(lastErrorMessage) }
            var row: [String: Any] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    row[name] = Int(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(statement, index)
                case SQLITE_NULL:
                    row[name] = nil
                default:
                    if let text = sqlite3_column_text(statement, index) {
                        row[name] = String(cString: text)
                    }
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func bind(_ statement: OpaquePointer?, _ binds: [Any?]) throws {
        for (offset, value) in binds.enumerated() {
            let index = Int32(offset + 1)
            // Call sites pass values like `profile.latencyMs as Any`; unwrap nested
            // Optional<Wrapped> stored inside Any before binding, otherwise a nil
            // optional would be stored as the literal string "Optional(nil)".
            var value = value
            if let wrapped = value {
                let mirror = Mirror(reflecting: wrapped)
                if mirror.displayStyle == .optional {
                    value = mirror.children.first?.value
                }
            }
            switch value {
            case nil:
                sqlite3_bind_null(statement, index)
            case let value as String:
                sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case let value as Int:
                sqlite3_bind_int64(statement, index, Int64(value))
            case let value as Int64:
                sqlite3_bind_int64(statement, index, value)
            case let value as Double:
                sqlite3_bind_double(statement, index, value)
            case let value as Bool:
                sqlite3_bind_int(statement, index, value ? 1 : 0)
            case let value as Date:
                sqlite3_bind_int64(statement, index, Int64(value.timeIntervalSince1970))
            default:
                sqlite3_bind_text(statement, index, String(describing: value), -1, SQLITE_TRANSIENT)
            }
        }
    }

    private var lastErrorMessage: String {
        guard let handle, let message = sqlite3_errmsg(handle) else { return "unknown sqlite error" }
        return String(cString: message)
    }

    /// Runs the block on the database queue, or inline when it is already running
    /// there. The second case keeps `transaction(_:)` closures able to call the
    /// public `execute`/`query` helpers without deadlocking.
    private func withoutDeadlock<T>(_ block: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try block()
        }
        return try queue.sync(execute: block)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DatabaseError: LocalizedError, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "Database open failed: \(message)"
        case .prepareFailed(let message): return "Database prepare failed: \(message)"
        case .stepFailed(let message): return "Database step failed: \(message)"
        }
    }
}
