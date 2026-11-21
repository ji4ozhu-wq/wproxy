import SwiftUI

/// Routing settings (spec §5.10, design reference `N-routing-settings`).
/// Presented as a sheet from the Home routing summary; changes are saved immediately.
struct RoutingSettingsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    /// When pushed inside an existing NavigationStack (e.g. the debug screenshot route)
    /// the view must not create a nested NavigationStack of its own.
    var embeddedInNavigation: Bool = false

    @State private var showRegionPicker = false
    @State private var didOpenRegionPickerForScreenshot = false

    private var isGlobal: Bool { app.settings.routingMode == .global }

    private var isTunnelActive: Bool {
        switch app.tunnelState {
        case .connecting, .connected, .disconnecting: return true
        default: return false
        }
    }

    private var selectedCodes: [String] {
        app.settings.bypassCountryCodes
    }

    var body: some View {
        if embeddedInNavigation {
            content
        } else {
            NavigationStack {
                content
            }
        }
    }

    private var content: some View {
        List {
            modeSection
            dnsSection
            localNetworkSection
            regionsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.t("routing.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.t("common.done")) { dismiss() }
                    .accessibilityIdentifier("wuji.routing.done")
            }
        }
        .sheet(isPresented: $showRegionPicker) {
            CountryPickerView()
        }
        .accessibilityIdentifier("wuji.routing.list")
        .task {
            #if DEBUG
            await openRegionPickerForScreenshotIfNeeded()
            #endif
        }
    }

    // MARK: - Sections

    /// "Global" is a single switch inside the rule settings, not a separate tab/page.
    /// Off = rule-based routing (LAN + selected regions direct); on = everything
    /// through the proxy and the bypass lists below are ignored.
    private var modeSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { app.settings.routingMode == .global },
                set: { isGlobal in
                    let newValue: RoutingMode = isGlobal ? .global : .rule
                    guard app.settings.routingMode != newValue else { return }
                    app.settings.routingMode = newValue
                    app.saveSettings()
                }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("routing.globalMode", table: "Routing"))
                        .foregroundStyle(Theme.label)
                    Text(L10n.t("routing.globalMode.subtitle", table: "Routing"))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .tint(Theme.green)
            .accessibilityIdentifier("wuji.routing.globalModeToggle")
        } header: {
            UppercaseSectionHeader(title: L10n.t("routing.modeSection"))
        } footer: {
            Text(modeFootnote)
        }
    }

    /// DNS handling is independent of Global mode: both modes still need an answer
    /// for every name the device resolves.
    private var dnsSection: some View {
        Section {
            ForEach(DNSMode.allCases, id: \.self) { mode in
                Button {
                    guard app.settings.dnsMode != mode else { return }
                    app.settings.dnsMode = mode
                    app.saveSettings()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t(mode.displayNameKey, table: "Routing"))
                                .foregroundStyle(Theme.label)
                            Text(L10n.t(mode == .proxyDoH
                                        ? "routing.dns.doh.subtitle"
                                        : "routing.dns.local.subtitle", table: "Routing"))
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if app.settings.dnsMode == mode {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wuji.routing.dns.\(mode.rawValue)")
            }
        } header: {
            UppercaseSectionHeader(title: L10n.t("routing.dns.section", table: "Routing"))
        } footer: {
            Text(L10n.t("routing.dns.footnote", table: "Routing"))
        }
    }

    private var localNetworkSection: some View {
        Section {
            Toggle(L10n.t("routing.bypassLan"), isOn: Binding(
                get: { app.settings.bypassLAN },
                set: { newValue in
                    app.settings.bypassLAN = newValue
                    app.saveSettings()
                }
            ))
            .tint(Theme.green)
            .disabled(isGlobal)
            .accessibilityIdentifier("wuji.routing.bypassLanToggle")
        } header: {
            UppercaseSectionHeader(title: L10n.t("routing.localSection"))
        } footer: {
            Text(L10n.t("routing.bypassLan.footnote", table: "Routing"))
        }
    }

    private var regionsSection: some View {
        Section {
            Button {
                showRegionPicker = true
            } label: {
                ValueRow(title: L10n.t("routing.bypassedRegions"),
                         value: String(format: L10n.t("routing.selectedCount"), selectedCodes.count),
                         showsChevron: true)
            }
            .buttonStyle(.plain)
            .disabled(isGlobal)
            .accessibilityIdentifier("wuji.routing.regionsRow")

            if selectedCodes.isEmpty {
                Text(L10n.t("routing.noRegions", table: "Routing"))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityIdentifier("wuji.routing.regionsEmpty")
            } else {
                ForEach(selectedCodes, id: \.self) { code in
                    Button {
                        showRegionPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Text(regionName(for: code))
                                .font(.body)
                                .foregroundStyle(Theme.label)
                            Spacer(minLength: 8)
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.tint)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isGlobal)
                    .accessibilityIdentifier("wuji.routing.region.\(code)")
                }
            }

            Button {
                showRegionPicker = true
            } label: {
                Text(L10n.t("routing.addRegion", table: "Routing"))
                    .font(.body)
                    .foregroundStyle(isGlobal ? Theme.tertiaryLabel : Theme.tint)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isGlobal)
            .accessibilityIdentifier("wuji.routing.addRegion")
        } header: {
            UppercaseSectionHeader(title: L10n.t("routing.regionsSection"))
        } footer: {
            Text(L10n.t("routing.serverRoutingFootnote", table: "Routing"))
        }
    }

    // MARK: - Helpers

    private var modeFootnote: String {
        if isTunnelActive {
            return "\(modeFootnoteText)\n\n\(L10n.t("routing.reconnectFootnote", table: "Routing"))"
        }
        return modeFootnoteText
    }

    private var modeFootnoteText: String {
        if isGlobal {
            return L10n.t("routing.mode.globalFootnote", table: "Routing")
        }
        return L10n.t("routing.mode.ruleFootnote", table: "Routing")
    }

    private func regionName(for code: String) -> String {
        if let info = app.countries.countries.first(where: { $0.code == code }) {
            return info.name
        }
        return CountryDirectory.localizedName(for: code)
    }

    #if DEBUG
    /// Screenshot harness: `-WujiScreenshotRoute regions` opens the region picker on top
    /// of this sheet once it has been presented.
    private func openRegionPickerForScreenshotIfNeeded() async {
        guard !didOpenRegionPickerForScreenshot else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-WujiScreenshotRoute"),
              index + 1 < arguments.count,
              arguments[index + 1] == "regions" else { return }
        didOpenRegionPickerForScreenshot = true
        try? await Task.sleep(nanoseconds: 500_000_000)
        showRegionPicker = true
    }
    #endif
}
