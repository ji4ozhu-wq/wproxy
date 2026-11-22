import SwiftUI

/// Settings root (spec §5.11, design reference `N-settings`). Also acts as the entry
/// point for the subscription list, routing is reached from the Home summary row.
struct SettingsView: View {
    @EnvironmentObject private var app: AppState

    @State private var path = NavigationPath()
    @State private var showAddSubscription = false
    @State private var showRoutingSheet = false
    @State private var confirmation: ConfirmationRequest?
    @State private var toast: String?
    @State private var didApplyScreenshotRoute = false
    @State private var geoIPStatus = GeoIPUpdater.shared.status
    @State private var geoIPUpdating = false

    enum Route: Hashable {
        case subscriptionList
        case subscriptionDetail(String)
        case testURL
        case timeout
        case about
        case languagePicker
        case licenses
        case terms
        case privacy
        case routing
    }

    private static let supportEmail = "ji4ozhu@gmail.com"

    var body: some View {
        NavigationStack(path: $path) {
            settingsRoot
                .navigationTitle(PlatformFlags.isMacOS ? "" : L10n.t("tab.settings"))
            .navigationDestination(for: Route.self) { route in
                destination(for: route)
            }
            .sheet(isPresented: $showAddSubscription) {
                AddSubscriptionView()
                    .wujiSheetSizing(width: 520, height: 620)
            }
            .sheet(isPresented: $showRoutingSheet) {
                RoutingSettingsView()
                    .wujiSheetSizing(width: 520, height: 640)
            }
            .sheet(item: $confirmation) { request in
                ConfirmationSheet(request: request)
                    .wujiSheetSizing(width: 420, height: 240)
            }
            .wujiToast($toast)
            .task {
                geoIPStatus = GeoIPUpdater.shared.status
                #if DEBUG
                applyScreenshotRouteIfNeeded()
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: GeoIPUpdater.didUpdateNotification)) { _ in
                geoIPStatus = GeoIPUpdater.shared.status
            }
            .accessibilityIdentifier("wuji.settings.list")
        }
    }

    /// Root content: native grouped Form on macOS, iOS-style List elsewhere.
    @ViewBuilder
    private var settingsRoot: some View {
        #if os(macOS)
        macGlassSettingsContent
        #else
        ScrollViewReader { proxy in
            List {
                latencySection
                subscriptionsSection
                geoIPSection
                languageSection.id("settings.language.section")
                supportSection
                dataSection
            }
            .wujiListStyle()
            .task {
                #if DEBUG
                await applyLanguageScreenshotHarness(proxy)
                #endif
            }
        }
        #endif
    }

    // MARK: - macOS iOS 26 Liquid Glass settings

    #if os(macOS)
    private var macGlassSettingsContent: some View {
        MacGlassPage {
            ViewThatFits(in: .vertical) {
                macGlassSettingsColumns
                ScrollView {
                    macGlassSettingsColumns
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
    }

    /// Two compact columns keep every settings section visible without a scrollbar.
    private var macGlassSettingsColumns: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("tab.settings"))
                .font(MacGlass.titleFont)
                .foregroundStyle(Theme.label)
                .padding(.horizontal, 4)

            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 14) {
                    macGlassLatencySection
                    macGlassSubscriptionsSection
                    macGlassGeoIPSection
                }
                VStack(spacing: 14) {
                    macGlassLanguageSection
                    macGlassSupportSection
                    macGlassDataSection
                }
            }
        }
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }

    private func macGlassSection<Rows: View>(title: String, footnote: String? = nil,
                                             @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MacGlassSectionHeader(title: title)
            MacGlassCard {
                VStack(spacing: 0) { rows() }
            }
            if let footnote {
                MacGlassFootnote(text: footnote)
            }
        }
    }

    private var macGlassLatencySection: some View {
        macGlassSection(title: L10n.t("settings.latency.section", table: "Settings")) {
            NavigationLink(value: Route.testURL) {
                MacGlassRow(symbol: "gauge.medium", tint: MacGlass.blue,
                            title: L10n.t("settings.latency.testURL", table: "Settings"),
                            value: SubscriptionFormat.host(app.settings.latencyTestURL))
            }
            .buttonStyle(.plain)
            .wujiRowHover()
            .accessibilityIdentifier("wuji.settings.testURL")

            MacGlassDivider()

            NavigationLink(value: Route.timeout) {
                MacGlassRow(symbol: "clock", tint: MacGlass.orange,
                            title: L10n.t("settings.latency.timeout", table: "Settings"),
                            value: secondsLabel(for: app.settings.latencyTimeout))
            }
            .buttonStyle(.plain)
            .wujiRowHover()
            .accessibilityIdentifier("wuji.settings.timeout")
        }
    }

    private var macGlassSubscriptionsSection: some View {
        macGlassSection(title: L10n.t("settings.section.subscriptions")) {
            HStack(spacing: 12) {
                MacGlassIcon(symbol: "arrow.triangle.2.circlepath", tint: MacGlass.green)
                Text(L10n.t("settings.autoUpdate"))
                    .font(MacGlass.rowFont)
                    .foregroundStyle(Theme.label)
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { app.settings.subscriptionAutoUpdateEnabled },
                    set: { newValue in
                        app.settings.subscriptionAutoUpdateEnabled = newValue
                        app.saveSettings()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(MacGlass.green)
                .accessibilityIdentifier("wuji.settings.autoUpdate")
            }
            .padding(.horizontal, 16)
            .frame(height: MacGlass.rowHeight)

            MacGlassDivider()

            NavigationLink(value: Route.subscriptionList) {
                MacGlassRow(symbol: "dot.radiowaves.left.and.right", tint: MacGlass.blue,
                            title: L10n.t("settings.subscriptions"),
                            value: "\(app.subscriptions.count)")
            }
            .buttonStyle(.plain)
            .wujiRowHover()
            .accessibilityIdentifier("wuji.settings.subscriptions")
        }
    }

    private var macGlassGeoIPSection: some View {
        macGlassSection(title: L10n.t("settings.geoip.section", table: "Settings")) {
            MacGlassRow(symbol: "globe", tint: MacGlass.purple,
                        title: L10n.t("settings.geoip.status", table: "Settings"),
                        value: geoIPStatusText,
                        showsChevron: false)
                .accessibilityIdentifier("wuji.settings.geoipStatus")

            MacGlassDivider()

            Button {
                Task { await runGeoIPUpdate() }
            } label: {
                HStack(spacing: 12) {
                    MacGlassIcon(symbol: "arrow.down.circle", tint: MacGlass.blue)
                    Text(L10n.t("settings.geoip.updateNow", table: "Settings"))
                        .font(MacGlass.rowFont)
                        .foregroundStyle(MacGlass.blue)
                    Spacer(minLength: 8)
                    if geoIPUpdating {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: MacGlass.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .wujiRowHover()
            .disabled(geoIPUpdating)
            .accessibilityIdentifier("wuji.settings.geoipUpdate")
        }
    }

    private var macGlassLanguageSection: some View {
        macGlassSection(title: L10n.t("settings.language.section", table: "Settings")) {
            Button {
                selectLanguage(.system)
            } label: {
                HStack(spacing: 12) {
                    MacGlassIcon(symbol: "character.bubble", tint: MacGlass.teal)
                    Text(L10n.t("settings.language.followSystem", table: "Settings"))
                        .font(MacGlass.rowFont)
                        .foregroundStyle(Theme.label)
                    Spacer(minLength: 8)
                    if app.settings.appLanguage == .system {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MacGlass.blue)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: MacGlass.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .wujiRowHover()
            .accessibilityIdentifier("wuji.settings.language.followSystem")

            MacGlassDivider()

            NavigationLink(value: Route.languagePicker) {
                MacGlassRow(symbol: "globe", tint: MacGlass.teal,
                            title: L10n.t("settings.language.current", table: "Settings"),
                            value: currentLanguageName)
            }
            .buttonStyle(.plain)
            .wujiRowHover()
            .accessibilityIdentifier("wuji.settings.language.chooseAnother")
        }
    }

    private var macGlassSupportSection: some View {
        macGlassSection(title: L10n.t("settings.section.support")) {
            NavigationLink(value: Route.about) {
                MacGlassRow(symbol: "info.circle", tint: MacGlass.gray, title: L10n.t("settings.about"))
            }
            .buttonStyle(.plain)
            .wujiRowHover()
            .accessibilityIdentifier("wuji.settings.about")

            MacGlassDivider()

            Button {
                openSupportEmail()
            } label: {
                HStack(spacing: 12) {
                    MacGlassIcon(symbol: "envelope", tint: MacGlass.gray)
                    Text(L10n.t("settings.contact"))
                        .font(MacGlass.rowFont)
                        .foregroundStyle(Theme.label)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryLabel)
                }
                .padding(.horizontal, 16)
                .frame(height: MacGlass.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .wujiRowHover()
            .accessibilityIdentifier("wuji.settings.contact")

            MacGlassDivider()

            NavigationLink(value: Route.terms) {
                MacGlassRow(symbol: "doc.text", tint: MacGlass.gray, title: L10n.t("settings.terms"))
            }
            .buttonStyle(.plain)
            .wujiRowHover()
            .accessibilityIdentifier("wuji.settings.terms")

            MacGlassDivider()

            NavigationLink(value: Route.privacy) {
                MacGlassRow(symbol: "hand.raised", tint: MacGlass.gray, title: L10n.t("settings.privacy"))
            }
            .buttonStyle(.plain)
            .wujiRowHover()
            .accessibilityIdentifier("wuji.settings.privacy")
        }
    }

    private var macGlassDataSection: some View {
        macGlassSection(title: L10n.t("settings.section.data", table: "Settings")) {
            Button(role: .destructive) {
                confirmation = clearDataRequest()
            } label: {
                HStack(spacing: 12) {
                    MacGlassIcon(symbol: "trash", tint: MacGlass.red)
                    Text(L10n.t("settings.clearData"))
                        .font(MacGlass.rowFont)
                        .foregroundStyle(MacGlass.red)
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 16)
                .frame(height: MacGlass.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .wujiRowHover()
            .accessibilityIdentifier("wuji.settings.clearData")
        }
    }
    #endif

    // MARK: - Sections

    private var latencySection: some View {
        Section {
            NavigationLink(value: Route.testURL) {
                ValueRow(title: L10n.t("settings.latency.testURL", table: "Settings"),
                         value: SubscriptionFormat.host(app.settings.latencyTestURL),
                         interactive: PlatformFlags.isMacOS)
            }
            .accessibilityIdentifier("wuji.settings.testURL")

            NavigationLink(value: Route.timeout) {
                ValueRow(title: L10n.t("settings.latency.timeout", table: "Settings"),
                         value: secondsLabel(for: app.settings.latencyTimeout),
                         interactive: PlatformFlags.isMacOS)
            }
            .accessibilityIdentifier("wuji.settings.timeout")
        } header: {
            UppercaseSectionHeader(title: L10n.t("settings.latency.section", table: "Settings"))
        }
    }

    private var subscriptionsSection: some View {
        Section {
            Toggle(L10n.t("settings.autoUpdate"), isOn: Binding(
                get: { app.settings.subscriptionAutoUpdateEnabled },
                set: { newValue in
                    app.settings.subscriptionAutoUpdateEnabled = newValue
                    app.saveSettings()
                }
            ))
            .tint(Theme.green)
            .accessibilityIdentifier("wuji.settings.autoUpdate")

            NavigationLink(value: Route.subscriptionList) {
                ValueRow(title: L10n.t("settings.subscriptions"),
                         value: "\(app.subscriptions.count)",
                         interactive: PlatformFlags.isMacOS)
            }
            .accessibilityIdentifier("wuji.settings.subscriptions")
        } header: {
            UppercaseSectionHeader(title: L10n.t("settings.section.subscriptions"))
        } footer: {
            Text(L10n.t("settings.subscriptions.footnote", table: "Settings"))
        }
    }

    private var geoIPSection: some View {
        Section {
            ValueRow(title: L10n.t("settings.geoip.status", table: "Settings"),
                     value: geoIPStatusText)
                .accessibilityIdentifier("wuji.settings.geoipStatus")

            Button {
                Task { await runGeoIPUpdate() }
            } label: {
                HStack {
                    Text(L10n.t("settings.geoip.updateNow", table: "Settings"))
                        .foregroundStyle(Theme.tint)
                    Spacer()
                    if geoIPUpdating { ProgressView() }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(geoIPUpdating)
            .accessibilityIdentifier("wuji.settings.geoipUpdate")
        } header: {
            UppercaseSectionHeader(title: L10n.t("settings.geoip.section", table: "Settings"))
        } footer: {
            Text(geoIPFootnote)
        }
    }

    private var geoIPStatusText: String {
        if let updated = geoIPStatus.lastUpdatedAt {
            return updated.formatted(date: .abbreviated, time: .omitted)
        }
        if let generated = geoIPStatus.generated, !generated.isEmpty {
            return generated
        }
        if let version = geoIPStatus.dataVersion, !version.isEmpty {
            return version
        }
        return "—"
    }

    private var geoIPFootnote: String {
        var text = L10n.t("settings.geoip.footnote", table: "Settings")
        if let error = geoIPStatus.lastError, !error.isEmpty {
            text += "\n\n" + String(format: L10n.t("settings.geoip.error", table: "Settings"), error)
        }
        return text
    }

    @MainActor
    private func runGeoIPUpdate() async {
        geoIPUpdating = true
        let success = await GeoIPUpdater.shared.manualUpdate()
        geoIPUpdating = false
        geoIPStatus = GeoIPUpdater.shared.status
        toast = success
            ? L10n.t("settings.geoip.updateSuccess", table: "Settings")
            : L10n.t("settings.geoip.updateFailure", table: "Settings")
    }

    /// Language menu: "Follow System" as a direct option, the current language
    /// shown as a value row, and a secondary picker with all 11 supported languages.
    private var languageSection: some View {
        Section {
            Button {
                selectLanguage(.system)
            } label: {
                HStack(spacing: 12) {
                    Text(L10n.t("settings.language.followSystem", table: "Settings"))
                        .font(Theme.body)
                        .foregroundStyle(PlatformFlags.interactiveTitleColor)
                    Spacer(minLength: 8)
                    if app.settings.appLanguage == .system {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.tint)
                    }
                }
                .contentShape(Rectangle())
                .wujiRowHover()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wuji.settings.language.followSystem")

            NavigationLink(value: Route.languagePicker) {
                ValueRow(title: L10n.t("settings.language.current", table: "Settings"),
                         value: currentLanguageName,
                         interactive: PlatformFlags.isMacOS)
            }
            .accessibilityIdentifier("wuji.settings.language.chooseAnother")
        } header: {
            UppercaseSectionHeader(title: L10n.t("settings.language.section", table: "Settings"))
        } footer: {
            Text(L10n.t("settings.language.footnote", table: "Settings"))
        }
    }

    /// Effective language shown in the menu: when following the system this shows
    /// the resolved device language next to "Follow System".
    private var currentLanguageName: String {
        if app.settings.appLanguage == .system {
            let resolved = AppLanguage.matching(code: L10n.currentLanguageCode) ?? .english
            return "\(L10n.t("settings.language.followSystem", table: "Settings")) · \(resolved.nativeName)"
        }
        return app.settings.appLanguage.nativeName
    }

    /// App language is applied immediately: the override is set before the settings
    /// mutation so the view tree re-created by `RootView`'s `.id` renders in the
    /// selected language, then the choice is persisted through `saveSettings()`.
    private func selectLanguage(_ language: AppLanguage) {
        guard app.settings.appLanguage != language else { return }
        L10n.overrideLanguage = language.localeIdentifier
        app.settings.appLanguage = language
        app.saveSettings()
    }

    private var supportSection: some View {        Section {
            NavigationLink(value: Route.about) {
                Text(L10n.t("settings.about"))
                    .wujiNavigationRow(chevron: false)
            }
            .accessibilityIdentifier("wuji.settings.about")

            Button {
                openSupportEmail()
            } label: {
                HStack(spacing: 8) {
                    Text(L10n.t("settings.contact"))
                        .font(Theme.body)
                        .foregroundStyle(PlatformFlags.interactiveTitleColor)
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.tertiaryLabel)
                }
                .contentShape(Rectangle())
                .wujiRowHover()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wuji.settings.contact")

            NavigationLink(value: Route.terms) {
                Text(L10n.t("settings.terms"))
                    .wujiNavigationRow(chevron: false)
            }
            .accessibilityIdentifier("wuji.settings.terms")

            NavigationLink(value: Route.privacy) {
                Text(L10n.t("settings.privacy"))
                    .wujiNavigationRow(chevron: false)
            }
            .accessibilityIdentifier("wuji.settings.privacy")
        } header: {
            UppercaseSectionHeader(title: L10n.t("settings.section.support"))
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                confirmation = clearDataRequest()
            } label: {
                Text(L10n.t("settings.clearData"))
                    .font(Theme.body)
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wuji.settings.clearData")
        } header: {
            UppercaseSectionHeader(title: L10n.t("settings.section.data", table: "Settings"))
        }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .subscriptionList:
            SubscriptionListView()
        case .subscriptionDetail(let id):
            SubscriptionDetailView(subscriptionID: id)
        case .testURL:
            LatencyTestURLView()
        case .timeout:
            LatencyTimeoutView()
        case .about:
            AboutView()
        case .languagePicker:
            LanguagePickerView()
        case .licenses:
            LicensesView()
        case .terms:
            LegalDocumentView(kind: .terms)
        case .privacy:
            LegalDocumentView(kind: .privacy)
        case .routing:
            RoutingSettingsView(embeddedInNavigation: true)
        }
    }

    // MARK: - Actions

    private func openSupportEmail() {
        guard let url = URL(string: "mailto:\(Self.supportEmail)") else { return }
        PlatformSystem.open(url)
    }

    private func resetVPNRequest() -> ConfirmationRequest {
        ConfirmationRequest(title: L10n.t("settings.resetVPN.title", table: "Settings"),
                            message: L10n.t("settings.resetVPN.body", table: "Settings"),
                            confirmTitle: L10n.t("settings.resetVPN.confirm", table: "Settings")) {
            Task { @MainActor in
                let success = await app.resetVPNConfiguration()
                toast = success
                    ? L10n.t("settings.resetVPN.success", table: "Settings")
                    : (app.banner ?? L10n.t("settings.resetVPN.failure", table: "Settings"))
            }
        }
    }

    private func clearDataRequest() -> ConfirmationRequest {
        ConfirmationRequest(title: L10n.t("settings.clearData.title", table: "Settings"),
                            message: L10n.t("settings.clearData.body", table: "Settings"),
                            confirmTitle: L10n.t("settings.clearData")) {
            Task { await clearAllData() }
        }
    }

    /// A4 (audit): clearing the data has to be a real reset. The system VPN
    /// configuration is removed first (it must not outlive the node data), then the
    /// database is wiped in one transaction, and only then does the app return to
    /// its first-run state. The success toast is shown before the onboarding gate
    /// takes over so the user gets a confirmation either way.
    private func clearAllData() async {
        let vpnReset = await app.resetVPNConfiguration()
        guard vpnReset else {
            toast = app.banner ?? L10n.t("settings.resetVPN.failure", table: "Settings")
            return
        }
        do {
            try app.db.deleteAllData()
            toast = L10n.t("settings.clearData.success", table: "Settings")
            // Give the toast a moment to appear; setting `settings` back to the
            // defaults makes RootView switch to the onboarding flow.
            try? await Task.sleep(nanoseconds: 900_000_000)
            // The language setting is part of the wiped data: drop the override
            // before the root view rebuilds so the onboarding flow uses the system
            // language again.
            L10n.overrideLanguage = AppLanguage.system.localeIdentifier
            app.settings = .default
            app.reload()
        } catch {
            toast = error.localizedDescription
        }
    }

    // MARK: - Labels

    private func secondsLabel(for interval: TimeInterval) -> String {
        String(format: L10n.t("settings.latency.seconds", table: "Settings"), Int(interval))
    }

    // MARK: - Screenshot harness

    #if DEBUG
    /// DEBUG-only screenshot harness for the language section (task-10).
    /// `-WujiScreenshotRoute language` scrolls the list to the language rows;
    /// `-WujiScreenshotRoute language-switch` runs the same action as tapping
    /// "English" so screenshots can show the instant in-app switch.
    private func applyLanguageScreenshotHarness(_ proxy: ScrollViewProxy) async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-WujiScreenshotRoute"),
              index + 1 < arguments.count else { return }
        switch arguments[index + 1] {
        case "language":
            try? await Task.sleep(nanoseconds: 600_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo("settings.language.section", anchor: .center)
            }
        case "language-switch":
            try? await Task.sleep(nanoseconds: 900_000_000)
            selectLanguage(.english)
        default:
            break
        }
    }

    /// DEBUG-only: `-WujiScreenshotRoute <route>` opens a page directly so screenshots can
    /// be captured on headless simulators (no Simulator.app UI available).
    private func applyScreenshotRouteIfNeeded() {
        guard !didApplyScreenshotRoute else { return }
        didApplyScreenshotRoute = true
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-WujiScreenshotRoute"),
              index + 1 < arguments.count else { return }
        switch arguments[index + 1] {
        case "subscriptions":
            path.append(Route.subscriptionList)
        case "subscriptions-delete-confirm":
            path.append(Route.subscriptionList)
        case "subscription-detail", "subscription-nodes", "subscription-edit":
            path.append(Route.subscriptionList)
            if let id = app.subscriptions.first?.id {
                path.append(Route.subscriptionDetail(id))
            }
        case "subscription-add":
            showAddSubscription = true
        case "reset-confirm":
            confirmation = resetVPNRequest()
        case "clear-confirm":
            confirmation = clearDataRequest()
        case "routing-pushed":
            path.append(Route.routing)
        case "routing", "regions":
            showRoutingSheet = true
        case "test-url":
            path.append(Route.testURL)
        case "timeout":
            path.append(Route.timeout)
        case "about":
            path.append(Route.about)
        case "licenses":
            path.append(Route.licenses)
        case "terms":
            path.append(Route.terms)
        case "privacy":
            path.append(Route.privacy)
        default:
            break
        }
    }
    #endif
}
