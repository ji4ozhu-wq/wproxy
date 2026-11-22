import AppKit
import Combine
import SwiftUI

/// macOS menu bar extra (system tray) for quick connection actions.
/// Chosen design: native `NSMenu` (option A) with standard items, a node submenu,
/// routing-mode submenu and live session statistics rows.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var refreshTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var statRows: [MenuBarStatsRow] = []

    func start() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        self.menu = menu

        updateStatusButton()

        AppState.shared.$tunnelState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusButton() }
            .store(in: &cancellables)

        AppState.shared.sessionStatsModel.$stats
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatsRows() }
            .store(in: &cancellables)
    }

    // MARK: - Status button

    private func updateStatusButton() {
        guard let button = statusItem?.button else { return }
        let app = AppState.shared

        let greenDot: NSColor?
        switch app.tunnelState {
        case .connected: greenDot = .systemGreen
        case .connecting, .disconnecting: greenDot = .systemOrange
        default: greenDot = nil
        }
        button.image = statusIcon(dotColor: greenDot)
        button.imagePosition = .imageOnly
        button.attributedTitle = NSAttributedString(string: "")
        button.toolTip = statusLine
    }

    /// Menu bar icon: the app's own icon (not a generic SF Symbol), with an optional
    /// colored status dot for connected / connecting states.
    private func statusIcon(dotColor: NSColor?) -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        defer { image.unlockFocus() }

        if let appIcon = NSApp.applicationIconImage {
            appIcon.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                         from: .zero, operation: .sourceOver, fraction: 1)
        } else if let fallback = NSImage(systemSymbolName: "globe", accessibilityDescription: "WProxy") {
            fallback.draw(in: NSRect(x: 1, y: 1, width: side - 2, height: side - 2),
                          from: .zero, operation: .sourceOver, fraction: 1)
        }

        if let dotColor {
            let dotSize: CGFloat = 6.5
            let dotRect = NSRect(x: side - dotSize - 0.5, y: 0.5, width: dotSize, height: dotSize)
            let dot = NSBezierPath(ovalIn: dotRect)
            dotColor.setFill()
            dot.fill()
            // subtle light outline so the dot reads on dark menu bars as well
            NSColor.white.withAlphaComponent(0.55).setStroke()
            dot.lineWidth = 0.8
            dot.stroke()
        }
        return image
    }

    private var statusLine: String {
        let app = AppState.shared
        let status: String
        switch app.tunnelState {
        case .connected: status = L10n.t("home.connected")
        case .connecting: status = L10n.t("home.connecting")
        case .disconnecting: status = L10n.t("home.disconnecting")
        default: status = L10n.t("home.notConnected")
        }
        guard let profile = app.activeProfile else { return status }
        return "\(status) · \(profile.displayName) · \(profile.proto.shortBadge)"
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu(menu)
        startRefreshTimer()
    }

    func menuDidClose(_ menu: NSMenu) {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatsRows() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        statRows = []

        let app = AppState.shared
        let connected = isConnected(app.tunnelState)

        // Header: status · node · protocol
        let header = NSMenuItem()
        let headerTitle = connected || app.activeProfile != nil ? statusLine : L10n.t("home.notConnected")
        header.attributedTitle = NSAttributedString(
            string: headerTitle,
            attributes: [.font: NSFont.systemFont(ofSize: 12),
                         .foregroundColor: NSColor.secondaryLabelColor]
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Connect / disconnect
        let connectItem = NSMenuItem(
            title: connected ? L10n.t("home.action.disconnect") : L10n.t("home.action.connect"),
            action: #selector(toggleConnection),
            keyEquivalent: "d"
        )
        connectItem.target = self
        connectItem.keyEquivalentModifierMask = [.command]
        connectItem.image = symbol(connected ? "stop.fill" : "power")
        menu.addItem(connectItem)

        // Current node submenu
        let nodeItem = NSMenuItem(title: L10n.t("home.currentNode"), action: nil, keyEquivalent: "")
        nodeItem.image = symbol("server.rack")
        let nodeMenu = NSMenu()
        let nodes = app.nodes.sorted { lhs, rhs in
            if lhs.groupID != rhs.groupID {
                let lg = app.groups.firstIndex(where: { $0.id == lhs.groupID }) ?? Int.max
                let rg = app.groups.firstIndex(where: { $0.id == rhs.groupID }) ?? Int.max
                if lg != rg { return lg < rg }
            }
            return lhs.sortOrder < rhs.sortOrder
        }
        if nodes.isEmpty {
            let empty = NSMenuItem(title: L10n.t("home.none"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            nodeMenu.addItem(empty)
        } else {
            for profile in nodes {
                let item = NSMenuItem(title: profile.displayName, action: #selector(selectNode(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = profile.id
                item.state = (profile.id == app.settings.activeProfileID) ? .on : .off
                if let latency = profile.latencyMs {
                    item.title = "\(profile.displayName)  ·  \(latency) ms"
                }
                nodeMenu.addItem(item)
            }
        }
        nodeItem.submenu = nodeMenu
        menu.addItem(nodeItem)

        // Routing mode submenu
        let routingItem = NSMenuItem(title: L10n.t("home.routing"), action: nil, keyEquivalent: "")
        routingItem.image = symbol("arrow.triangle.branch")
        let routingMenu = NSMenu()
        for mode in [RoutingMode.rule, .global] {
            let title = mode == .rule ? L10n.t("routing.rule") : L10n.t("routing.global")
            let item = NSMenuItem(title: title, action: #selector(selectRoutingMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = app.settings.routingMode == mode ? .on : .off
            routingMenu.addItem(item)
        }
        routingItem.submenu = routingMenu
        menu.addItem(routingItem)

        menu.addItem(.separator())

        // Live session statistics
        let stats = app.sessionStatsModel.stats
        let rows: [(String, String)] = [
            (L10n.t("home.download"), rate(stats.downlinkRate)),
            (L10n.t("home.upload"), rate(stats.uplinkRate)),
            (L10n.t("home.duration"), duration(stats))
        ]
        for (title, value) in rows {
            let rowView = MenuBarStatsRow(title: title)
            rowView.setValue(value)
            let item = NSMenuItem()
            item.view = rowView
            item.isEnabled = false
            menu.addItem(item)
            statRows.append(rowView)
        }

        menu.addItem(.separator())

        let showItem = NSMenuItem(title: L10n.t("menu.showWindow"), action: #selector(showMainWindow), keyEquivalent: "")
        showItem.target = self
        showItem.image = symbol("macwindow")
        menu.addItem(showItem)

        let logsItem = NSMenuItem(title: L10n.t("logs.title") + "…", action: #selector(openConnectionLog), keyEquivalent: "l")
        logsItem.target = self
        logsItem.keyEquivalentModifierMask = [.command]
        logsItem.image = symbol("doc.text.magnifyingglass")
        menu.addItem(logsItem)

        let settingsItem = NSMenuItem(title: L10n.t("tab.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.image = symbol("gearshape")
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: L10n.t("menu.about"), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = symbol("info.circle")
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.t("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = symbol("rectangle.portrait.and.arrow.right")
        menu.addItem(quitItem)

        refreshStatsRows()
    }

    // MARK: - Stats

    private func refreshStatsRows() {
        guard !statRows.isEmpty else { return }
        let stats = AppState.shared.sessionStatsModel.stats
        let values = [rate(stats.downlinkRate), rate(stats.uplinkRate), duration(stats)]
        for (row, value) in zip(statRows, values) {
            row.setValue(value)
        }
    }

    private func isConnected(_ state: TunnelState) -> Bool {
        if case .connected = state { return true }
        return false
    }

    private func rate(_ bytes: Double) -> String {
        if bytes < 1024 { return String(format: "%.0f B/s", bytes) }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB/s", bytes / 1024) }
        return String(format: "%.1f MB/s", bytes / 1024 / 1024)
    }

    private func duration(_ stats: TunnelSessionStats) -> String {
        guard let start = stats.connectedAt else { return "00:00:00" }
        let interval = max(0, Int(Date().timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", interval / 3600, (interval % 3600) / 60, interval % 60)
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    // MARK: - Actions

    @objc private func toggleConnection() {
        let app = AppState.shared
        switch app.tunnelState {
        case .connected, .connecting, .disconnecting:
            Task { await app.disconnect() }
        default:
            if app.activeProfile == nil {
                openWindow(tab: "nodes")
            } else {
                Task { await app.connect() }
            }
        }
    }

    @objc private func selectNode(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let profile = AppState.shared.nodes.first(where: { $0.id == id }) else { return }
        AppState.shared.setActive(profile)
    }

    @objc private func selectRoutingMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = RoutingMode(rawValue: raw) else { return }
        AppState.shared.settings.routingMode = mode
        AppState.shared.saveSettings()
    }

    @objc private func showMainWindow() {
        openWindow(tab: nil)
    }

    @objc private func openConnectionLog() {
        openWindow(tab: "logs")
    }

    @objc private func openSettings() {
        openWindow(tab: "settings")
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "WProxy",
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            .version: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        ])
    }

    private func openWindow(tab: String?) {
        if let tab {
            NotificationCenter.default.post(name: .wujiSelectTab, object: tab)
        }
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Ask LaunchServices to reopen the app, which opens the main Window scene.
            NSWorkspace.shared.open(Bundle.main.bundleURL)
        }
    }
}

/// Two-column statistics row hosted inside an `NSMenuItem` so values can be right aligned
/// like the native menu design.
final class MenuBarStatsRow: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 18))
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.frame = NSRect(x: 12, y: 1, width: 100, height: 16)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.textColor = .labelColor
        valueLabel.frame = NSRect(x: 110, y: 1, width: 128, height: 16)
        addSubview(titleLabel)
        addSubview(valueLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setValue(_ value: String) {
        valueLabel.stringValue = value
    }
}
