import SwiftUI

/// About screen (spec §5.12, design reference `N-about-licenses`).
struct AboutView: View {
    var body: some View {
        WujiSettingsList {
            Section {
                appHeader
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
            }
            Section {
                NavigationLink {
                    LicensesView()
                } label: {
                    Text(L10n.t("about.licenses"))
                        .wujiNavigationRow(chevron: false)
                }
                .accessibilityIdentifier("wuji.settings.about.openSource")
            }
            Section {
                Text(L10n.t("settings.about.copyright", table: "Settings"))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .navigationTitle(L10n.t("settings.about.title", table: "Settings"))
        .wujiInlineNavigationTitle()
        .wujiHiddenTabBar()
    }

    private var appHeader: some View {
        VStack(spacing: 8) {
            AppMarkBadge()
            Text(L10n.t("app.name"))
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.label)
            Text(versionText)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
                .monospacedDigit()
        }
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return String(format: L10n.t("settings.about.version", table: "Settings"), version, build)
    }

}

/// The real app icon from the asset catalog (`AppIconPreview`, a copy of the 1024
/// app icon because `AppIcon` itself cannot be looked up by name at runtime).
struct AppMarkBadge: View {
    var size: CGFloat = 88

    var body: some View {
        Image("AppIconPreview")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}
