import SwiftUI

// MARK: - Latency test URL

/// Editable latency-test URL (spec §5.11). Validates the URL before saving and pops back.
struct LatencyTestURLView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    init() {
        _text = State(initialValue: "")
    }

    var body: some View {
        List {
            Section {
                TextField("https://", text: $text)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit { save() }
                    .accessibilityIdentifier("wuji.settings.latency.urlField")
            } footer: {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                } else {
                    Text(L10n.t("settings.latency.testURLFootnote", table: "Settings"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.t("settings.latency.testURLTitle", table: "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L10n.t("common.save")) { save() }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("wuji.settings.latency.save")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.t("common.done")) { isFocused = false }
            }
        }
        .onAppear {
            if text.isEmpty {
                text = app.settings.latencyTestURL
            }
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            errorMessage = L10n.t("settings.latency.testURLInvalid", table: "Settings")
            return
        }
        app.settings.latencyTestURL = url.absoluteString
        app.saveSettings()
        isFocused = false
        dismiss()
    }
}
