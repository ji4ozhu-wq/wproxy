import XCTest
@testable import Wuji

/// Every user-selectable setting must survive a relaunch. AppSettings is stored as
/// one JSON blob, so the round-trip and the "older blob without newer keys" case are
/// both covered here.
final class AppSettingsTests: XCTestCase {
    func testSettingsRoundTripKeepsNewOptions() throws {
        var settings = AppSettings.default
        settings.routingMode = .global
        settings.dnsMode = .local
        settings.appLanguage = .simplifiedChinese
        settings.bypassLAN = false
        settings.bypassCountryCodes = ["CN", "JP"]
        settings.onDemandMode = .wifi
        settings.latencyTestURL = "https://example.com/generate_204"
        settings.latencyTimeout = 9
        settings.subscriptionAutoUpdateEnabled = false
        settings.activeProfileID = "profile-1"
        settings.onboardingDone = true
        settings.consentAccepted = true
        settings.firstConnectExplained = true
        settings.sortField = "name"
        settings.sortAscending = false

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.dnsMode, .local)
        XCTAssertEqual(decoded.appLanguage, .simplifiedChinese)
    }

    func testLegacySettingsBlobKeepsExistingValuesAndDefaultsNewOnes() throws {
        // Settings written by a build before dnsMode/appLanguage existed.
        let legacy = """
        {"routingMode":"global","bypassLAN":false,"bypassCountryCodes":["CN"],
         "onDemandMode":"always","latencyTestURL":"https://example.com/x",
         "latencyTimeout":7,"subscriptionAutoUpdateEnabled":false,
         "activeProfileID":"abc","onboardingDone":true,"consentAccepted":true,
         "firstConnectExplained":true,"sortField":"added","sortAscending":false}
        """
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.routingMode, .global)
        XCTAssertEqual(decoded.bypassLAN, false)
        XCTAssertEqual(decoded.bypassCountryCodes, ["CN"])
        XCTAssertEqual(decoded.onDemandMode, .always)
        XCTAssertEqual(decoded.activeProfileID, "abc")
        XCTAssertEqual(decoded.sortField, "added")
        XCTAssertEqual(decoded.dnsMode, .proxyDoH, "New options default instead of wiping the blob")
        XCTAssertEqual(decoded.appLanguage, .system)
    }

    func testSettingsStorePersistsAcrossInstances() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wuji-settings-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let db = AppDatabase(databaseURL: url)
        var settings = AppSettings.default
        settings.dnsMode = .local
        settings.appLanguage = .english
        settings.routingMode = .global
        try SettingsStore(db: db).save(settings)

        let reloaded = AppDatabase(databaseURL: url)
        let loaded = SettingsStore(db: reloaded).load()
        XCTAssertEqual(loaded.dnsMode, .local)
        XCTAssertEqual(loaded.appLanguage, .english)
        XCTAssertEqual(loaded.routingMode, .global)
    }
}
