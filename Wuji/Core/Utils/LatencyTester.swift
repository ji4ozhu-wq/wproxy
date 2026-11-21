import Foundation
import Network

/// Measures TCP handshake latency to a node's server:port (direct, outside the tunnel).
/// Owned by the data role; see docs/impl-plan.md (B7).
///
/// A test succeeds when the TCP three-way handshake completes, which is what the
/// user cares about ("can I reach this server"). Timeouts and failures resolve to
/// `nil`; results can be written straight back to `ProfileStore`.
final class LatencyTester: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.juejin.ios.wuji.latency", attributes: .concurrent)
    private let stateLock = NSLock()
    private var generation = 0
    private var probes: [UUID: Probe] = [:]

    /// Timeout used by the app when the user has not overridden it (spec §4.2).
    static let defaultTimeout: TimeInterval = 5
    /// Maximum number of simultaneous probes (spec §4.3).
    static let defaultConcurrency = 8

    init() {}

    // MARK: - Single node

    /// Measures the TCP handshake latency of one node. Returns milliseconds, or
    /// `nil` on timeout/failure/cancellation.
    func test(profile: NodeProfile, timeout: TimeInterval = LatencyTester.defaultTimeout) async -> Int? {
        guard !profile.server.isEmpty,
              (1...65535).contains(profile.port),
              let port = NWEndpoint.Port(rawValue: UInt16(profile.port)) else {
            return nil
        }
        let started = DispatchTime.now()
        let expectedGeneration = currentGeneration()

        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
                let probe = Probe(continuation: continuation)
                stateLock.lock()
                guard generation == expectedGeneration else {
                    stateLock.unlock()
                    probe.finish(nil)
                    return
                }
                probes[probe.id] = probe
                stateLock.unlock()

                let connection = NWConnection(host: NWEndpoint.Host(profile.server), port: port, using: .tcp)
                probe.attach(connection)
                connection.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        let elapsed = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
                        let milliseconds = max(1, Int(elapsed / 1_000_000))
                        self?.finish(probe, with: milliseconds)
                    case .failed, .cancelled:
                        self?.finish(probe, with: nil)
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                let deadline = max(0.1, timeout)
                queue.asyncAfter(deadline: .now() + deadline) { [weak self] in
                    self?.finish(probe, with: nil)
                }
            }
        }, onCancel: {
            self.cancelAll()
        })
    }


    // MARK: - HTTP latency (through the active tunnel)

    /// Measures HTTP(S) round-trip latency to `urlString` using the system network.
    /// When the VPN tunnel is connected this request goes through the tunnel, so the
    /// result reflects the real proxy path (used for the active node's latency).
    /// - Returns: milliseconds, or `nil` on invalid URL / timeout / failure.
    func testHTTP(urlString: String, timeout: TimeInterval = LatencyTester.defaultTimeout) async -> Int? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        let boundedTimeout = max(0.5, timeout)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = boundedTimeout
        configuration.timeoutIntervalForResource = max(1, boundedTimeout)
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        // HEAD first; some servers reject it, so fall back to a 1-byte ranged GET.
        if let latency = await measureHTTPLatency(session: session, url: url, method: "HEAD") {
            return latency
        }
        return await measureHTTPLatency(session: session, url: url, method: "GET")
    }

    private func measureHTTPLatency(session: URLSession, url: URL, method: String) async -> Int? {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if method == "GET" {
            request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        }
        request.setValue("Wuji/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let start = DispatchTime.now()
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (400..<600).contains(http.statusCode) {
                return nil
            }
            let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            return max(1, Int(elapsed / 1_000_000))
        } catch {
            return nil
        }
    }

    // MARK: - Batch

    /// Tests every profile with at most `concurrency` probes in flight.
    /// Invokes `onResult` as each result arrives.
    func testAll(profiles: [NodeProfile], timeout: TimeInterval,
                 concurrency: Int = LatencyTester.defaultConcurrency,
                 onResult: @escaping (String, Int?) -> Void) async {
        _ = await run(profiles: profiles, timeout: timeout, concurrency: concurrency,
                      onProgress: onResult, store: nil)
    }

    /// Tests every profile and returns `[profileID: latency]`.
    @discardableResult
    func testAll(profiles: [NodeProfile], timeout: TimeInterval,
                 concurrency: Int = LatencyTester.defaultConcurrency) async -> [String: Int?] {
        await run(profiles: profiles, timeout: timeout, concurrency: concurrency,
                  onProgress: nil, store: nil)
    }

    /// Tests every profile and writes each result back to the database as it
    /// arrives (only changed latencies are written). Returns all results.
    @discardableResult
    func testAndStore(profiles: [NodeProfile], store: ProfileStore, timeout: TimeInterval,
                      concurrency: Int = LatencyTester.defaultConcurrency,
                      onResult: ((String, Int?) -> Void)? = nil) async -> [String: Int?] {
        await run(profiles: profiles, timeout: timeout, concurrency: concurrency,
                  onProgress: onResult, store: store)
    }

    /// Cancels every in-flight probe; pending tests resolve to `nil`.
    func cancelAll() {
        let active: [Probe]
        stateLock.lock()
        generation &+= 1
        active = Array(probes.values)
        probes.removeAll()
        stateLock.unlock()
        for probe in active {
            probe.finish(nil)
        }
    }

    private func currentGeneration() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generation
    }

    // MARK: - Internals

    private func run(profiles: [NodeProfile], timeout: TimeInterval, concurrency: Int,
                     onProgress: ((String, Int?) -> Void)?, store: ProfileStore?) async -> [String: Int?] {
        guard !profiles.isEmpty else { return [:] }
        let limit = max(1, min(concurrency, profiles.count))
        var results: [String: Int?] = [:]

        await withTaskGroup(of: (String, Int?).self) { group in
            var iterator = profiles.makeIterator()
            for _ in 0..<limit {
                guard let profile = iterator.next() else { break }
                group.addTask { [weak self] in
                    let value = await self?.test(profile: profile, timeout: timeout)
                    return (profile.id, value)
                }
            }
            for await (id, value) in group {
                results[id] = value
                onProgress?(id, value)
                if let store {
                    try? store.updateLatency(profileID: id, latencyMs: value)
                }
                if let profile = iterator.next() {
                    group.addTask { [weak self] in
                        let value = await self?.test(profile: profile, timeout: timeout)
                        return (profile.id, value)
                    }
                }
            }
        }
        return results
    }

    private func finish(_ probe: Probe, with value: Int?) {
        stateLock.lock()
        probes[probe.id] = nil
        stateLock.unlock()
        probe.finish(value)
    }

    /// Guards a single checked continuation so it resumes exactly once and the
    /// underlying `NWConnection` is always cancelled.
    private final class Probe: @unchecked Sendable {
        let id = UUID()
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Int?, Never>?
        private var connection: NWConnection?

        init(continuation: CheckedContinuation<Int?, Never>) {
            self.continuation = continuation
        }

        func attach(_ connection: NWConnection) {
            lock.lock()
            guard continuation != nil else {
                lock.unlock()
                connection.cancel()
                return
            }
            self.connection = connection
            lock.unlock()
        }

        func finish(_ value: Int?) {
            lock.lock()
            let continuation = self.continuation
            let connection = self.connection
            self.continuation = nil
            self.connection = nil
            lock.unlock()
            connection?.cancel()
            continuation?.resume(returning: value)
        }
    }
}
