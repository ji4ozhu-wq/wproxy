import XCTest
@testable import Wuji

/// In-app language switching (task-10): L10n override, settings persistence and the
/// legacy settings JSON that predates `appLanguage`.
final class LocalizationTests: XCTestCase {
    override func tearDown() {
        L10n.overrideLanguage = nil
        super.tearDown()
    }

    // MARK: - L10n override

    func testOverrideLanguageSwitchesMainTable() {
        L10n.overrideLanguage = "en"
        let english = L10n.t("tab.settings")
        L10n.overrideLanguage = "zh-Hans"
        let chinese = L10n.t("tab.settings")

        XCTAssertEqual(english, "Settings")
        XCTAssertEqual(chinese, "设置")
        XCTAssertNotEqual(english, chinese)
    }

    func testOverrideLanguageSwitchesSettingsTable() {
        L10n.overrideLanguage = "en"
        let english = L10n.t("settings.language.system", table: "Settings")
        L10n.overrideLanguage = "zh-Hans"
        let chinese = L10n.t("settings.language.system", table: "Settings")

        XCTAssertEqual(english, "Follow System")
        XCTAssertEqual(chinese, "跟随系统")
        XCTAssertNotEqual(english, chinese)
    }

    func testCurrentLanguageCodeAndChineseFlagFollowOverride() {
        L10n.overrideLanguage = "en"
        XCTAssertEqual(L10n.currentLanguageCode, "en")
        XCTAssertFalse(L10n.isChinese)

        L10n.overrideLanguage = "zh-Hans"
        XCTAssertEqual(L10n.currentLanguageCode, "zh-Hans")
        XCTAssertTrue(L10n.isChinese)
    }

    func testCurrentLocaleFollowsOverride() {
        L10n.overrideLanguage = "en"
        XCTAssertEqual(L10n.currentLocale.language.languageCode?.identifier, "en")

        L10n.overrideLanguage = "zh-Hans"
        XCTAssertEqual(L10n.currentLocale.language.languageCode?.identifier, "zh")
    }

    func testSwitchingBackToSystemClearsOverride() {
        L10n.overrideLanguage = "en"
        XCTAssertNotNil(L10n.overrideLanguage)

        L10n.overrideLanguage = nil
        XCTAssertNil(L10n.overrideLanguage)
        XCTAssertEqual(L10n.isChinese, L10n.currentLanguageCode.lowercased().hasPrefix("zh"))
    }

    func testUnsupportedOverrideFallsBackToMainBundle() {
        L10n.overrideLanguage = "it" // not a shipped language
        // The lookup falls back to the main bundle and never returns a bare key
        // for an existing string.
        XCTAssertNotEqual(L10n.t("tab.settings"), "tab.settings")
    }

    func testSupportedLanguageSetCoversAllConfiguredLanguages() {
        XCTAssertEqual(L10n.supportedLanguageCodes.count, 11)
        XCTAssertTrue(L10n.supportedLanguageCodes.contains("zh-Hant"))
        XCTAssertTrue(L10n.supportedLanguageCodes.contains("ja"))
        XCTAssertTrue(L10n.supportedLanguageCodes.contains("vi"))
        XCTAssertEqual(AppLanguage.allCases.filter { $0 != .system }.count, 11)
    }

    func testLanguageMatchingResolvesSystemCodes() {
        XCTAssertEqual(AppLanguage.matching(code: "en"), .english)
        XCTAssertEqual(AppLanguage.matching(code: "zh-hans"), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.matching(code: "zh-Hant"), .traditionalChinese)
        XCTAssertEqual(AppLanguage.matching(code: "zh-TW"), .traditionalChinese)
        XCTAssertEqual(AppLanguage.matching(code: "ja"), .japanese)
        XCTAssertNil(AppLanguage.matching(code: "it"))
    }

    func testEverySupportedLanguageLoadsTranslatedTables() {
        let sampleKeys = ["tab.settings", "home.routing", "home.download"]
        for code in L10n.supportedLanguageCodes {
            L10n.overrideLanguage = code
            for key in sampleKeys {
                let value = L10n.t(key)
                XCTAssertNotEqual(value, key, "\(code) is missing \(key)")
            }
            if code != "en" {
                XCTAssertNotEqual(L10n.t("tab.settings"), "Settings",
                                  "\(code) still falls back to English")
            }
        }
        L10n.overrideLanguage = nil
    }

    // MARK: - AppSettings persistence

    func testAppLanguageCodableRoundTrip() throws {
        var settings = AppSettings.default
        settings.appLanguage = .simplifiedChinese
        settings.bypassCountryCodes = ["CN", "JP"]
        settings.onDemandMode = .wifi

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.appLanguage, .simplifiedChinese)
        XCTAssertEqual(decoded.bypassCountryCodes, ["CN", "JP"])
        XCTAssertEqual(decoded.onDemandMode, .wifi)
    }

    func testLegacySettingsJSONWithoutAppLanguageDefaultsToSystem() throws {
        // Shape of the JSON written before `appLanguage` existed.
        let legacy = """
        {
          "routingMode": "global",
          "bypassLAN": false,
          "bypassCountryCodes": ["JP"],
          "onDemandMode": "wifi",
          "latencyTestURL": "https://example.com/generate_204",
          "latencyTimeout": 8,
          "subscriptionAutoUpdateEnabled": false,
          "onboardingDone": true,
          "consentAccepted": true,
          "firstConnectExplained": true,
          "sortField": "name",
          "sortAscending": false
        }
        """
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded.appLanguage, .system)
        XCTAssertEqual(decoded.routingMode, .global)
        XCTAssertFalse(decoded.bypassLAN)
        XCTAssertEqual(decoded.bypassCountryCodes, ["JP"])
        XCTAssertEqual(decoded.onDemandMode, .wifi)
        XCTAssertEqual(decoded.latencyTestURL, "https://example.com/generate_204")
        XCTAssertEqual(decoded.latencyTimeout, 8)
        XCTAssertFalse(decoded.subscriptionAutoUpdateEnabled)
        XCTAssertTrue(decoded.onboardingDone)
        XCTAssertTrue(decoded.consentAccepted)
        XCTAssertTrue(decoded.firstConnectExplained)
        XCTAssertEqual(decoded.sortField, "name")
        XCTAssertFalse(decoded.sortAscending)
    }

    func testSettingsStorePersistsAppLanguage() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wuji-i18n-\(UUID().uuidString).sqlite3")
        let db = AppDatabase(databaseURL: url)
        try db.openIfNeeded()
        let store = SettingsStore(db: db)

        var settings = AppSettings.default
        settings.appLanguage = .english
        try store.save(settings)

        XCTAssertEqual(store.load().appLanguage, .english)

        settings.appLanguage = .system
        try store.save(settings)
        XCTAssertEqual(store.load().appLanguage, .system)
    }
}
