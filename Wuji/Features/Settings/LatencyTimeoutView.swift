import SwiftUI

// MARK: - Latency timeout

/// Latency-test timeout picker (spec §5.11). Selection saves immediately and pops back.
struct LatencyTimeoutView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    private let options: [TimeInterval] = [3, 5, 8, 10, 15]

    var body: some View {
        List {
            Section {
                ForEach(options, id: \.self) { seconds in
                    Button {
                        app.settings.latencyTimeout = seconds
                        app.saveSettings()
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text(label(for: seconds))
                                .font(Theme.body)
                                .foregroundStyle(Theme.label)
                            Spacer(minLength: 8)
                            if app.settings.latencyTimeout == seconds {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wuji.settings.timeout.option.\(Int(seconds))")
                }
            } footer: {
                Text(L10n.t("settings.latency.timeoutFootnote", table: "Settings"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.t("settings.latency.timeoutTitle", table: "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func label(for seconds: TimeInterval) -> String {
        String(format: L10n.t("settings.latency.seconds", table: "Settings"), Int(seconds))
    }
}
