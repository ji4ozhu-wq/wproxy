import SwiftUI
import UIKit

/// First-run network permission gate, shown after the onboarding pages and before the
/// consent screen. Requests Local Network + VPN Configuration; failures keep the user
/// here with instructions until the permissions are granted.
struct NetworkPermissionView: View {
    @EnvironmentObject private var app: AppState
    @State private var phase: Phase = .requesting

    private enum Phase: Equatable {
        case requesting
        case failed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: phase == .requesting ? "network" : "wifi.exclamationmark")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(phase == .requesting ? Theme.tint : Theme.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 48)

                VStack(alignment: .leading, spacing: 12) {
                    Text(phase == .requesting
                         ? L10n.t("permission.network.title")
                         : L10n.t("permission.network.failed.title"))
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.label)
                        .accessibilityIdentifier(phase == .requesting
                                                 ? "wuji.permission.title"
                                                 : "wuji.permission.failedTitle")

                    Text(phase == .requesting
                         ? L10n.t("permission.network.body")
                         : L10n.t("permission.network.failed.body"))
                        .font(Theme.body)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("wuji.permission.body")
                }

                if phase == .requesting {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(L10n.t("permission.network.requesting"))
                            .font(Theme.body)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .accessibilityIdentifier("wuji.permission.requesting")
                } else {
                    VStack(spacing: 12) {
                        Button {
                            Task { await request() }
                        } label: {
                            Text(L10n.t("permission.network.retry"))
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.white)
                                .background(Theme.tint)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wuji.permission.retry")

                        Button {
                            openSystemSettings()
                        } label: {
                            Text(L10n.t("permission.network.openSettings"))
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(Theme.label)
                                .background(Color(.secondarySystemFill))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wuji.permission.openSettings")
                    }
                }

                Text(L10n.t("permission.network.note"))
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wuji.permission.note")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.hMargin)
            .padding(.bottom, 32)
        }
        .background(Theme.background)
        .accessibilityIdentifier("wuji.permission.screen")
        .task {
            await request()
        }
    }

    private func request() async {
        phase = .requesting
        let granted = await NetworkPermissionRequester.shared.requestAll()
        guard !granted else {
            app.settings.networkPermissionPassed = true
            app.saveSettings()
            return
        }
        phase = .failed
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
