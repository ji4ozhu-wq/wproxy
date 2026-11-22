import Foundation
import NetworkExtension
import os.log

/// Packet Tunnel Provider entry point.
///
/// Responsibilities:
/// 1. read the Xray configuration the app wrote to `active_tunnel.json` (App Group),
/// 2. install the tun network settings (default routes, LAN excludes, DNS, MTU),
/// 3. find the utun fd the system created in this process and inject it into the
///    Xray config root `env["xray.tun.fd"]`,
/// 4. start Xray through libXray and report state/traffic back to the app and to
///    the App Group status files,
/// 5. stop the kernel when the system tears the tunnel down.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    enum ProviderError: LocalizedError {
        case missingLaunchConfiguration
        case invalidLaunchConfiguration
        case tunFileDescriptorNotFound
        case kernelNotRunning

        var errorDescription: String? {
            switch self {
            case .missingLaunchConfiguration:
                return "No tunnel configuration was handed to the extension."
            case .invalidLaunchConfiguration:
                return "The tunnel configuration is unreadable."
            case .tunFileDescriptorNotFound:
                return "The tunnel interface could not be located in the extension process."
            case .kernelNotRunning:
                return "The Xray kernel did not stay running after startup."
            }
        }
    }

    // MARK: - Provider message wire keys (kept in sync with TunnelController.swift)

    private enum ProviderMessage {
        static let type = "type"
        static let traffic = "traffic"
        static let status = "status"
        static let version = "version"
        static let logs = "logs"
        static let clearLogs = "logsClear"
        static let after = "after"
    }

    private struct Snapshot {
        var running = false
        var connectedAt: Date?
        var uplinkBytes: Int64 = 0
        var downlinkBytes: Int64 = 0
        var uplinkRate: Double = 0
        var downlinkRate: Double = 0
        var previousBytes: XrayRunner.TrafficSample?
        var previousSampleAt: Date?
    }

    private static let log = Logger(subsystem: "com.juejin.ios.wuji.tunnel-ext", category: "PacketTunnelProvider")
    /// Background liveness sampling. The app samples traffic on demand through
    /// `handleAppMessage`, so a 1 Hz timer would only waste battery while the app
    /// is not polling.
    private static let trafficSampleInterval: TimeInterval = 10

    private let xrayQueue = DispatchQueue(label: "com.juejin.ios.wuji.tunnel-ext.xray", qos: .userInitiated)
    private let stateLock = NSLock()
    private var snapshot = Snapshot()
    private var trafficTimer: DispatchSourceTimer?
    private let completionLock = NSLock()
    private var startCompleted = false
    #if os(macOS)
    /// In-memory-only tail of the Xray access log (max 1 MB) served to the app.
    private var accessLogRelay: AccessLogRelay?
    #endif

    // MARK: - Tunnel lifecycle

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        resetSnapshot()
        guard let launch = loadLaunchConfiguration() else {
            completeStart(error: ProviderError.missingLaunchConfiguration, completionHandler: completionHandler)
            return
        }
        let host = serverHost
        Self.log.info("Starting tunnel for \(host, privacy: .private)")

        xrayQueue.async { [weak self] in
            guard let self else { return }
            let excludedAddresses = TunnelNetworkSettingsFactory.resolveIPv4Addresses(for: host)
            let settings = TunnelNetworkSettingsFactory.make(serverHost: host,
                                                             excludedServerAddresses: excludedAddresses,
                                                             bypassLAN: launch.bypassLAN)
            // NEPacketTunnelProvider APIs are safest from the main thread; the
            // blocking Go/Xray work below stays on xrayQueue.
            DispatchQueue.main.async {
                self.setTunnelNetworkSettings(settings) { error in
                    if let error {
                        Self.log.error("setTunnelNetworkSettings failed: \(error.localizedDescription, privacy: .public)")
                        self.completeStart(error: error, completionHandler: completionHandler)
                        return
                    }
                    self.xrayQueue.async {
                        self.startKernel(launch: launch, completionHandler: completionHandler)
                    }
                }
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        Self.log.info("Stopping tunnel, reason \(reason.rawValue, privacy: .public)")
        xrayQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completionHandler() }
                return
            }
            self.stopTrafficTimer()
            #if os(macOS)
            self.accessLogRelay?.stop()
            self.accessLogRelay = nil
            #endif
            XrayRunner.stop()
            self.updateSnapshot {
                $0.running = false
                $0.previousBytes = nil
                $0.previousSampleAt = nil
            }
            self.writeStatus(state: "disconnected", message: Self.stopReasonDescription(reason))
            DispatchQueue.main.async { completionHandler() }
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        xrayQueue.async { [weak self] in
            self?.stopTrafficTimer()
            completionHandler()
        }
    }

    override func wake() {
        xrayQueue.async { [weak self] in
            guard let self, self.readSnapshot().running else { return }
            self.startTrafficTimer()
        }
    }

    // MARK: - Kernel startup

    private func startKernel(launch: TunnelLaunchConfig, completionHandler: @escaping (Error?) -> Void) {
        guard let descriptor = TunFdResolver.utunFileDescriptor(
            expectedInterfaceAddress: TunnelNetworkSettingsFactory.ipv4Address
        ) else {
            completeStart(error: ProviderError.tunFileDescriptorNotFound, completionHandler: completionHandler)
            return
        }
        #if os(macOS)
        // Start a fresh in-memory-only access log relay and point Xray at its temp file.
        let relay = AccessLogRelay()
        relay?.start()
        accessLogRelay = relay
        let configJSON = Self.injectAccessLog(into: launch.xrayJSON, filePath: relay?.filePath)
        #else
        let configJSON = launch.xrayJSON
        #endif
        do {
            try XrayRunner.run(configJSON: configJSON, tunFileDescriptor: descriptor)
        } catch {
            Self.log.error("runXray failed: \(error.localizedDescription, privacy: .public)")
            completeStart(error: error, completionHandler: completionHandler)
            return
        }
        guard XrayRunner.isRunning() else {
            completeStart(error: ProviderError.kernelNotRunning, completionHandler: completionHandler)
            return
        }
        let version = XrayRunner.version() ?? "unknown"
        Self.log.info("Xray \(version, privacy: .public) running on utun fd \(descriptor)")
        RouteDiagnostics.write(context: "started fd=\(descriptor) xray=\(version)")
        updateSnapshot {
            $0.running = true
            $0.connectedAt = Date()
            $0.uplinkBytes = 0
            $0.downlinkBytes = 0
            $0.uplinkRate = 0
            $0.downlinkRate = 0
            $0.previousBytes = nil
            $0.previousSampleAt = nil
        }
        writeStatus(state: "connected")
        writeTraffic(currentStats())
        startTrafficTimer()
        completeStart(error: nil, completionHandler: completionHandler)
    }

    private func completeStart(error: Error?, completionHandler: @escaping (Error?) -> Void) {
        completionLock.lock()
        let alreadyCompleted = startCompleted
        startCompleted = true
        completionLock.unlock()
        guard !alreadyCompleted else { return }
        if let error {
            writeStatus(state: "error", message: error.localizedDescription)
            Self.log.error("Tunnel start failed: \(error.localizedDescription, privacy: .public)")
        }
        DispatchQueue.main.async { completionHandler(error) }
    }

    // MARK: - Traffic sampling

    private func startTrafficTimer() {
        stopTrafficTimer()
        let timer = DispatchSource.makeTimerSource(queue: xrayQueue)
        timer.schedule(deadline: .now() + Self.trafficSampleInterval,
                       repeating: .seconds(Int(Self.trafficSampleInterval)),
                       leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.sampleTraffic()
        }
        timer.resume()
        trafficTimer = timer
    }

    private func stopTrafficTimer() {
        trafficTimer?.setEventHandler {}
        trafficTimer?.cancel()
        trafficTimer = nil
    }

    private func sampleTraffic(writeFile: Bool = true) {
        do {
            let sample = try XrayRunner.trafficSample()
            let now = Date()
            updateSnapshot { snapshot in
                if let previousBytes = snapshot.previousBytes, let previousAt = snapshot.previousSampleAt {
                    let interval = max(now.timeIntervalSince(previousAt), 0.2)
                    snapshot.uplinkRate = max(0, Double(sample.uplinkBytes - previousBytes.uplinkBytes) / interval)
                    snapshot.downlinkRate = max(0, Double(sample.downlinkBytes - previousBytes.downlinkBytes) / interval)
                }
                snapshot.uplinkBytes = sample.uplinkBytes
                snapshot.downlinkBytes = sample.downlinkBytes
                snapshot.previousBytes = sample
                snapshot.previousSampleAt = now
            }
            if writeFile { writeTraffic(currentStats()) }
        } catch {
            Self.log.error("Traffic sampling failed: \(error.localizedDescription, privacy: .public)")
            guard !XrayRunner.isRunning() else { return }
            // The kernel died underneath us: tear the tunnel down with a reason so
            // the app can surface an error instead of showing a fake "connected".
            stopTrafficTimer()
            updateSnapshot { $0.running = false }
            let failure = XrayRunner.InvocationError.rejected("The Xray kernel stopped unexpectedly.")
            writeStatus(state: "error", message: failure.localizedDescription)
            cancelTunnelWithError(failure)
        }
    }

    /// Injects the extension-only access-log configuration into the Xray JSON:
    /// temp file inside the extension container + DNS log (used to map IPs to domains).
    private static func injectAccessLog(into json: String, filePath: String?) -> String {
        guard let filePath,
              var root = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else {
            return json
        }
        root["log"] = [
            "loglevel": "warning",
            "access": filePath,
            "dnsLog": true
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
              let updated = String(data: data, encoding: .utf8) else {
            return json
        }
        return updated
    }

    private func currentStats() -> TunnelSessionStats {
        let current = readSnapshot()
        var stats = TunnelSessionStats()
        stats.uploadBytes = current.uplinkBytes
        stats.downloadBytes = current.downlinkBytes
        stats.connectedAt = current.connectedAt
        stats.uplinkRate = current.uplinkRate
        stats.downlinkRate = current.downlinkRate
        return stats
    }

    // MARK: - App messages

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        let request = (try? JSONSerialization.jsonObject(with: messageData)) as? [String: Any]
        let type = request?[ProviderMessage.type] as? String
        switch type {
        case ProviderMessage.traffic:
            // Sample on demand so the foreground app gets fresh numbers without the
            // extension running a fast timer of its own.
            sampleTraffic(writeFile: false)
            completionHandler?(try? JSONEncoder().encode(currentStats()))
        case ProviderMessage.status:
            let current = readSnapshot()
            let file = TunnelStatusFile(state: current.running ? "connected" : "disconnected",
                                        message: nil,
                                        updatedAt: Date())
            completionHandler?(try? JSONEncoder().encode(file))
        case ProviderMessage.version:
            let version = XrayRunner.version() ?? ""
            completionHandler?(try? JSONEncoder().encode(["version": version]))
        case ProviderMessage.logs:
            #if os(macOS)
            let after = request?[ProviderMessage.after] as? Int ?? 0
            let batch = accessLogRelay?.snapshot(after: after)
                ?? AccessLogBatch(entries: [], next: 0, dropped: true)
            completionHandler?(try? JSONEncoder().encode(batch))
            #else
            completionHandler?(nil)
            #endif
        case ProviderMessage.clearLogs:
            #if os(macOS)
            accessLogRelay?.clear()
            #endif
            completionHandler?(try? JSONEncoder().encode(["ok": true]))
        default:
            Self.log.error("Unknown provider message")
            completionHandler?(nil)
        }
    }

    // MARK: - App Group files

    private func loadLaunchConfiguration() -> TunnelLaunchConfig? {
        guard let url = AppGroup.activeTunnelURL,
              let data = try? Data(contentsOf: url) else {
            Self.log.error("active_tunnel.json is missing in the App Group container")
            return nil
        }
        do {
            return try JSONDecoder().decode(TunnelLaunchConfig.self, from: data)
        } catch {
            Self.log.error("active_tunnel.json is invalid: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private var serverHost: String {
        if let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol {
            if let configuration = tunnelProtocol.providerConfiguration?[AppGroup.providerConfigurationKey] as? [String: Any],
               let host = configuration["serverHost"] as? String,
               !host.isEmpty {
                return host
            }
            if let address = tunnelProtocol.serverAddress, !address.isEmpty {
                return address
            }
        }
        return "127.0.0.1"
    }

    private func writeStatus(state: String, message: String? = nil) {
        guard let url = AppGroup.tunnelStatusURL else {
            Self.log.error("App Group container is unavailable; cannot write tunnel status")
            return
        }
        let file = TunnelStatusFile(state: state, message: message, updatedAt: Date())
        guard let data = try? JSONEncoder().encode(file) else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Self.log.error("Failed to write tunnel status: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func writeTraffic(_ stats: TunnelSessionStats) {
        guard let url = AppGroup.trafficURL else { return }
        guard let data = try? JSONEncoder().encode(stats) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Snapshot helpers

    private func resetSnapshot() {
        stateLock.lock()
        snapshot = Snapshot()
        stateLock.unlock()
        completionLock.lock()
        startCompleted = false
        completionLock.unlock()
    }

    private func updateSnapshot(_ body: (inout Snapshot) -> Void) {
        stateLock.lock()
        body(&snapshot)
        stateLock.unlock()
    }

    private func readSnapshot() -> Snapshot {
        stateLock.lock()
        defer { stateLock.unlock() }
        return snapshot
    }

    private static func stopReasonDescription(_ reason: NEProviderStopReason) -> String {
        switch reason {
        case .none: return "The tunnel was stopped."
        case .userInitiated: return "The tunnel was disconnected by the user."
        case .providerFailed: return "The tunnel provider failed."
        case .noNetworkAvailable: return "No network is available."
        case .unrecoverableNetworkChange: return "The device changed networks."
        case .providerDisabled: return "The tunnel provider was disabled."
        case .authenticationCanceled: return "The VPN authentication was canceled."
        case .configurationFailed: return "The tunnel configuration was rejected."
        case .idleTimeout: return "The tunnel timed out."
        case .configurationDisabled: return "The tunnel configuration was disabled."
        case .configurationRemoved: return "The tunnel configuration was removed."
        case .superceded: return "The tunnel was replaced by another VPN."
        case .userLogout: return "The user logged out."
        case .userSwitch: return "The device user changed."
        case .connectionFailed: return "The tunnel connection failed."
        case .sleep: return "The device went to sleep."
        case .appUpdate: return "The app was updated."
        case .internalError: return "The Network Extension framework reported an internal error."
        @unknown default: return "The tunnel was stopped (reason \(reason.rawValue))."
        }
    }
}
