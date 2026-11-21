import XCTest
@testable import Wuji

final class SmokeTests: XCTestCase {
    func testSettingsRoundTrip() throws {
        let db = AppDatabase(databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent("wuji-test-\(UUID().uuidString).sqlite3"))
        try db.openIfNeeded()
        let store = SettingsStore(db: db)
        var settings = AppSettings.default
        settings.bypassLAN = false
        settings.bypassCountryCodes = ["CN", "JP"]
        try store.save(settings)
        let loaded = store.load()
        XCTAssertEqual(loaded.bypassLAN, false)
        XCTAssertEqual(loaded.bypassCountryCodes, ["CN", "JP"])
    }

    func testProfileStoreRoundTrip() throws {
        let db = AppDatabase(databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent("wuji-test-\(UUID().uuidString).sqlite3"))
        try db.openIfNeeded()
        let store = ProfileStore(db: db)
        let group = try store.ensureManualGroup()
        var profile = NodeProfile(id: UUID().uuidString, groupID: group.id, name: "Tokyo-01", proto: .vless,
                                  server: "203.0.113.24", port: 443)
        profile.uuid = "b9d3f7e2-6a4c-4f5d-8e91-2c7a0e4b9f3d"
        try store.upsert(profile: profile)
        let loaded = try store.profiles()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.server, "203.0.113.24")
        try store.delete(profileID: profile.id)
        XCTAssertEqual(try store.profiles().count, 0)
    }

    func testAppSettingsDefaults() {
        let settings = AppSettings.default
        XCTAssertEqual(settings.routingMode, .rule)
        XCTAssertTrue(settings.bypassLAN)
        XCTAssertFalse(settings.consentAccepted)
    }
}
