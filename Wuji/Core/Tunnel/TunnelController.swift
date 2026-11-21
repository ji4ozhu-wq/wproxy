import Foundation
import NetworkExtension
import os.log

/// Controls the system VPN tunnel via NETunnelProviderManager.
protocol TunnelControlling: AnyObject {
    var state: TunnelState { get }
    var onStateChange: ((TunnelState) -> Void)? { get set }
    func prepareAndStart(config: TunnelLaunchConfig, serverHost: String) async throws
    func stop() async
    func requestTrafficStats() async -> TunnelSessionStats?
    func resetConfiguration() async throws
}

/// Owns the single `NETunnelProviderManager` configuration of the app.
///
/// The manager is the system-side half of the tunnel: the Xray JSON itself is
/// handed to the extension through the App Group file `active_tunnel.json` written
/// here before every start; `providerConfiguration` only carries routing metadata
/// (server host, config file name).
///
/// All public members are safe to call from any thread; `onStateChange` is always
/// delivered on the main queue.
final class TunnelController: TunnelControlling {
    private static let log = Logger(subsystem: "com.juejin.ios.wuji", category: "TunnelController")

    /// How long to wait for the system to report `.connected` after `startVPNTunnel()`.
    private static let startupTimeout: TimeInterval = 45
    /// How long to wait for the system to report `.disconnected` after a stop.
    private static let shutdownTimeout: TimeInterval = 5
    /// Upper bound for one extension reply. Without this a hung/killed extension
    /// would leave the awaiting task suspended forever (one leaked task per second).
    private static let providerMessageTimeout: TimeInterval = 2

    private struct TrafficSample {
        var stats: TunnelSessionStats
        var at: Date
    }

    private let stateLock = NSLock()
    private var _state: TunnelState = .disconnected
    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var lastTrafficSample: TrafficSample?
    private var connectedAt: Date?

    var onStateChange: ((TunnelState) -> Void)?

