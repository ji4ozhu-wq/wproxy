import Foundation

// MARK: - Document model

enum LegalDocumentKind {
    case terms
    case privacy

    var title: String {
        switch self {
        case .terms: return L10n.t("settings.terms")
        case .privacy: return L10n.t("settings.privacy")
        }
    }

    var resource: String {
        switch self {
        case .terms: return "terms"
        case .privacy: return "privacy"
        }
    }
}

struct LegalDocument {
    enum Block {
        case paragraph(String)
        case bullet(String)

        /// Markdown source of the block, so the renderer can keep inline styling.
        var markdown: String {
            switch self {
            case .paragraph(let text), .bullet(let text): return text
            }
        }
    }

    struct Section {
        var heading: String
        var blocks: [Block]
    }

    var title: String
    var effectiveDate: String?
    /// Paragraphs between the title and the first `##` heading (operator, contact...).
    var preamble: [Block]
    var sections: [Section]

    static func firstEmail(in text: String) -> String? {
        guard let range = text.range(of: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
                                    options: .regularExpression) else { return nil }
        return String(text[range])
    }

    /// Renders the inline Markdown the docs use (`**bold**`) as styled text. The
    /// surrounding layout (headings, cards, bullets) is already native, so only
    /// inline spans are interpreted and whitespace is preserved.
    static func attributedString(for markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: markdown, options: options) {
            return attributed
        }
        return AttributedString(markdown)
    }
}

enum LegalDocumentLoader {
    /// Loads the Markdown matching the current in-app language (Settings → Language):
    /// `zh` when Chinese is active, `en` otherwise (also the fallback when following
    /// the system language).
    static func load(kind: LegalDocumentKind) -> LegalDocument? {
        // Legal documents are only maintained in English and Simplified Chinese;
        // every other in-app language (including Traditional Chinese) opens English.
        let language = L10n.currentLanguageCode == "zh-Hans" ? "zh" : "en"
        guard let url = Bundle.main.url(forResource: "\(kind.resource)-\(language)", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return parse(text)
    }

    static func parse(_ text: String) -> LegalDocument {
        var title = ""
        var effectiveDate: String?
        var preamble: [LegalDocument.Block] = []
        var sections: [LegalDocument.Section] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("## ") {
                sections.append(LegalDocument.Section(heading: String(line.dropFirst(3)), blocks: []))
                continue
            }
            if line.hasPrefix("# ") {
                title = String(line.dropFirst(2))
                continue
            }
            // Metadata uses bold Markdown (`**Effective date:** ...`), so detect it on
            // the plain text while keeping the Markdown for the body blocks.
            let plain = line.replacingOccurrences(of: "**", with: "")
            if let value = effectiveDateValue(from: plain) {
                effectiveDate = value
                continue
            }
            let block: LegalDocument.Block = line.hasPrefix("- ")
                ? .bullet(String(line.dropFirst(2)))
                : .paragraph(line)
            if sections.isEmpty {
                preamble.append(block)
            } else {
                sections[sections.count - 1].blocks.append(block)
            }
        }
        return LegalDocument(title: title,
                             effectiveDate: effectiveDate,
                             preamble: preamble,
                             sections: sections)
    }

    private static func effectiveDateValue(from line: String) -> String? {
        let prefixes = ["Effective date:", "Effective Date:", "生效日期：", "生效日期:"]
        for prefix in prefixes where line.hasPrefix(prefix) {
            let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
