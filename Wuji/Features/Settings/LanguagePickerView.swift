import SwiftUI

/// Secondary language list opened from Settings → Language.
/// Lists every supported language with its endonym + English name; the selected
/// language is persisted immediately and the app rebuilds in that language.
struct LanguagePickerView: View {
    @EnvironmentObject private var app: AppState

    private var supportedLanguages: [AppLanguage] {
        AppLanguage.allCases.filter { $0 != .system }
    }

    var body: some View {
        WujiSettingsList {
            Section {
                ForEach(supportedLanguages, id: \.self) { language in
                    Button {
                        select(language)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.nativeName)
                                    .font(Theme.body)
                                    .foregroundStyle(Theme.label)
                                Text(language.englishName)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                            Spacer(minLength: 8)
                            if app.settings.appLanguage == language {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wuji.settings.language.option.\(language.rawValue)")
                }
            } footer: {
                Text(L10n.t("settings.language.footnote", table: "Settings"))
            }
        }
        .navigationTitle(L10n.t("settings.language.chooseAnother", table: "Settings"))
        .wujiInlineNavigationTitle()
        .accessibilityIdentifier("wuji.settings.language.picker")
    }

    private func select(_ language: AppLanguage) {
        guard app.settings.appLanguage != language else { return }
        L10n.overrideLanguage = language.localeIdentifier
        app.settings.appLanguage = language
        app.saveSettings()
    }
}
