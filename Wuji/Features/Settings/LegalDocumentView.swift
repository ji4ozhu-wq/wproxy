import SwiftUI

/// Legal document page (spec §5.13/§5.14, design reference `N-legal`).
/// Renders the bilingual Markdown bundled in `Wuji/Resources/{terms,privacy}-{en,zh}.md`
/// as native inset cards. The document follows the in-app language (Settings → Language):
/// `LegalDocumentLoader` picks the matching file, and the root view is re-created when
/// the language changes, so this page re-renders in the new language.
struct LegalDocumentView: View {
    let kind: LegalDocumentKind

    @State private var document: LegalDocument?
    @State private var didFail = false

    var body: some View {
        Group {
            if let document {
                content(document)
            } else if didFail {
                failureState
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
        }
        .navigationTitle(kind.title)
        .wujiInlineNavigationTitle()
        .wujiHiddenTabBar()
        .task {
            loadIfNeeded()
        }
    }

    // MARK: - Content

    private func content(_ document: LegalDocument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard(document)
                ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                    sectionCard(section)
                }
            }
            .padding(.horizontal, Theme.hMargin)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .wujiMacContentWidth(820)
        }
        .background(Theme.background)
        .accessibilityIdentifier("wuji.settings.legal.scroll")
    }

    private func headerCard(_ document: LegalDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(document.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)
            if let effectiveDate = document.effectiveDate {
                Text(String(format: L10n.t("settings.legal.effectiveDate", table: "Settings"), effectiveDate))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            if !document.preamble.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(document.preamble.enumerated()), id: \.offset) { _, block in
                        preambleView(block)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// Metadata lines between the title and the first section (operator, contact...).
    @ViewBuilder
    private func preambleView(_ block: LegalDocument.Block) -> some View {
        switch block {
        case .paragraph(let text):
            Text(LegalDocument.attributedString(for: text))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                Text(LegalDocument.attributedString(for: text))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sectionCard(_ section: LegalDocument.Section) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.heading)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(section.blocks.enumerated()), id: \.offset) { index, block in
                if index > 0 {
                    Divider()
                }
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private func blockView(_ block: LegalDocument.Block) -> some View {
        switch block {
        case .paragraph(let text):
            paragraphView(text)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.body)
                    .foregroundStyle(Theme.secondaryLabel)
                Text(LegalDocument.attributedString(for: text))
                    .font(.body)
                    .foregroundStyle(Theme.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func paragraphView(_ text: String) -> some View {
        if let email = LegalDocument.firstEmail(in: text) {
            let remaining = text.replacingOccurrences(of: email, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            VStack(alignment: .leading, spacing: 6) {
                if !remaining.isEmpty {
                    Text(LegalDocument.attributedString(for: remaining))
                        .font(.body)
                        .foregroundStyle(Theme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Link(email, destination: URL(string: "mailto:\(email)") ?? URL(string: "mailto:")!)
                    .font(.body)
                    .accessibilityIdentifier("wuji.settings.legal.email")
            }
        } else {
            Text(LegalDocument.attributedString(for: text))
                .font(.body)
                .foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - States

    private var failureState: some View {
        EmptyStateView(symbol: "doc.text.magnifyingglass",
                       title: L10n.t("settings.legal.unavailableTitle", table: "Settings"),
                       message: L10n.t("settings.legal.unavailableMessage", table: "Settings"),
                       primaryTitle: L10n.t("settings.legal.retry", table: "Settings"),
                       primaryAction: {
                           didFail = false
                           document = nil
                           loadIfNeeded()
                       })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .accessibilityIdentifier("wuji.settings.legal.error")
    }

    private func loadIfNeeded() {
        guard document == nil, !didFail else { return }
        if let loaded = LegalDocumentLoader.load(kind: kind) {
            document = loaded
        } else {
            didFail = true
        }
    }
}