    var state: TunnelState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _state
    }

    init() {
        // Restore the system-side status when the app is relaunched while the
        // tunnel is already connected (or was disconnected from Settings).
        Task { await syncSystemState() }
    }

    // MARK: - Start / stop

    func prepareAndStart(config: TunnelLaunchConfig, serverHost: String) async throws {
        Self.log.info("Preparing tunnel for \(serverHost, privacy: .private)")
        setState(.connecting)
        do {
            try writeLaunchConfiguration(config)

            let manager = try await loadOrCreateManager()
            let tunnelProtocol = NETunnelProviderProtocol()
            tunnelProtocol.providerBundleIdentifier = AppGroup.tunnelBundleIdentifier
            tunnelProtocol.serverAddress = serverHost
            tunnelProtocol.providerConfiguration = [
                AppGroup.providerConfigurationKey: [
                    "serverHost": serverHost,
                    "configFile": "active_tunnel.json"
                ]
            ]
            // Let iOS install the tunnel's default route normally. `enforceRoutes`
            // is not used: on iOS 26 it produced a connected tunnel whose DNS was
            // captured while app TCP still bypassed it (routes not scoped to utun).
            // The included/excluded routes below still define what goes in/out.
            if #available(iOS 14.2, *) {
                tunnelProtocol.enforceRoutes = false
            }
            manager.protocolConfiguration = tunnelProtocol
            manager.localizedDescription = "Wuji"
            manager.isEnabled = true
            applyOnDemandRules(mode: config.onDemandMode, to: manager)
            try await save(manager)

            guard let saved = try await reloadManagedManager() else {
                throw TunnelError.missingConfiguration
            }
            setManager(saved)
            installStatusObserver(for: saved)
            try await start(saved)
            try await waitUntilConnected(manager: saved)
            resetTrafficClock()
            Self.log.info("Tunnel connected")
        } catch {
            Self.log.error("Tunnel start failed: \(error.localizedDescription, privacy: .private)")
            let mapped = Self.mapStartError(error)
            setState(.error(mapped.localizedDescription))
            throw mapped
        }
    }

    func stop() async {
        setState(.disconnecting)
        var existing = currentManager()
        if existing == nil {
            existing = try? await reloadManagedManager()
        }
        guard let manager = existing else {
            removeActiveLaunchConfiguration()
            resetTrafficClock()
            setState(.disconnected)
            return
        }
        // A2 (audit): an enabled on-demand rule reconnects the tunnel immediately
        // after a user-initiated disconnect. Turn the rules off and persist that
        // before stopping, otherwise the connection can never be turned off from
        // inside the app while on-demand is active.
        if let manager = await disableOnDemandAndReload(manager) {
            let status = manager.connection.status
            if status == .connected || status == .connecting || status == .reasserting {
                manager.connection.stopVPNTunnel()
                await waitUntilDisconnected(manager: manager)
            }
        }
        // C9 (audit): the launch file carries the node credentials in clear text;
        // it is only needed between the app's start call and the extension's read.
        removeActiveLaunchConfiguration()
        resetTrafficClock()
        setState(.disconnected)
    }

    /// Turns on-demand rules off and persists the change. Returns the reloaded
    /// manager (saving preferences invalidates the previous manager instance) or
    /// `nil` when the configuration disappeared. A failed save is logged and the
    /// existing manager is returned so the stop still proceeds.
    private func disableOnDemandAndReload(_ manager: NETunnelProviderManager) async -> NETunnelProviderManager? {
        guard manager.isOnDemandEnabled else { return manager }
        applyOnDemandRules(mode: .off, to: manager)
        do {
            try await save(manager)
        } catch {
            Self.log.error("Failed to disable on-demand before stopping: \(error.localizedDescription, privacy: .private)")
            return manager
        }
        do {
            guard let reloaded = try await reloadManagedManager() else { return nil }
            setManager(reloaded)
            installStatusObserver(for: reloaded)
            return reloaded
        } catch {
            Self.log.error("Reloading the tunnel configuration failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    // MARK: - Traffic

    func requestTrafficStats() async -> TunnelSessionStats? {
        guard let manager = currentManager() else { return nil }
        guard let session = manager.connection as? NETunnelProviderSession,
              session.status == .connected else { return nil }

        let request = Data(#"{"type":"traffic"}"#.utf8)
        let response: Data? = await withCheckedContinuation { continuation in
            // Guard the continuation: the timeout and the provider callback may race,
            // and a second resume would crash the process.
            let box = ProviderReplyBox(continuation)
            do {
                try session.sendProviderMessage(request) { data in
                    box.finish(data)
                }
            } catch {
                Self.log.error("sendProviderMessage failed: \(error.localizedDescription, privacy: .private)")
                box.finish(nil)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.providerMessageTimeout) {
                box.finish(nil)
            }
        }
        guard let response,
              let stats = try? JSONDecoder().decode(TunnelSessionStats.self, from: response) else {
            return nil
        }
        return recordTrafficSample(stats)
    }

    /// Applies the app-side rate calculation (impl-plan C6: the extension reports
    /// cumulative bytes, the app derives bytes/second between two samples).
    private func recordTrafficSample(_ raw: TunnelSessionStats) -> TunnelSessionStats {
        var stats = raw
        let now = Date()
        stateLock.lock()
        defer { stateLock.unlock() }
        let previous = lastTrafficSample
        if previous == nil {
            connectedAt = connectedAt ?? stats.connectedAt ?? now
        }
        stats.connectedAt = stats.connectedAt ?? connectedAt
        if let previous {
            let interval = max(now.timeIntervalSince(previous.at), 0.2)
            stats.uplinkRate = max(0, Double(stats.uploadBytes - previous.stats.uploadBytes) / interval)
            stats.downlinkRate = max(0, Double(stats.downloadBytes - previous.stats.downloadBytes) / interval)
        } else {
            stats.uplinkRate = 0
            stats.downlinkRate = 0
        }
        lastTrafficSample = TrafficSample(stats: stats, at: now)
        return stats
    }

    // MARK: - System configuration

    func resetConfiguration() async throws {
        Self.log.info("Removing the system VPN configuration")
        do {
            let managers = try await Self.loadAllManagers()
            for manager in managers where Self.isManagedByWuji(manager) {
                if manager.connection.status != .disconnected && manager.connection.status != .invalid {
                    manager.connection.stopVPNTunnel()
                }
                try await remove(manager)
            }
        } catch {
            #if targetEnvironment(simulator)
            // The simulator has no VPN subsystem ("IPC failed"). There is no system
            // configuration to remove there, so the reset is already effective.
            Self.log.info("Skipping VPN configuration removal: the simulator has no NetworkExtension IPC")
            #else
            Self.log.error("Removing the VPN configuration failed: \(error.localizedDescription, privacy: .private)")
            throw Self.mapStartError(error)
            #endif
        }
        removeStatusObserver()
        setManager(nil)
        clearAppGroupFiles()
        resetTrafficClock()
        setState(.disconnected)
    }

    /// Re-reads the system status; call when the app becomes active so a change made
    /// in Settings (or by another VPN app) shows up in the UI.
    func syncSystemState() async {
        do {
            let managers = try await Self.loadAllManagers()
            guard let managed = managers.first(where: Self.isManagedByWuji) else {
                removeStatusObserver()
                setManager(nil)
                setState(.disconnected)
                return
            }
            setManager(managed)
            installStatusObserver(for: managed)
            handleConnectionStatus(managed.connection.status)
            if managed.connection.status == .disconnected,
               let file = readStatusFile(),
               file.state == "error",
               let message = file.message,
               !message.isEmpty {
                setState(.error(message))
            }
        } catch {
            Self.log.error("Reading the system VPN state failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Applies a new on-demand mode to an existing configuration without starting it.
    /// Used by the Settings screen when the user switches the on-demand option while
    /// a tunnel configuration already exists.
    func updateOnDemandMode(_ mode: OnDemandMode) async {
        var existing = currentManager()
        if existing == nil {
            existing = try? await reloadManagedManager()
        }
        guard let manager = existing else { return }
        applyOnDemandRules(mode: mode, to: manager)
        do {
            try await save(manager)
            Self.log.info("On-demand mode updated to \(mode.rawValue, privacy: .public)")
            // Saving preferences invalidates the manager instance; reload it so the
            // status observer and a later stop/start use a live connection object.
            if let reloaded = try await reloadManagedManager() {
                setManager(reloaded)
                installStatusObserver(for: reloaded)
            } else {
                setManager(nil)
                removeStatusObserver()
            }
        } catch {
            Self.log.error("Failed to save the on-demand mode: \(error.localizedDescription, privacy: .private)")
        }
    }

    var isConfigured: Bool {
        currentManager() != nil
    }

    // MARK: - Manager loading

    private static func loadAllManagers() async throws -> [NETunnelProviderManager] {
        try await withCheckedThrowingContinuation { continuation in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: managers ?? [])
                }
            }
        }
    }

    private static func isManagedByWuji(_ manager: NETunnelProviderManager) -> Bool {
        guard let tunnelProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol else {
            return false
        }
        return tunnelProtocol.providerBundleIdentifier == AppGroup.tunnelBundleIdentifier
    }

    private func loadOrCreateManager() async throws -> NETunnelProviderManager {
        let managers = try await Self.loadAllManagers()
        let ours = managers.filter(Self.isManagedByWuji)
        guard let first = ours.first else {
            return NETunnelProviderManager()
        }
        // Keep exactly one Wuji configuration; stale duplicates can keep the
        // system VPN status alive and confuse the status callback.
        for duplicate in ours.dropFirst() {
            try? await remove(duplicate)
        }
        return first
    }

    private func reloadManagedManager() async throws -> NETunnelProviderManager? {
        let managers = try await Self.loadAllManagers()
        return managers.first(where: Self.isManagedByWuji)
    }

    private func save(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func remove(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.removeFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func start(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try manager.connection.startVPNTunnel()
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - On-demand rules

    private func applyOnDemandRules(mode: OnDemandMode, to manager: NETunnelProviderManager) {
        switch mode {
        case .off:
            manager.isOnDemandEnabled = false
            manager.onDemandRules = []
        case .always:
            let connect = NEOnDemandRuleConnect()
            manager.isOnDemandEnabled = true
            manager.onDemandRules = [connect]
        case .wifi:
            let connect = NEOnDemandRuleConnect()
            connect.interfaceTypeMatch = .wiFi
            let disconnect = NEOnDemandRuleDisconnect()
            disconnect.interfaceTypeMatch = .cellular
            manager.isOnDemandEnabled = true
            manager.onDemandRules = [connect, disconnect]
        case .cellular:
            let connect = NEOnDemandRuleConnect()
            connect.interfaceTypeMatch = .cellular
            let disconnect = NEOnDemandRuleDisconnect()
            disconnect.interfaceTypeMatch = .wiFi
            manager.isOnDemandEnabled = true
            manager.onDemandRules = [connect, disconnect]
        }
    }

    // MARK: - Status handling

    private func installStatusObserver(for manager: NETunnelProviderManager) {
        removeStatusObserver()
        let observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self] _ in
            self?.handleConnectionStatus(manager.connection.status)
        }
        statusObserver = observer
    }

    private func removeStatusObserver() {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
        statusObserver = nil
    }

    private func handleConnectionStatus(_ status: NEVPNStatus) {
        switch status {
        case .connected:
            stateLock.lock()
            if connectedAt == nil { connectedAt = Date() }
            stateLock.unlock()
            setState(.connected)
        case .connecting, .reasserting:
            setState(.connecting)
        case .disconnecting:
            setState(.disconnecting)
        case .disconnected, .invalid:
            resetTrafficClock()
            setState(.disconnected)
        @unknown default:
            break
        }
    }

    private func waitUntilConnected(manager: NETunnelProviderManager) async throws {
        let deadline = Date().addingTimeInterval(Self.startupTimeout)
        var sawConnecting = false
        while Date() < deadline {
            let status = manager.connection.status
            switch status {
            case .connected:
                return
            case .connecting, .reasserting:
                sawConnecting = true
            case .disconnected, .invalid:
                if sawConnecting || status == .invalid {
                    throw startupFailure()
                }
            case .disconnecting:
                break
            @unknown default:
                break
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        throw TunnelError.startupTimedOut
    }

    private func waitUntilDisconnected(manager: NETunnelProviderManager) async {
        let deadline = Date().addingTimeInterval(Self.shutdownTimeout)
        while Date() < deadline {
            if manager.connection.status == .disconnected || manager.connection.status == .invalid {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func startupFailure() -> Error {
        if let file = readStatusFile(),
           file.state == "error",
           let message = file.message,
           !message.isEmpty {
            return TunnelError.configurationFailed(message)
        }
        return TunnelError.systemPermissionDenied
    }

    // MARK: - State plumbing

    private func setState(_ newState: TunnelState) {
        stateLock.lock()
        let changed = _state != newState
        _state = newState
        stateLock.unlock()
        guard changed else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(newState)
        }
    }

    private func setManager(_ newManager: NETunnelProviderManager?) {
        stateLock.lock()
        manager = newManager
        stateLock.unlock()
    }

    private func currentManager() -> NETunnelProviderManager? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return manager
    }

    private func resetTrafficClock() {
        stateLock.lock()
        lastTrafficSample = nil
        connectedAt = nil
        stateLock.unlock()
    }

    // MARK: - App Group files

    private func writeLaunchConfiguration(_ config: TunnelLaunchConfig) throws {
        guard let url = AppGroup.activeTunnelURL else {
            throw TunnelError.missingConfiguration
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            // C9 (audit): the file contains the node credentials. Keep it in the
            // App Group container only until the first unlock after a reboot and
            // delete it again as soon as the tunnel stops (see `stop()`).
            try encoder.encode(config).write(
                to: url,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            Self.log.error("Writing active_tunnel.json failed: \(error.localizedDescription, privacy: .private)")
            throw TunnelError.missingConfiguration
        }
    }

    /// Removes the launch configuration handed to the extension (audit C9). Only the
    /// tunnel start reads it, so removing it after a stop or a reset is safe.
    private func removeActiveLaunchConfiguration() {
        guard let url = AppGroup.activeTunnelURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func readStatusFile() -> TunnelStatusFile? {
        guard let url = AppGroup.tunnelStatusURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TunnelStatusFile.self, from: data)
    }

    private func clearAppGroupFiles() {
        let urls = [AppGroup.activeTunnelURL, AppGroup.tunnelStatusURL, AppGroup.trafficURL]
        for url in urls.compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Errors

    private static func mapStartError(_ error: Error) -> Error {
        if let tunnelError = error as? TunnelError {
            return tunnelError
        }
        let nsError = error as NSError
        if nsError.domain == NEVPNErrorDomain,
           nsError.code == NEVPNError.configurationDisabled.rawValue {
            return TunnelError.systemPermissionDenied
        }
        return TunnelError.configurationFailed(nsError.localizedDescription)
    }
}

/// Resume-once wrapper around a checked continuation used for provider messages.
private final class ProviderReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var finished = false

    init(_ continuation: CheckedContinuation<Data?, Never>) {
        self.continuation = continuation
    }

    func finish(_ data: Data?) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: data)
    }
}

enum TunnelError: LocalizedError {
    case notAvailable
    case missingConfiguration
    case systemPermissionDenied
    case configurationFailed(String)
    case startupTimedOut

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return NSLocalizedString("error.tunnel.unavailable", comment: "")
        case .missingConfiguration:
            return NSLocalizedString("error.tunnel.noConfig", comment: "")
        case .systemPermissionDenied:
            return NSLocalizedString("error.tunnel.permission", comment: "")
        case .configurationFailed(let detail):
            // B10: the underlying detail is kept when present (it is the only useful
            // clue for a failed start); an empty detail gets a localized generic text.
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? L10n.t("error.tunnel.failed") : detail
        case .startupTimedOut:
            return L10n.t("error.tunnel.timeout")
        }
    }
}
