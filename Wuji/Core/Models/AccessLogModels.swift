import Foundation

/// One parsed Xray access-log line: a connection accepted by the tun inbound and the
/// outbound tag chosen by routing (`proxy` / `direct` / `dns-out`).
/// Shared with the macOS tunnel extension; iOS simply does not use it.
struct AccessLogEntry: Codable, Identifiable, Equatable, Sendable {
    /// Monotonic sequence number assigned inside the tunnel extension.
    var seq: Int
    var timestamp: Date
    /// Domain when DNS correlation is available, otherwise the destination host/IP.
    var host: String
    /// Original destination from the access log, e.g. `74.125.195.100:443`.
    var destination: String
    /// `proxy` / `direct` / `dns` / `other`.
    var route: String
    /// Raw detour tag, e.g. `tun-in -> proxy`.
    var detour: String

    var id: Int { seq }
}

struct AccessLogBatch: Codable, Sendable {
    var entries: [AccessLogEntry]
    /// Sequence number the next request should pass as `after`.
    var next: Int
    /// True when the extension had to drop older entries (1 MB in-memory ring buffer).
    var dropped: Bool
}
