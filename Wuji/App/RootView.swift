import SwiftUI

enum Tab: Hashable {
    case connect, nodes, settings
}

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @State private var selectedTab: Tab = RootView.initialTab
    @State private var splitSelection: Tab? = RootView.initialTab

    /// DEBUG-only launch argument used by screenshot/UI-test tooling: `-WujiTab connect|nodes|settings`.
    static var initialTab: Tab {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-WujiTab"), index + 1 < arguments.count {
            switch arguments[index + 1] {
            case "settings": return .settings
            case "nodes": return .nodes
            default: return .connect
            }
        }
        #endif
        return .connect
    }

    var body: some View {
        Group {
            if !app.settings.onboardingDone {
                OnboardingView()
            } else if !app.settings.networkPermissionPassed {
                NetworkPermissionView()
            } else if !app.settings.consentAccepted {
                ConsentView()
            } else {
                GeometryReader { proxy in
                    if proxy.size.width >= 700 {
                        splitLayout
                    } else {
                        tabLayout
                    }
                }
            }
        }
        // App language (Settings → Language): re-create every screen so all view
        // bodies run again with the refreshed `L10n` override, and propagate the
        // matching locale so dates/numbers follow the selected language too.
        .id(app.settings.appLanguage)
        .environment(\.locale, L10n.currentLocale)
        .wujiToast(Binding(
            get: { app.toastMessage },
            set: { app.toastMessage = $0 }
        ))
        .onChange(of: app.settings.appLanguage) { _, newValue in
            L10n.overrideLanguage = newValue.localeIdentifier
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            app.reload()
            Task {
                await app.syncTunnelSystemState()
                await app.autoUpdateSubscriptionsIfNeeded()
            }
        }
    }

    // Compact: native tab bar (iPhone portrait / SE)
    private var tabLayout: some View {
        TabView(selection: $selectedTab) {
            HomeView(onNavigate: { selectedTab = $0 })
                .tabItem { Label(L10n.t("tab.connect"), systemImage: "power") }
                .tag(Tab.connect)
            NodeListView()
                .tabItem { Label(L10n.t("tab.nodes"), systemImage: "list.bullet.rectangle") }
                .tag(Tab.nodes)
            SettingsView()
                .tabItem { Label(L10n.t("tab.settings"), systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(Theme.tint)
    }

    // Regular: iPad / iPhone Duo unfolded — sidebar + detail
    private var splitLayout: some View {
        NavigationSplitView {
            List(selection: $splitSelection) {
                Label(L10n.t("tab.connect"), systemImage: "power").tag(Tab.connect)
                Label(L10n.t("tab.nodes"), systemImage: "list.bullet.rectangle").tag(Tab.nodes)
                Label(L10n.t("tab.settings"), systemImage: "gearshape").tag(Tab.settings)
            }
            .navigationTitle("Wuji")
        } detail: {
            switch splitSelection ?? .connect {
            case .connect:
                HomeView(onNavigate: { splitSelection = $0 })
            case .nodes:
                NodeListView()
            case .settings:
                SettingsView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.tint)
    }
}
