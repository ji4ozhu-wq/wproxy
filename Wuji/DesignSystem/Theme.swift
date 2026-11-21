import Foundation
import SwiftUI

enum Theme {
    // Colors (system semantic, light theme only)
    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let label = Color(.label)
    static let secondaryLabel = Color(.secondaryLabel)
    static let tertiaryLabel = Color(.tertiaryLabel)
    static let tint = Color(.systemBlue)
    static let separator = Color(.separator)
    static let green = Color(.systemGreen)
    static let red = Color(.systemRed)
    static let orange = Color(.systemOrange)
    static let gray = Color(.systemGray)

    // Layout
    static let cardRadius: CGFloat = 12
    static let hMargin: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let buttonHeight: CGFloat = 50
    static let connectButtonSize: CGFloat = 190

    // Fonts
    static let largeTitle = Font.largeTitle.bold()
    static let title = Font.title2.bold()
    static let headline = Font.headline
    static let body = Font.body
    static let footnote = Font.footnote
    static let caption = Font.caption
    static let sectionHeader = Font.footnote
    static let buttonLabel = Font.body.weight(.semibold)
    static func mono(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }
}

/// Localization helper for the in-app language setting (Settings → Language).
///
/// `overrideLanguage` forces one of the bundled localizations (`"en"` / `"zh-Hans"`)
/// without restarting the app; when it is `nil` (default) the device language is used
/// exactly as before. `t(_:table:)` resolves the requested `.strings` table from the
/// matching `.lproj` bundle; that bundle is loaded lazily and cached.
enum L10n {
    /// Language codes that ship a `.lproj` folder in the app bundle.
    static let supportedLanguageCodes = ["en", "zh-Hans", "zh-Hant", "es", "fr", "de", "ja", "ko", "ru", "th", "vi"]

    /// Forced in-app language code, or `nil` to follow the device language.
    /// Changing it drops the cached `.lproj` bundles used by `t(_:table:)`.
    static var overrideLanguage: String? {
        didSet {
            guard overrideLanguage != oldValue else { return }
            bundleLock.lock()
            cachedBundles.removeAll()
            bundleLock.unlock()
        }
    }

    /// Language code the UI is currently rendered with (`"en"` / `"zh-Hans"`).
    static var currentLanguageCode: String {
        if let overrideLanguage, !overrideLanguage.isEmpty {
            return overrideLanguage
        }
        // The main bundle resolves the device language against the bundled
        // localizations; unsupported device languages fall back to en.
        let preferred = Bundle.main.preferredLocalizations
        return preferred.first(where: { supportedLanguageCodes.contains($0) }) ?? "en"
    }

    /// Locale for dates and numbers: follows the in-app language, else the device.
    static var currentLocale: Locale {
        if let overrideLanguage, !overrideLanguage.isEmpty {
            return Locale(identifier: overrideLanguage)
        }
        return Locale.current
    }

    /// `true` when the current UI language is Chinese.
    static var isChinese: Bool {
        currentLanguageCode.lowercased().hasPrefix("zh")
    }

    /// Returns the localized string, falling back to the key itself when missing.
    static func t(_ key: String, table: String = "Localizable") -> String {
        NSLocalizedString(key, tableName: table, bundle: localizedBundle(), value: key, comment: "")
    }

    // MARK: - Bundle cache

    private static let bundleLock = NSLock()
    private static var cachedBundles: [String: Bundle] = [:]

    /// Returns `Bundle.main` when following the system language, otherwise the cached
    /// bundle for the forced language's `.lproj` directory. Loading a `.lproj`
    /// directory as a bundle lets `NSLocalizedString` read that language's tables
    /// without touching the process-wide localization.
    private static func localizedBundle() -> Bundle {
        guard let code = overrideLanguage,
              supportedLanguageCodes.contains(code),
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        bundleLock.lock()
        if let cached = cachedBundles[code] {
            bundleLock.unlock()
            return cached
        }
        bundleLock.unlock()

        bundleLock.lock()
        cachedBundles[code] = bundle
        bundleLock.unlock()
        return bundle
    }
}
