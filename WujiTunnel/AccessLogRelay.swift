import Foundation

#if os(macOS)
/// Tails the Xray access log inside the extension's temporary directory and keeps the
/// newest ~1 MB of parsed proxy/direct entries in memory only. Nothing is persisted:
/// the file is deleted when the tunnel stops and the buffer is bounded by `maxBytes`.
final class AccessLogRelay {
    /// In-memory budget requested for the log ring buffer (1 MB).
    static let maxBytes = 1_000_000

    private let queue = DispatchQueue(label: "com.juejin.ios.wuji.access-log-relay")
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?

    private let fileURL: URL
    private var offset: UInt64 = 0
    private var entries: [AccessLogEntry] = []
    private var nextSeq = 1
    private var dropped = false
    private var bytes = 0
    private var ipToDomain: [String: String] = [:]

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()

    init?() {
        let directory = FileManager.default.temporaryDirectory
        fileURL = directory.appendingPathComponent("wuji-access-log-\(UUID().uuidString).log", isDirectory: false)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Absolute path handed to Xray through `log.access`.
    var filePath: String { fileURL.path }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.offset = 0
            self.entries.removeAll()
            self.bytes = 0
            self.nextSeq = 1
            self.dropped = false
            self.ipToDomain.removeAll()
            self.lock.unlock()
            try? FileManager.default.removeItem(at: self.fileURL)

            guard self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 0.8, repeating: 0.8)
            timer.setEventHandler { [weak self] in self?.readNewLines() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            try? FileManager.default.removeItem(at: self.fileURL)
            self.lock.lock()
            self.offset = 0
            self.entries.removeAll()
            self.bytes = 0
            self.dropped = false
            self.lock.unlock()
        }
    }

    func snapshot(after: Int) -> AccessLogBatch {
        lock.lock()
        defer { lock.unlock() }
        let firstSeq = entries.first?.seq ?? nextSeq
        var droppedNow = dropped
        if after < firstSeq - 1 {
            droppedNow = true
        }
        let selected = entries.filter { $0.seq > after }
        return AccessLogBatch(entries: selected, next: nextSeq, dropped: droppedNow)
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        bytes = 0
        dropped = true
        lock.unlock()
    }

    // MARK: - Parsing

    private func readNewLines() {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        lock.lock()
        let currentOffset = offset
        let shouldRead = size > currentOffset
        lock.unlock()
        guard shouldRead else { return }
        try? handle.seek(toOffset: currentOffset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        let text = String(decoding: data, as: UTF8.self)
        lock.lock()
        offset = size
        for line in text.split(whereSeparator: \.isNewline) {
            parse(String(line))
        }
        trimToBudgetLocked()
        lock.unlock()
    }

    private func parse(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        let timestamp = parseTimestamp(line) ?? Date()

        // DNS log: "server got answer: example.com -> [1.2.3.4, 5.6.7.8] 23ms"
        if line.contains(" got answer:") || line.contains(" cache HIT:") || line.contains(" cache OPTIMISTE:") {
            recordDNSMapping(line)
            return
        }

        guard line.contains("accepted") else { return }
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard let acceptedIndex = parts.firstIndex(of: "accepted"), acceptedIndex + 1 < parts.count else { return }
        var destination = String(parts[acceptedIndex + 1])
        if destination.hasPrefix("tcp:") || destination.hasPrefix("udp:") {
            destination = String(destination.dropFirst(4))
        }
        var detour = ""
        if let open = line.firstIndex(of: "["), let close = line.firstIndex(of: "]") {
            detour = String(line[line.index(after: open)..<close])
        }
        let lower = detour.lowercased()
        let route: String
        if lower.contains("dns") {
            route = "dns"
        } else if lower.contains("direct") {
            route = "direct"
        } else if lower.contains("proxy") {
            route = "proxy"
        } else {
            route = "other"
        }
        let host = resolvedHost(for: destination)

        entries.append(AccessLogEntry(seq: nextSeq,
                                      timestamp: timestamp,
                                      host: host,
                                      destination: destination,
                                      route: route,
                                      detour: detour))
        nextSeq += 1
        bytes += line.utf8.count + 48
    }

    private func parseTimestamp(_ line: String) -> Date? {
        guard line.count >= 19 else { return nil }
        return Self.timestampFormatter.date(from: String(line.prefix(19)))
    }

    /// Extracts `ip -> domain` pairs from an Xray DNS log line.
    private func recordDNSMapping(_ line: String) {
        guard let arrowRange = line.range(of: " -> ["),
              let closeIndex = line[arrowRange.upperBound...].firstIndex(of: "]") else { return }
        let leading = line[..<arrowRange.lowerBound]
        let domain = leading.split(separator: " ").last.map(String.init) ?? ""
        guard !domain.isEmpty else { return }
        let ipsPart = line[arrowRange.upperBound..<closeIndex]
        for ip in ipsPart.split(separator: ",") {
            let trimmed = ip.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            ipToDomain[trimmed] = domain
        }
        if ipToDomain.count > 2000 {
            ipToDomain.removeAll()
        }
    }

    private func resolvedHost(for destination: String) -> String {
        // destination is host:port (IPv4). Strip the port and look for a DNS mapping.
        guard let colon = destination.lastIndex(of: ":") else { return destination }
        let hostPart = String(destination[..<colon])
        if let domain = ipToDomain[hostPart], !domain.isEmpty {
            return domain
        }
        return hostPart
    }

    private func trimToBudgetLocked() {
        while bytes > Self.maxBytes, !entries.isEmpty {
            let removed = entries.removeFirst()
            bytes -= (removed.host.utf8.count + removed.destination.utf8.count + removed.detour.utf8.count + 96)
            dropped = true
        }
        if bytes < 0 { bytes = 0 }
    }
}
#endif
