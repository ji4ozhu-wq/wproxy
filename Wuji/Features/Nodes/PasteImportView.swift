import SwiftUI

/// Result of one paste import. The importing screen hands it back to the node list,
/// which shows it as a summary toast: imported / duplicates skipped / unreadable.
struct PasteImportSummary: Equatable {
    var imported: Int
    var duplicates: Int
    var unreadable: Int
    var warnings: Int

    var message: String {
        var text = String(format: L10n.t("nodes.import.summary", table: "Nodes"),
                          imported, duplicates, unreadable)
        if warnings > 0 {
            text += " · " + String(format: L10n.t("nodes.import.warningsCount", table: "Nodes"), warnings)
        }
        return text
    }
}

/// Clipboard import (spec §5.6): multi-line links, recognized preview, batch save.
struct PasteImportView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    var initialText: String?
    /// Called right before the sheet dismisses after a successful import.
    var onImport: ((PasteImportSummary) -> Void)?

    @State private var text = ""
    @State private var report = URIParseReport()
    @State private var duplicateIDs: Set<String> = []
    @State private var selectedIDs: Set<String> = []
    @State private var parseError: String?
    @State private var importing = false
    @State private var didPrefill = false

    private var recognized: [NodeProfile] { report.profiles }
    private var warningsByNodeID: [String: URIParseWarning] { report.warningsByNodeID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.label)
                    .frame(minHeight: 168)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(L10n.t("nodes.paste.placeholder", table: "Nodes"))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(Theme.tertiaryLabel)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityIdentifier("wuji.nodes.paste.editor")

                if let parseError {
                    Label(parseError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .accessibilityIdentifier("wuji.nodes.paste.error")
                }

                if recognized.isEmpty {
                    Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? L10n.t("nodes.paste.emptyHint", table: "Nodes")
                         : L10n.t("nodes.paste.noLinks", table: "Nodes"))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                } else {
                    recognizedList
                }

                if !report.failures.isEmpty {
                    failuresList
                }

                Text(L10n.t("nodes.paste.footer", table: "Nodes"))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, Theme.hMargin)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle(L10n.t("nodes.paste.title", table: "Nodes"))
        .wujiInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .wujiLeading) {
                Button(L10n.t("common.cancel")) { dismiss() }
                    .accessibilityIdentifier("wuji.nodes.paste.cancelButton")
            }
            ToolbarItem(placement: .wujiTrailing) {
                Button(L10n.t("nodes.paste.import", table: "Nodes")) {
                    importSelected()
                }
                .disabled(selectedIDs.isEmpty || importing)
                .accessibilityIdentifier("wuji.nodes.paste.importButton")
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: importButtonTitle, isLoading: importing) {
                importSelected()
            }
            .disabled(selectedIDs.isEmpty || importing)
            .opacity(selectedIDs.isEmpty ? 0.4 : 1)
            .accessibilityIdentifier("wuji.nodes.paste.primaryButton")
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Theme.background)
        }
        .onAppear(perform: configureFromDebugArguments)
        .onAppear(perform: prefillIfNeeded)
        .onChange(of: text) { _, newValue in
            parse(newValue)
        }
        .wujiMacSheetActions(onCancel: { dismiss() })
    }

    // MARK: - Recognized list

    private var recognizedList: some View {
        VStack(spacing: 0) {
            ForEach(Array(recognized.enumerated()), id: \.element.id) { index, profile in
                if index > 0 {
                    Divider().padding(.leading, 16)
                }
                recognizedRow(profile)
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func recognizedRow(_ profile: NodeProfile) -> some View {
        let duplicate = duplicateIDs.contains(profile.id)
        let selected = selectedIDs.contains(profile.id)
        let warning = warningsByNodeID[profile.id]
        return Button {
            guard !duplicate else { return }
            toggle(profile)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.label)
                            .lineLimit(1)
                        Text("\(profile.proto.shortBadge) · \(profile.endpoint)")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryLabel)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if duplicate {
                        Text(L10n.t("nodes.import.duplicate", table: "Nodes"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondaryLabel)
                    } else {
                        Image(systemName: selected ? "checkmark" : "plus.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(selected ? Theme.green : Theme.secondaryLabel)
                    }
                }
                if let warning {
                    Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("wuji.nodes.paste.warning.\(profile.id)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(duplicate)
        .accessibilityLabel("\(profile.displayName), \(profile.proto.shortBadge), \(profile.endpoint)")
        .accessibilityValue(duplicate
                            ? L10n.t("nodes.import.duplicate", table: "Nodes")
                            : (selected ? L10n.t("consent.checked", table: "Nodes") : ""))
        .accessibilityIdentifier("wuji.nodes.paste.row.\(profile.id)")
    }

    // MARK: - Unreadable lines

    private var failuresList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: L10n.t("nodes.import.failuresTitle", table: "Nodes"), report.failures.count))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.red)
            ForEach(Array(report.failures.enumerated()), id: \.offset) { _, failure in
                VStack(alignment: .leading, spacing: 2) {
                    Text(failure.line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(2)
                    Text(failure.message)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityIdentifier("wuji.nodes.paste.failures")
    }

    // MARK: - Helpers

    private var importButtonTitle: String {
        let count = selectedIDs.count
        if count == 1 { return L10n.t("nodes.paste.import.one", table: "Nodes") }
        return String(format: L10n.t("nodes.paste.import.many", table: "Nodes"), count)
    }

    private func toggle(_ profile: NodeProfile) {
        if selectedIDs.contains(profile.id) {
            selectedIDs.remove(profile.id)
        } else {
            selectedIDs.insert(profile.id)
        }
    }

    /// Parses the editor text and marks recognized nodes that already exist — either
    /// in the app or earlier in the same paste — so they are skipped on import.
    private func parse(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            report = URIParseReport()
            duplicateIDs = []
            selectedIDs = []
            parseError = nil
            return
        }
        let parsed = app.uriParser.parseDetailed(trimmed, groupID: ProfileStore.manualGroupID)
        report = parsed

        var duplicates: Set<String> = []
        var fresh: [NodeProfile] = []
        for profile in parsed.profiles {
            let matchesExisting = app.nodes.contains { app.uriParser.isDuplicate(profile, of: $0) }
            let matchesBatch = fresh.contains { app.uriParser.isDuplicate(profile, of: $0) }
            if matchesExisting || matchesBatch {
                duplicates.insert(profile.id)
            } else {
                fresh.append(profile)
            }
        }
        duplicateIDs = duplicates
        selectedIDs = Set(fresh.map(\.id))
        parseError = parsed.profiles.isEmpty
            ? L10n.t("nodes.paste.noLinks", table: "Nodes")
            : nil
    }

    private func configureFromDebugArguments() {
        #if DEBUG
        guard DebugScreenshotRoute.value("-WujiScreenshotAction") == "import" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { importSelected() }
        #endif
    }

    private func prefillIfNeeded() {
        guard !didPrefill else { return }
        didPrefill = true
        if let initialText, !initialText.isEmpty {
            text = initialText
            parse(initialText)
            return
        }
        #if DEBUG
        // The screenshot harness launches straight into this page; don't trigger the
        // system paste prompt for a purely visual check.
        if DebugScreenshotRoute.value("-WujiScreenshotPage") != nil { return }
        #endif
        if let clipboard = PlatformPasteboard.string, !clipboard.isEmpty {
            text = clipboard
            parse(clipboard)
        }
    }

    private func importSelected() {
        guard !importing else { return }
        let profiles = recognized.filter { selectedIDs.contains($0.id) }
        guard !profiles.isEmpty else { return }
        importing = true
        app.addProfiles(profiles, groupID: ProfileStore.manualGroupID)
        importing = false
        let warnings = profiles.reduce(into: 0) { count, profile in
            if warningsByNodeID[profile.id] != nil { count += 1 }
        }
        let summary = PasteImportSummary(imported: profiles.count,
                                         duplicates: duplicateIDs.count,
                                         unreadable: report.failures.count,
                                         warnings: warnings)
        onImport?(summary)
        dismiss()
    }
}
