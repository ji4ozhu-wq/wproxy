import SwiftUI

@main
struct WujiApp: App {
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
        WindowGroup {
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
}
