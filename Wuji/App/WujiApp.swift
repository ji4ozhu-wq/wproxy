import SwiftUI

@main
struct WujiApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacWindowDelegate.self) private var appDelegate
    #endif

    @StateObject private var appState = AppState.shared

    init() {
        // Apply the persisted in-app language (Settings → Language) before the first
        // view is built, so a relaunch does not flash the device language first.
        // `nil` keeps the previous behaviour of following the system language.
        L10n.overrideLanguage = AppState.shared.settings.appLanguage.localeIdentifier
        // Country/region names follow the in-app language (and the Chinese labels use
        // "中国台湾 / 中国香港 / 中国澳门").
        CountryDirectory.shared.setPreferredLanguageCode(L10n.currentLanguageCode)
    }

    var body: some Scene {
        #if os(macOS)
        // A single main window (not WindowGroup): this app is not document based and
        // must always show its window at launch, even after macOS saved a "no windows"
        // state when the user closed it before quitting.
        Window("app.name", id: "main") {
            rootContent
        }
        .wujiMacWindowScene()
        #else
        WindowGroup {
            rootContent
        }
        #endif
    }

    private var rootContent: some View {
        RootView()
            .environmentObject(appState)
            .environmentObject(appState.sessionStatsModel)
            .preferredColorScheme(.light)
            .onChange(of: appState.settings.appLanguage) { _, newValue in
                // Keep the global override in sync with the setting. RootView also
                // re-creates its content when the value changes, which re-runs every
                // body with the new language.
                L10n.overrideLanguage = newValue.localeIdentifier
                CountryDirectory.shared.setPreferredLanguageCode(L10n.currentLanguageCode)
            }
    }
}


#if os(macOS)
/// macOS keeps restoring "no windows" state after a window was closed when the app
/// quit, which can leave the app running without any window. Reopen the main window
/// on launch/activation when nothing is visible.
final class MacWindowDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            MenuBarController.shared.start()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.openWindowIfNeeded()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openWindowIfNeeded()
        }
        return true
    }

    private func openWindowIfNeeded() {
        let visible = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        guard !visible else { return }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("newWindow:")), to: nil, from: nil)
    }
}
#endif
