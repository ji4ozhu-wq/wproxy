import Foundation
import Network
import NetworkExtension
import os

/// Requests the two iOS permissions the tunnel needs before the user can connect:
///
/// 1. **Local Network** (iOS 14+): browsing for a Bonjour service is what triggers the
///    system prompt. Denials surface as a `.waiting` browser state.
/// 2. **VPN Configuration** (NetworkExtension): saving the first `NETunnelProviderManager`
///    triggers the system "Allow VPN Configuration" prompt.
///
/// The result is only used to gate first-run onboarding; the real tunnel start still
/// reports its own errors if a permission is revoked later.
@MainActor
final class NetworkPermissionRequester {
    static let shared = NetworkPermissionRequester()
    private static let log = Logger(subsystem: "com.juejin.ios.wuji", category: "permissions")

    private var isRequesting = false

    /// Asks for both permissions. Returns `true` when the app may continue.
    func requestAll() async -> Bool {
        guard !isRequesting else { return false }
        isRequesting = true
        defer { isRequesting = false }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-WujiForcePermissionFailure") {
            return false
        }
        #endif

        #if targetEnvironment(simulator)
        // The simulator has no Local Network prompt and no NetworkExtension backend;
        // simulate a grant so onboarding can be exercised in UI tests/screenshots.
        try? await Task.sleep(nanoseconds: 350_000_000)
        return true
        #else
        guard await requestLocalNetwork() else { return false }
        return await requestVPNConfiguration()
        #endif
    }

    // MARK: - Local network

    private func requestLocalNetwork() async -> Bool {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.juejin.ios.wuji.local-network")
            let browser = NWBrowser(for: .bonjour(type: "_wuji-permission._tcp", domain: nil), using: .tcp)
            let lock = NSLock()
            var finished = false

            func finish(_ granted: Bool) {
                lock.lock()
                let alreadyFinished = finished
                finished = true
                lock.unlock()
                guard !alreadyFinished else { return }
                browser.cancel()
                Self.log.info("Local network permission result: \(granted, privacy: .public)")
                continuation.resume(returning: granted)
            }

            browser.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .failed:
                    finish(false)
                case .waiting:
                    // Denied local-network access leaves the browser waiting.
                    finish(false)
                default:
                    break
                }
            }
            browser.start(queue: queue)
            // If neither prompt nor ready state arrives quickly, assume the permission
            // was already granted earlier (browsing is allowed without a prompt then).
            queue.asyncAfter(deadline: .now() + 8) { finish(true) }
        }
    }

    // MARK: - VPN configuration

    private func requestVPNConfiguration() async -> Bool {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if managers.contains(where: Self.isWujiManager) {
                return true
            }

            let manager = NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = AppGroup.tunnelBundleIdentifier
            proto.serverAddress = "wuji-permission"
            manager.protocolConfiguration = proto
            manager.localizedDescription = "WProxy"
            manager.isEnabled = true
            try await manager.saveToPreferences()

            // Denying the prompt does not always throw; verify by reloading.
            let reloaded = try await NETunnelProviderManager.loadAllFromPreferences()
            return reloaded.contains(where: Self.isWujiManager)
        } catch {
            Self.log.error("VPN configuration permission failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    private static func isWujiManager(_ manager: NETunnelProviderManager) -> Bool {
        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol else { return false }
        return proto.providerBundleIdentifier == AppGroup.tunnelBundleIdentifier
    }
}
