import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var session: SessionStatsModel
    var onNavigate: (Tab) -> Void = { _ in }
    @State private var showFirstConnectSheet = false
    @State private var showRouting = false

    private var isConnected: Bool {
        if case .connected = app.tunnelState { return true }
        return false
    }

    private var statusTitle: String {
        switch app.tunnelState {
        case .disconnected: return L10n.t("home.notConnected")
        case .connecting: return L10n.t("home.connecting")
        case .connected: return L10n.t("home.connected")
        case .disconnecting: return L10n.t("home.disconnecting")
        case .error: return L10n.t("home.notConnected")
        }
    }

    private var statusSubtitle: String {
        if case .error(let message) = app.tunnelState { return message }
        if let profile = app.activeProfile {
            let latency = profile.latencyMs.map { String(format: L10n.t("unit.ms"), $0) } ?? L10n.t("home.latencyUnknown")
            return "\(profile.displayName) · \(profile.proto.shortBadge) · \(latency)"
        }
        return L10n.t("home.selectNodeHint")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    connectionControl
                        .padding(.top, 10)
                        .padding(.horizontal, Theme.hMargin)

                    if case .error(let message) = app.tunnelState {
                        ErrorBanner(message: message)
                    }

                    CardContainer {
                        VStack(spacing: 0) {
                            Button {
                                onNavigate(.nodes)
                            } label: {
                                DataRowView(symbol: "server.rack",
                                            title: L10n.t("home.currentNode"),
                                            value: app.activeProfile?.displayName ?? L10n.t("home.none"),
                                            showsChevron: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("wuji.home.currentNodeRow")
                            RowDivider()
                            Button {
                                showRouting = true
                            } label: {
                                DataRowView(symbol: "arrow.triangle.branch",
                                            title: L10n.t("home.routing"),
                                            value: routingSummary,
                                            showsChevron: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("wuji.home.routingRow")
                        }
                    }

                    CardContainer {
                        VStack(spacing: 0) {
                            SectionHeader(title: L10n.t("home.thisSession"))
                                .padding(.top, 4)
                            DataRowView(symbol: "arrow.down", title: L10n.t("home.download"), value: formattedRate(session.stats.downlinkRate))
                            RowDivider()
                            DataRowView(symbol: "arrow.up", title: L10n.t("home.upload"), value: formattedRate(session.stats.uplinkRate))
                            RowDivider()
                            DataRowView(symbol: "clock", title: L10n.t("home.duration"), value: formattedDuration)
                            RowDivider()
                            DataRowView(symbol: "chart.bar", title: L10n.t("home.total"), value: formattedBytes(session.stats.uploadBytes + session.stats.downloadBytes))
                        }
                        .padding(.bottom, 6)
                    }

                    if !isConnected && app.activeProfile == nil {
                        PlainActionButton(title: L10n.t("home.chooseNode")) {
                            onNavigate(.nodes)
                        }
                        .accessibilityIdentifier("wuji.home.chooseNode")
                    }
                }
                .padding(.bottom, 96)
            }
            .background(Theme.background)
            // The old large "Connect" navigation title and the top-right menu
            // (Settings / Reset VPN) were removed by request; the tab bar and the
            // Settings tab remain the only navigation entry points.
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showFirstConnectSheet) {
                FirstConnectSheet {
                    showFirstConnectSheet = false
                    app.settings.firstConnectExplained = true
                    app.saveSettings()
                    Task { await app.connect() }
                } onCancel: {
                    showFirstConnectSheet = false
                }
            }
            .sheet(isPresented: $showRouting) {
                RoutingSettingsView()
            }
        }
    }

    private var routingSummary: String {
        if app.settings.routingMode == .global {
            return L10n.t("routing.global")
        }
        let count = app.settings.bypassCountryCodes.count + (app.settings.bypassLAN ? 1 : 0)
        return String(format: L10n.t("routing.summary"), count)
    }

    // MARK: - Connection control (selected concept: large pill button)

    private var isOn: Bool {
        switch app.tunnelState {
        case .connected, .connecting, .disconnecting: return true
        case .disconnected, .error: return false
        }
    }

    private var busy: Bool { app.tunnelState.isBusy }

    private var connectionControl: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                HStack(spacing: 7) {
                    if isConnected {
                        Circle().fill(Theme.green).frame(width: 8, height: 8)
                    }
                    Text(statusTitle)
                        .font(.title3.bold())
                        .foregroundStyle(Theme.label)
                        .accessibilityIdentifier("wuji.home.statusTitle")
                }
                Text(statusSubtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wuji.home.statusSubtitle")
            }
            .frame(maxWidth: .infinity)

            Button {
                Task { await toggleConnection() }
            } label: {
                HStack(spacing: 8) {
                    if busy {
                        ProgressView()
                            .tint(isOn ? Theme.label : .white)
                    } else {
                        Image(systemName: isOn ? "stop.fill" : "power")
                            .font(.headline)
                    }
                    Text(isOn ? L10n.t("home.action.disconnect") : L10n.t("home.action.connect"))
                        .font(.headline)
                }
                .foregroundStyle(isOn ? Theme.label : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(isOn ? Color(.tertiarySystemFill) : Theme.tint)
                .clipShape(Capsule())
                .animation(.easeInOut(duration: 0.2), value: isOn)
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityIdentifier("wuji.home.connectPill")
        }
        .padding(.top, 6)
    }

    private func toggleConnection() async {
        if isOn {
            await app.disconnect()
        } else {
            await handleSwitchOn()
        }
    }

    private func handleSwitchOn() async {
        guard app.activeProfile != nil else {
            onNavigate(.nodes)
            return
        }
        if !app.settings.firstConnectExplained {
            showFirstConnectSheet = true
        } else {
            await app.connect()
        }
    }

    private func formattedRate(_ bytes: Double) -> String {
        let value = bytes
        if value < 1024 { return String(format: "%.0f B/s", value) }
        if value < 1024 * 1024 { return String(format: "%.1f KB/s", value / 1024) }
        return String(format: "%.1f MB/s", value / 1024 / 1024)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }

    private var formattedDuration: String {
        guard let start = session.stats.connectedAt else { return "00:00:00" }
        let interval = Int(Date().timeIntervalSince(start))
        return String(format: "%02d:%02d:%02d", interval / 3600, (interval % 3600) / 60, interval % 60)
    }
}
