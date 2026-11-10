import XCTest
@testable import Strap

final class SettingsTests: XCTestCase {
    func testOldSettingsWithoutNewKeysStillLoad() throws {
        let old = Data(#"{"age":34,"designPreview":true,"sleepNeedHours":7.5}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertEqual(settings.age, 34)
        XCTAssertTrue(settings.designPreview)
        XCTAssertEqual(settings.sleepNeedHours, 7.5)
        XCTAssertEqual(settings.sex, .unspecified)
        XCTAssertEqual(settings.wakeTimeMinutes, 7 * 60)
        XCTAssertEqual(settings.sleepIntent, .easy)
    }

    func testRoundTripKeepsIntentAndWake() throws {
        var settings = AppSettings()
        settings.wakeTimeMinutes = 6 * 60 + 15
        settings.sleepIntent = .hard
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.sleepIntent.extraHours, 0.5)
    }
}
