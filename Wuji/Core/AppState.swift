import Foundation
import Network
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let db: AppDatabase
    let profileStore: ProfileStore
    let subscriptionStore: SubscriptionStore
    let settingsStore: SettingsStore
    let subscriptionService: SubscriptionService
    let latencyTester: LatencyTester
    let countries: CountryDirectory
    let uriParser: URIParser
    let tunnel: TunnelController

    @Published var settings: AppSettings = .default
    @Published var groups: [NodeGroup] = []
    @Published var nodes: [NodeProfile] = []
    @Published var subscriptions: [Subscription] = []
    @Published var tunnelState: TunnelState = .disconnected
    @Published var banner: String?
    /// Global transient confirmation shown by `RootView` (e.g. "Settings applied").
    @Published var toastMessage: String?

    /// Live traffic statistics; only the Home screen observes this object.
    let sessionStatsModel = SessionStatsModel()

    /// Settings the running tunnel was started from. Any later change to the node or
    /// to the routing settings is compared against this snapshot and triggers an
    /// automatic reconnect (user decision for audit B2/G3).
    private struct TunnelSetup: Equatable {
        var activeProfileID: String?
        var routingMode: RoutingMode
        var dnsMode: DNSMode
        var bypassLAN: Bool
        var bypassCountryCodes: [String]

        init(settings: AppSettings) {
            activeProfileID = settings.activeProfileID
            routingMode = settings.routingMode
            dnsMode = settings.dnsMode
            bypassLAN = settings.bypassLAN
            bypassCountryCodes = settings.bypassCountryCodes
        }
    }

    /// Delay before an automatic reconnect runs, so that changing several settings in
    /// a row (e.g. the country multi-select saving once at Done, or a slider) only
    /// restarts the tunnel once.
    private static let autoReconnectDelay: UInt64 = 500_000_000

    private var statsTimer: Timer?
    private var appliedSetup: TunnelSetup?
    /// Setup snapshot independent of the tunnel lifecycle, used to decide whether a
    /// settings edit should show the "settings applied" toast.
    private var lastTunnelSetup: TunnelSetup?
    private var autoReconnectTask: Task<Void, Never>?
    private var isAutoReconnecting = false

    /// Bumped whenever a pending/scheduled automatic reconnect must be abandoned
    /// (manual disconnect, removal, VPN reset). The reconnect task captures the value
    /// before stopping the tunnel and refuses to start a new one when it changed.
    private var autoReconnectEpoch = 0
    private var pendingSettingsAppliedToast = false

    init(db: AppDatabase = .shared) {
        self.db = db
        self.profileStore = ProfileStore(db: db)
        self.subscriptionStore = SubscriptionStore(db: db)
        self.settingsStore = SettingsStore(db: db)
        self.subscriptionService = SubscriptionService()
        self.latencyTester = LatencyTester()
        self.countries = CountryDirectory.shared
        self.uriParser = URIParser()
        self.tunnel = TunnelController()
        self.tunnel.onStateChange = { [weak self] state in
            Task { @MainActor in self?.applyTunnelState(state) }
        }
        // Decode the country routing data off the main thread once at launch so that
        // opening the region picker for the first time doesn't hitch the UI.
        Task.detached(priority: .utility) {
            _ = CountryDirectory.shared.countries
        }
        // First launch after install/update: decompress the bundled geoip snapshot
        // into the App Group container so connections can build country assets.
        Task { _ = await GeoIPUpdater.shared.prepareIfNeeded() }
        CountryDirectory.shared.setPreferredLanguageCode(L10n.currentLanguageCode)
        #if DEBUG
        resetStateIfRequested()
        #endif
        reload()
        lastTunnelSetup = TunnelSetup(settings: settings)
        #if DEBUG
        applyDebugLaunchOverrides()
        #endif
    }

    /// Single place that reacts to tunnel state changes, whether they come from the
    /// connect flow, the system Settings app, on-demand reconnects or a relaunch.
    private func applyTunnelState(_ state: TunnelState) {
        #if DEBUG
        diagnose("tunnelState=\(String(describing: state))")
        #endif
        tunnelState = state
        switch state {
        case .connected:
            startStatsTimer()
            // A tunnel that appeared without going through `connect()` (system
            // settings / on-demand / relaunch) has no snapshot yet; adopt the current
            // settings so a later change can be detected. A connected tunnel whose
            // snapshot no longer matches the settings (changed while connecting) is
            // restarted to apply them (G3).
            let current = TunnelSetup(settings: settings)
            if appliedSetup == nil {
                appliedSetup = current
            } else if appliedSetup != current, !isAutoReconnecting {
                scheduleAutoReconnect()
            }
            if pendingSettingsAppliedToast {
                pendingSettingsAppliedToast = false
                showToast(L10n.t("toast.settingsApplied"))
            }
        case .disconnected:
            stopStatsTimer()
            sessionStatsModel.reset()
            appliedSetup = nil
        case .error:
            stopStatsTimer()
            appliedSetup = nil
        case .connecting, .disconnecting:
            break
        }
    }

    #if DEBUG
    /// UI-test / screenshot helper: `-WujiBypassOnboarding` skips the first-run gates in DEBUG builds only.
    private func applyDebugLaunchOverrides() {
        reapplyDebugOverridesIfNeeded()
        if ProcessInfo.processInfo.arguments.contains("-WujiConnectedState") {
            tunnelState = .connected
        }
        startAutoConnectIfNeeded()
    }

    /// `-WujiAutoConnect`: skips the gates and immediately connects to the active
    /// node; `-WujiAutoDiagnose` writes state/self-test lines to Documents so a
    /// physical-device run can be inspected without a GUI console.
    private func startAutoConnectIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-WujiAutoConnect"), !didAutoConnect else { return }
        didAutoConnect = true
        var updated = settings
        updated.onboardingDone = true
        updated.consentAccepted = true
        updated.networkPermissionPassed = true
        if updated.activeProfileID == nil, let first = nodes.first {
            updated.activeProfileID = first.id
        }
        settings = updated
        try? settingsStore.save(settings)
        diagnose("autoConnect profile=\(settings.activeProfileID ?? "nil") nodes=\(nodes.count)")
        dumpActiveConfiguration()
        Task { @MainActor in
            if ProcessInfo.processInfo.arguments.contains("-WujiReconnect"),
               case .connected = tunnelState {
                diagnose("forcing reconnect with new tunnel settings")
                await disconnect()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            if ProcessInfo.processInfo.arguments.contains("-WujiResetVPN") {
                diagnose("resetting stale VPN configuration")
                _ = await resetVPNConfiguration()
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            if (ProcessInfo.processInfo.arguments.contains("-WujiDNSLocal")
                || ProcessInfo.processInfo.arguments.contains("-WujiDNSDoH")),
               case .connected = tunnelState {
                diagnose("reconnecting for local DNS mode")
                await disconnect()
            }
            if case .connected = tunnelState {
                diagnose("autoConnect already connected; running probes")
            } else {
                await connect()
            }
            dumpActiveConfiguration()
            await runSelfTest()
        }
    }

    /// DEBUG: when launched with `-WujiXrayLog`, route the Xray logs into the App
    /// Group so the app can copy them into Documents for inspection.
    private func injectDebugXrayLogIfRequested(_ json: String) -> String {
        guard ProcessInfo.processInfo.arguments.contains("-WujiXrayLog"),
              let container = AppGroup.containerURL,
              let data = json.data(using: .utf8),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return json
        }
        root["log"] = [
            "loglevel": "debug",
            "error": container.appendingPathComponent("xray-error.log").path,
            "access": container.appendingPathComponent("xray-access.log").path,
        ]
        guard let updated = try? JSONSerialization.data(withJSONObject: root, options: []),
              let text = String(data: updated, encoding: .utf8) else { return json }
        return text
    }

    private func dumpActiveConfiguration() {
        guard ProcessInfo.processInfo.arguments.contains("-WujiAutoDiagnose"),
              let url = AppGroup.activeTunnelURL,
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let xray = root["xrayJSON"] as? String,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            diagnose("no active configuration to dump")
            return
        }
        let destination = documents.appendingPathComponent("wuji-xray-config.json")
        try? Data(xray.utf8).write(to: destination, options: .atomic)
        diagnose("dumped active configuration bytes=\(xray.utf8.count)")
        for name in ["xray-error.log", "xray-access.log", "route_diag.txt"] {
            if let source = AppGroup.containerURL?.appendingPathComponent(name),
               let data = try? Data(contentsOf: source) {
                try? data.write(to: documents.appendingPathComponent(name), options: .atomic)
                diagnose("copied \(name) bytes=\(data.count)")
            }
        }
    }

    private func runSelfTest() async {
        diagnose("selfTest start state=\(String(describing: tunnelState))")
        dumpTunnelFiles("start")
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        diagnose("selfTest after-wait state=\(String(describing: tunnelState))")
        dumpTunnelFiles("after-wait")
        guard case .connected = tunnelState else {
            diagnose("selfTest skipped banner=\(banner ?? "-")")
            return
        }
        await dumpNetworkPath()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        let probes: [(String, [String: String])] = [
            ("https://1.1.1.1/cdn-cgi/trace", [:]),
            ("https://1.1.1.1/dns-query?name=api.ipify.org&type=A", ["Accept": "application/dns-json"]),
            ("https://api.ipify.org", [:]),
            ("https://www.ip138.com", [:]),
            ("https://www.baidu.com", [:]),
        ]
        probeTCP(host: "1.1.1.1", port: 443)
        probeDNS(host: "www.google.com")
        for (probe, headers) in probes {
            let started = Date()
            var request = URLRequest(url: URL(string: probe)!)
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: data.prefix(120), encoding: .utf8) ?? ""
                let finalURL = response.url?.absoluteString ?? "-"
                diagnose("probe \(probe) status=\(status) final=\(finalURL) ms=\(Int(Date().timeIntervalSince(started) * 1000)) body=\(body.replacingOccurrences(of: "\n", with: " "))")
            } catch {
                diagnose("probe \(probe) error=\(error.localizedDescription)")
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dumpTunnelFiles("after \(probe)")
        }
        diagnose("selfTest end state=\(String(describing: tunnelState))")
    }

    private func dumpNetworkPath() async {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let lock = NSLock()
            var finished = false
            let finish: () -> Void = {
                lock.lock()
                let already = finished
                finished = true
                lock.unlock()
                guard !already else { return }
                monitor.cancel()
                continuation.resume()
            }
            monitor.pathUpdateHandler = { [weak self] path in
                let interfaces = path.availableInterfaces.map { String(describing: $0.type) + ":" + $0.name }.joined(separator: ",")
                let line = "nwpath status=\(path.status) reason=\(String(describing: path.unsatisfiedReason)) interfaces=[\(interfaces)] expensive=\(path.isExpensive) constrained=\(path.isConstrained) dns=\(path.supportsDNS)"
                Task { @MainActor in self?.diagnose(line) }
            }
            monitor.start(queue: DispatchQueue(label: "wuji.path.monitor"))
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { finish() }
        }
    }

    private func probeDNS(host: String) {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        let started = Date()
        let status = getaddrinfo(host, "443", &hints, &result)
        defer { if let result { freeaddrinfo(result) } }
        if status == 0, let result {
            var addresses: [String] = []
            var pointer: UnsafeMutablePointer<addrinfo>? = result
            while let current = pointer, addresses.count < 6 {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen,
                               &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    addresses.append(String(cString: buffer))
                }
                pointer = current.pointee.ai_next
            }
            diagnose("dnsprobe \(host) ok ms=\(Int(Date().timeIntervalSince(started) * 1000)) addrs=\(addresses.joined(separator: ","))")
        } else {
            diagnose("dnsprobe \(host) failed status=\(status) err=\(String(cString: gai_strerror(status)))")
        }
    }

    private func probeTCP(host: String, port: UInt16) {
        let started = Date()
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &result) == 0, let result else {
            diagnose("tcpprobe \(host):\(port) resolve-failed")
            return
        }
        defer { freeaddrinfo(result) }
        let fd = socket(result.pointee.ai_family, result.pointee.ai_socktype, result.pointee.ai_protocol)
        guard fd >= 0 else {
            diagnose("tcpprobe \(host):\(port) socket-failed errno=\(errno)")
            return
        }
        defer { close(fd) }
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let code = Darwin.connect(fd, result.pointee.ai_addr, result.pointee.ai_addrlen)
        if code == 0 {
            diagnose("tcpprobe \(host):\(port) connected ms=\(Int(Date().timeIntervalSince(started) * 1000))")
            return
        }
        guard errno == EINPROGRESS else {
            diagnose("tcpprobe \(host):\(port) connect-failed errno=\(errno) ms=\(Int(Date().timeIntervalSince(started) * 1000))")
            return
        }
        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&descriptor, 1, 8000)
        if ready > 0 {
            var socketError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length)
            if socketError == 0 {
                diagnose("tcpprobe \(host):\(port) connected ms=\(Int(Date().timeIntervalSince(started) * 1000))")
            } else {
                diagnose("tcpprobe \(host):\(port) error=\(socketError) ms=\(Int(Date().timeIntervalSince(started) * 1000))")
            }
        } else {
            diagnose("tcpprobe \(host):\(port) timeout ms=\(Int(Date().timeIntervalSince(started) * 1000))")
        }
    }

    private func dumpTunnelFiles(_ label: String) {
        if let url = AppGroup.tunnelStatusURL, let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            diagnose("\(label) tunnel_status=\(text)")
        }
        if let url = AppGroup.trafficURL, let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            diagnose("\(label) tunnel_traffic=\(text)")
        }
        if let url = AppGroup.containerURL?.appendingPathComponent("xray-error.log"),
           let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            let tail = text.split(separator: "\n").suffix(25).joined(separator: " | ")
            diagnose("\(label) xray_error_log=\(tail)")
        }
    }

    private func diagnose(_ line: String) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-WujiAutoDiagnose") else { return }
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = documents.appendingPathComponent("wuji-diagnose.txt")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(timestamp) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try? handle.close()
        } else {
            try? Data(entry.utf8).write(to: url, options: .atomic)
        }
        #endif
    }

    private func reapplyDebugOverridesIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-WujiLanguage"), index + 1 < arguments.count,
           let language = AppLanguage(rawValue: arguments[index + 1]) {
            settings.appLanguage = language
            L10n.overrideLanguage = language.localeIdentifier
        }
        if arguments.contains("-WujiDNSLocal"), settings.dnsMode != .local {
            settings.dnsMode = .local
            try? settingsStore.save(settings)
        }
        if arguments.contains("-WujiDNSDoH"), settings.dnsMode != .proxyDoH {
            settings.dnsMode = .proxyDoH
            try? settingsStore.save(settings)
        }
        if arguments.contains("-WujiConnectedState") {
            tunnelState = .connected
        }
        if arguments.contains("-WujiDemoSession") {
            sessionStatsModel.stats = TunnelSessionStats(
                uploadBytes: 1_186_000_000,
                downloadBytes: 622_000_000,
                connectedAt: Date().addingTimeInterval(-2538),
                uplinkRate: 3.1 * 1024 * 1024,
                downlinkRate: 12.4 * 1024 * 1024
            )
        }
        if arguments.contains("-WujiBypassOnboarding") {
            settings.networkPermissionPassed = true
        }
        if arguments.contains("-WujiForcePermissionGate") {
            settings.onboardingDone = true
            settings.consentAccepted = false
            settings.networkPermissionPassed = false
        }
        if arguments.contains("-WujiDemoRouting") {
            settings.routingMode = .rule
            settings.bypassLAN = true
            if settings.bypassCountryCodes.isEmpty {
                settings.bypassCountryCodes = ["CN", "JP"]
            }
        }
        guard arguments.contains("-WujiBypassOnboarding") else { return }
        settings.consentAccepted = true
        settings.onboardingDone = true
        if settings.activeProfileID == nil, let first = nodes.first {
            settings.activeProfileID = first.id
        }
    }

    /// UI-test helper: `-WujiResetState` wipes the local database before the app UI appears.
    private func resetStateIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-WujiResetState") else { return }
        try? db.execute("DELETE FROM profiles; DELETE FROM groups; DELETE FROM subscriptions; DELETE FROM settings;")
        settings = .default
        try? settingsStore.save(settings)
        _ = try? profileStore.ensureManualGroup()
    }
    #endif

    // MARK: - Loading

    func reload() {
        do {
            try db.openIfNeeded()
            settings = settingsStore.load()
            _ = try profileStore.ensureManualGroup()
            DemoSeed.seedIfNeeded(store: profileStore)
            groups = try profileStore.groups()
            nodes = try profileStore.profiles()
            subscriptions = try subscriptionStore.all()
            #if DEBUG
            reapplyDebugOverridesIfNeeded()
            #endif
        } catch {
            banner = error.localizedDescription
        }
    }

    var activeProfile: NodeProfile? {
        guard let id = settings.activeProfileID else { return nil }
        return nodes.first { $0.id == id }
    }

    func nodes(in group: NodeGroup) -> [NodeProfile] {
        nodes.filter { $0.groupID == group.id }
    }

    // MARK: - Mutations

    func setActive(_ profile: NodeProfile?) {
        // G3: the tunnel keeps running on the previous node until it is restarted;
        // switching the current node while connected triggers an automatic reconnect.
        setActiveProfileID(profile?.id, reconnectIfConnected: true)
    }

    /// Writes the current node without deciding about a reconnect. Subscription
    /// refreshes re-point the selection to the replacement node (same server and
    /// credentials) and must not restart the tunnel for that.
    private func setActiveProfileID(_ newID: String?, reconnectIfConnected: Bool) {
        guard settings.activeProfileID != newID else {
            if reconnectIfConnected { requestAutoReconnectIfNeeded() }
            return
        }
        settings.activeProfileID = newID
        try? settingsStore.save(settings)
        if reconnectIfConnected {
            markNetworkSettingsAppliedIfNeeded()
            requestAutoReconnectIfNeeded()
        } else {
            // Keep the "settings the tunnel runs with" snapshot in sync so the
            // remapped id does not look like a user change.
            appliedSetup?.activeProfileID = newID
            lastTunnelSetup?.activeProfileID = newID
        }
    }

    func saveSettings() {
        try? settingsStore.save(settings)
        // G3: routing/DNS/country changes made while connected are applied by
        // reconnecting. Confirm when the change actually affects the tunnel; plain
        // UI prefs (language, sort order) stay silent.
        markNetworkSettingsAppliedIfNeeded()
        requestAutoReconnectIfNeeded()
    }

    /// Shows the global "settings applied" toast after a node switch or a
    /// tunnel-affecting settings change. While connected the confirmation waits for
    /// the automatic reconnect to finish; otherwise it appears immediately.
    private func markNetworkSettingsAppliedIfNeeded() {
        let current = TunnelSetup(settings: settings)
        guard current != lastTunnelSetup else { return }
        lastTunnelSetup = current
        guard settings.activeProfileID != nil else { return }
        if tunnelState == .connected {
            pendingSettingsAppliedToast = true
        } else {
            showToast(L10n.t("toast.settingsApplied"))
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
    }

    // MARK: - Automatic reconnect (G3)

    /// Restarts the tunnel when the settings it was started with no longer match the
    /// current ones: current node changed, or routing mode / bypass LAN / bypassed
    /// countries changed. Runs only while connected; changes made while disconnected
    /// are picked up by the next manual connect.
    private func requestAutoReconnectIfNeeded() {
        guard tunnelState == .connected, !isAutoReconnecting else { return }
        guard let applied = appliedSetup, applied != TunnelSetup(settings: settings) else { return }
        scheduleAutoReconnect()
    }

    private func scheduleAutoReconnect() {
        // Debounce so saving several values in a row (country multi-select, mode
        // picker then Done) only restarts the tunnel once.
        autoReconnectTask?.cancel()
        autoReconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.autoReconnectDelay)
            guard let self, !Task.isCancelled else { return }
            self.autoReconnectTask = nil
            await self.performAutoReconnect()
        }
    }

    private func performAutoReconnect() async {
        guard tunnelState == .connected else { return }
        // Every explicit disconnect/removal/reset bumps the epoch; the reconnect must
        // not start its new tunnel after such a request landed while stopping (G3).
        autoReconnectEpoch &+= 1
        let epoch = autoReconnectEpoch
        isAutoReconnecting = true
        defer { isAutoReconnecting = false }
        await stopTunnelAndReset()
        guard epoch == autoReconnectEpoch, tunnelState == .disconnected else { return }
        await connectInternal()
    }

    private func cancelScheduledAutoReconnect() {
        autoReconnectEpoch &+= 1
        autoReconnectTask?.cancel()
        autoReconnectTask = nil
    }

    /// Re-reads the system VPN status (used when the app returns to foreground).
    func syncTunnelSystemState() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-WujiConnectedState") {
            tunnelState = .connected
            return
        }
        #endif
        await tunnel.syncSystemState()
    }

    // MARK: - Removal (B7 / G4)

    /// Deletes a node. User decision for B7/G4: when the node being removed is the
    /// one the tunnel is running on, disconnect first and delete afterwards. The
    /// removal is therefore asynchronous only in that case; callers keep the same
    /// synchronous API and the list updates when the work is done.
    func deleteProfile(_ profile: NodeProfile) {
        guard settings.activeProfileID == profile.id, tunnelState != .disconnected else {
            removeProfile(profile)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.disconnectIfActiveNodeDeleted(profile.id)
            self.removeProfile(profile)
        }
    }

    /// Disconnects the tunnel when `profileID` is the current node and a tunnel is
    /// up (connected, connecting or already disconnecting). Returns `true` when a
    /// disconnect was performed. Used by node deletion and, through
    /// `prepareForRemoval`, by subscription deletion.
    @discardableResult
    func disconnectIfActiveNodeDeleted(_ profileID: String) async -> Bool {
        guard settings.activeProfileID == profileID else { return false }
        switch tunnelState {
        case .connected, .connecting, .disconnecting:
            cancelScheduledAutoReconnect()
            await stopTunnelAndReset()
            return true
        case .disconnected, .error:
            return false
        }
    }

    /// Pre-removal hook for callers that delete nodes through another route (the
    /// subscription list deletes a whole group). Disconnects first when `profileID`
    /// is the running node; the subscription code can call
    /// `prepareForRemoval(ofGroup:)` to cover "active node belongs to this group".
    @discardableResult
    func prepareForRemoval(of profileID: String) async -> Bool {
        await disconnectIfActiveNodeDeleted(profileID)
    }

    /// Convenience for subscription deletion: disconnects when the current node is
    /// part of `groupID`, which is about to be deleted. Returns `true` when a
    /// disconnect was performed.
    @discardableResult
    func prepareForRemoval(ofGroup groupID: String) async -> Bool {
        guard let activeID = settings.activeProfileID,
              nodes.contains(where: { $0.id == activeID && $0.groupID == groupID }) else {
            return false
        }
        return await prepareForRemoval(of: activeID)
    }

    private func removeProfile(_ profile: NodeProfile) {
        try? profileStore.delete(profileID: profile.id)
        if settings.activeProfileID == profile.id {
            setActiveProfileID(nil, reconnectIfConnected: false)
        }
        reload()
    }

    private var latencyAutoTask: Task<Void, Never>?

    /// Measures nodes in the background in small batches and updates each row as its
    /// result arrives. Used after manual/QR/paste imports and every subscription
    /// fetch (manual refresh and the foreground auto-update), so new nodes never sit
    /// at "unknown latency" until the user taps test.
    func scheduleLatencyTests(for profiles: [NodeProfile]) {
        let targets = profiles.filter { candidate in
            nodes.contains(where: { $0.id == candidate.id })
        }
        guard !targets.isEmpty else { return }
        latencyAutoTask?.cancel()
        latencyAutoTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let concurrency = LatencyTester.defaultConcurrency
            var index = 0
            while index < targets.count {
                if Task.isCancelled { return }
                let end = min(index + concurrency, targets.count)
                let batch = Array(targets[index..<end])
                await withTaskGroup(of: (String, Int?).self) { group in
                    for profile in batch {
                        let profileID = profile.id
                        group.addTask { (profileID, await self.testLatencyResult(for: profile)) }
                    }
                    for await (profileID, latency) in group {
                        if Task.isCancelled {
                            group.cancelAll()
                            break
                        }
                        self.updateLatency(profileID: profileID, latencyMs: latency)
                    }
                }
                index = end
            }
        }
    }

    func updateLatency(profileID: String, latencyMs: Int?) {
        try? profileStore.updateLatency(profileID: profileID, latencyMs: latencyMs)
        if let index = nodes.firstIndex(where: { $0.id == profileID }) {
            nodes[index].latencyMs = latencyMs
            nodes[index].latencyAt = Date()
        }
    }

    // MARK: - Latency

    /// Latency shown for a node. The currently connected node is measured with an
    /// HTTP request through the tunnel (the configured test URL) so the number
    /// reflects the real proxy path; every other node uses a TCP handshake.
    /// Falls back to TCP when the HTTP probe fails.
    func testLatencyResult(for profile: NodeProfile) async -> Int? {
        let timeout = settings.latencyTimeout > 0 ? settings.latencyTimeout : LatencyTester.defaultTimeout
        if tunnelState == .connected, profile.id == settings.activeProfileID,
           let httpLatency = await latencyTester.testHTTP(urlString: settings.latencyTestURL, timeout: timeout) {
            return httpLatency
        }
        return await latencyTester.test(profile: profile, timeout: timeout)
    }

    // MARK: - Subscriptions

    /// IDs of the subscriptions whose refresh is currently running. The fetch layer
    /// also has a URL-level gate; this one covers the whole refresh (fetch + replace
    /// nodes + reload) so the foreground auto-update and a manual "Update" cannot
    /// interleave (B8).
    private var refreshingSubscriptionIDs: Set<String> = []

    /// Replaces the nodes of a subscription group with the freshly fetched list.
    @discardableResult
    func refresh(subscription: Subscription) async throws -> Subscription {
        guard !refreshingSubscriptionIDs.contains(subscription.id) else {
            throw SubscriptionError.refreshInProgress
        }
        refreshingSubscriptionIDs.insert(subscription.id)
        defer { refreshingSubscriptionIDs.remove(subscription.id) }

        var subscription = subscription
        guard let group = groups.first(where: { $0.subscriptionID == subscription.id }) else {
            throw SubscriptionError.emptySubscription
        }
        let previousActive = activeProfile
        let activeWasInGroup = previousActive?.groupID == group.id
        do {
            let result = try await subscriptionService.fetch(url: subscription.url, groupID: group.id, name: subscription.name)
            try profileStore.deleteProfiles(inGroup: group.id)
            for node in result.nodes {
                try profileStore.upsert(profile: node)
            }
            subscription.lastUpdatedAt = result.updatedAt
            subscription.trafficUpload = result.trafficUpload
            subscription.trafficDownload = result.trafficDownload
            subscription.trafficTotal = result.trafficTotal
            subscription.expireAt = result.expireAt
            subscription.lastError = nil
            try subscriptionStore.upsert(subscription)
            reload()
            // A5 (audit): the previous node is carried over by matching protocol +
            // server + port + credentials. The old implementation matched on the raw
            // URI, and manual nodes have an empty one, so the selection could jump to
            // an unrelated node. No match means the node really disappeared: clear it.
            if activeWasInGroup, let previousActive {
                if let match = nodes.first(where: { Self.isSameEndpoint($0, previousActive) }) {
                    setActiveProfileID(match.id, reconnectIfConnected: false)
                } else {
                    setActiveProfileID(nil, reconnectIfConnected: false)
                }
            } else if let activeID = settings.activeProfileID,
                      !nodes.contains(where: { $0.id == activeID }) {
                setActiveProfileID(nil, reconnectIfConnected: false)
            }
            scheduleLatencyTests(for: nodes.filter { $0.groupID == group.id })
            return subscription
        } catch {
            // B8 (audit): a failed attempt is recorded with its timestamp too,
            // otherwise the foreground auto-update would retry the same subscription
            // on every activation.
            try? subscriptionStore.recordFailure(subscription, error: error.localizedDescription)
            reload()
            throw error
        }
    }

    /// Identity used to carry the selected node across a subscription refresh:
    /// protocol + server + port, with the credential the protocol actually uses
    /// (VMess/VLESS: uuid, Trojan/Shadowsocks: password). `rawURI` is deliberately
    /// not used — manual nodes have an empty one.
    private static func isSameEndpoint(_ lhs: NodeProfile, _ rhs: NodeProfile) -> Bool {
        guard lhs.proto == rhs.proto, lhs.port == rhs.port else { return false }
        let lhsServer = lhs.server.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rhsServer = rhs.server.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lhsServer == rhsServer else { return false }
        switch lhs.proto {
        case .vmess, .vless:
            let lhsUUID = lhs.uuid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rhsUUID = rhs.uuid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return lhsUUID == rhsUUID
        case .trojan, .shadowsocks:
            return lhs.password == rhs.password
        case .socks:
            return lhs.socksUsername == rhs.socksUsername && lhs.password == rhs.password
        }
    }

    /// Refreshes subscriptions whose auto-update interval elapsed (foreground trigger).
    func autoUpdateSubscriptionsIfNeeded() async {
        guard settings.subscriptionAutoUpdateEnabled else { return }
        let now = Date()
        for subscription in subscriptions {
            guard let interval = subscription.autoUpdateInterval, interval > 0 else { continue }
            if let last = subscription.lastUpdatedAt, now.timeIntervalSince(last) < interval { continue }
            _ = try? await refresh(subscription: subscription)
        }
    }

    // MARK: - VPN configuration

    /// Removes the system VPN configuration and clears the shared tunnel files.
    @discardableResult
    func resetVPNConfiguration() async -> Bool {
        cancelScheduledAutoReconnect()
        // A start that is still in flight must not re-create the configuration that
        // this reset is about to remove.
        connectGeneration &+= 1
        do {
            try await tunnel.resetConfiguration()
            appliedSetup = nil
            sessionStatsModel.reset()
            tunnelState = .disconnected
            return true
        } catch {
            banner = error.localizedDescription
            return false
        }
    }

    func addProfiles(_ newProfiles: [NodeProfile], groupID: String) {
        for profile in newProfiles {
            var profile = profile
            profile.groupID = groupID
            try? profileStore.upsert(profile: profile)
        }
        reload()
        scheduleLatencyTests(for: newProfiles)
    }

    // MARK: - Tunnel

    private var connectGeneration = 0

    func connect() async {
        // An automatic reconnect is already restarting the tunnel; ignore manual taps
        // that land in the short gap between its stop and start (B6).
        guard !isAutoReconnecting else { return }
        await connectInternal()
    }

    private func connectInternal() async {
        guard let profile = activeProfile else {
            banner = NSLocalizedString("home.noNodeSelected", comment: "")
            return
        }
        guard !tunnelState.isBusy else { return }
        connectGeneration &+= 1
        let generation = connectGeneration
        tunnelState = .connecting
        // Snapshot of the settings this start is built from (G3). Any change made
        // before the tunnel reports connected is compared against it on `.connected`
        // and restarts the tunnel once with the new values.
        appliedSetup = TunnelSetup(settings: settings)
        do {
            var geoIPRuleTargets: [String] = []
            // The asset directory is always exported: besides the per-selection
            // GeoIP asset, Xray needs `geosite.dat` there for the split DNS
            // (`geosite:cn` -> domestic resolvers) used in remote-DoH mode.
            let geoIPAssetDirectory = AppGroup.containerURL?.path
            let needsGeoIP = settings.routingMode == .rule && (!settings.bypassCountryCodes.isEmpty || settings.bypassLAN)
            // Prepare also installs geosite.dat, so call it regardless of GeoIP rules.
            _ = await GeoIPUpdater.shared.prepareIfNeeded()
            if needsGeoIP {
                if let asset = GeoIPAssetManager.shared.makeAsset(
                    codes: settings.bypassCountryCodes,
                    includePrivate: settings.bypassLAN,
                    dataVersion: countries.datasetDataVersion ?? ""
                ) {
                    geoIPRuleTargets = asset.ruleTargets
                } else {
                    throw GeoIPAssetError.unavailable
                }
            }
            let input = XrayBuildInput(profile: profile,
                                       settings: settings,
                                       geoIPRuleTargets: geoIPRuleTargets,
                                       geoIPAssetDirectory: geoIPAssetDirectory)
            var json = try XrayConfigBuilder.build(input)
            #if DEBUG
            json = injectDebugXrayLogIfRequested(json)
            #endif
            // On-demand is deliberately off: iOS shows a "Connect On Demand"
            // switch in Settings for configs that use it (the previous app and the
            // competitor do not), and on-demand restarts made the tunnel harder to
            // reason about on real devices. The tunnel still survives locking the
            // screen; only network switches rely on the system's normal VPN recovery.
            let launch = TunnelLaunchConfig(xrayJSON: json,
                                            onDemandEnabled: false,
                                            onDemandMode: .off,
                                            // Global mode means *everything* through the
                                            // proxy, including LAN/private destinations,
                                            // so the system-level LAN exclusions are off.
                                            bypassLAN: settings.routingMode == .rule && settings.bypassLAN)
            guard generation == connectGeneration else { return }
            try await tunnel.prepareAndStart(config: launch, serverHost: profile.server)
            // A cancel (disconnect / removal / reset) while the system was starting
            // must not be overwritten by a later "connected" state. When the start
            // completed anyway, bring the tunnel down so a cancelled attempt cannot
            // stay connected.
            guard generation == connectGeneration else {
                await tunnel.stop()
                return
            }
            startStatsTimer()
        } catch {
            // Ignore failures that belong to a start the user already cancelled.
            guard generation == connectGeneration, tunnelState != .disconnected else { return }
            tunnelState = .error(error.localizedDescription)
            banner = error.localizedDescription
            #if DEBUG
            diagnose("connect failed: \(error.localizedDescription)")
            #endif
        }
    }

    func disconnect() async {
        cancelScheduledAutoReconnect()
        await stopTunnelAndReset()
    }

    /// Shared stop path: invalidates a pending connect, stops the system tunnel and
    /// clears the session figures. Used by user disconnect, removal (B7/G4) and the
    /// automatic reconnect (G3, which then starts a fresh tunnel itself).
    private func stopTunnelAndReset() async {
        connectGeneration &+= 1
        stopStatsTimer()
        sessionStatsModel.reset()
        await tunnel.stop()
        tunnelState = .disconnected
        sessionStatsModel.reset()
    }

    func toggleTunnel() async {
        switch tunnelState {
        case .connected:
            await disconnect()
        case .connecting, .disconnecting:
            // Busy: the Home connection button is disabled in these states (B6).
            return
        default:
            await connect()
        }
    }

    private func startStatsTimer() {
        guard statsTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let stats = await self.tunnel.requestTrafficStats() else { return }
                guard self.tunnelState != .disconnected else { return }
                self.sessionStatsModel.stats = stats
            }
        }
        statsTimer = timer
    }

    private func stopStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
    }

    #if DEBUG
    private var didAutoConnect = false
    #endif

    private var geoIPRefreshTimer: Timer?

    /// GeoIP updates only run while the VPN is connected (the download has to go
    /// through the tunnel where GitHub/jsDelivr are reachable). Failures retry with a
    /// fixed hourly cadence – no exponential backoff – until one succeeds.
    private func startGeoIPRefresh() {
        Task { await GeoIPUpdater.shared.updateIfNeeded(vpnConnected: true) }
        guard geoIPRefreshTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.tunnelState == .connected else { return }
                await GeoIPUpdater.shared.updateIfNeeded(vpnConnected: true)
            }
        }
        geoIPRefreshTimer = timer
    }

    private func stopGeoIPRefresh() {
        geoIPRefreshTimer?.invalidate()
        geoIPRefreshTimer = nil
    }
}


/// Raised when the GeoIP dataset/asset is not ready, which would silently send the
/// user's selected "direct" countries through the proxy.
enum GeoIPAssetError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return NSLocalizedString("error.geoip.unavailable", comment: "")
        }
    }
}
