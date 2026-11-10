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

    func testDashboardLayoutDefaultsToEveryRowInOrder() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.dashboardOrder, DashboardRow.allCases)
        XCTAssertTrue(settings.hiddenDashboardRows.isEmpty)
    }

    func testSavedDashboardOrderAndHiddenRowsSurviveRoundTrip() throws {
        var settings = AppSettings()
        settings.dashboardOrder = [.stress, .steps, .hrv, .restingHR, .zonesLow,
                                   .zonesHigh, .vo2Max, .calories]
        settings.hiddenDashboardRows = [.zonesHigh, .calories]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.dashboardOrder, settings.dashboardOrder)
        XCTAssertEqual(decoded.hiddenDashboardRows, settings.hiddenDashboardRows)
    }

    /// A save from a build with fewer rows must keep the arrangement and append
    /// the rows that appeared later; an unknown key must not throw the decode.
    func testOlderDashboardOrderGainsNewRowsAtTheEnd() throws {
        let old = Data(#"""
        {"age":30,"dashboardOrder":["stress","hrv","retiredRow"],"hiddenDashboardRows":["gone"]}
        """#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertEqual(Array(settings.dashboardOrder.prefix(2)), [.stress, .hrv])
        XCTAssertEqual(settings.dashboardOrder.count, DashboardRow.allCases.count)
        XCTAssertEqual(settings.dashboardOrder.last, .calories)
        XCTAssertTrue(settings.hiddenDashboardRows.isEmpty)
    }

    func testMalformedDashboardKeysAreDroppedNotFatal() throws {
        let duplicate = Data(#"{"dashboardOrder":["steps","steps","steps"]}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: duplicate)
        XCTAssertEqual(settings.dashboardOrder.first, .steps)
        XCTAssertEqual(settings.dashboardOrder.filter { $0 == .steps }.count, 1)
        XCTAssertEqual(Set(settings.dashboardOrder), Set(DashboardRow.allCases))
    }

    func testBodyDataDefaultsToNilSoCaloriesAbstain() throws {
        let old = Data(#"{"age":41,"designPreview":true}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertNil(settings.weightKG)
        XCTAssertNil(settings.heightCM)
    }

    func testBodyDataRoundTrips() throws {
        var settings = AppSettings()
        settings.weightKG = 72.5
        settings.heightCM = 178
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.weightKG, 72.5)
        XCTAssertEqual(decoded.heightCM, 178)
    }

    func testBodyTextFieldParsing() {
        XCTAssertEqual(SettingsView.parsedNumber("72.5"), 72.5)
        XCTAssertEqual(SettingsView.parsedNumber("72,5"), 72.5)
        XCTAssertNil(SettingsView.parsedNumber(""))
        XCTAssertNil(SettingsView.parsedNumber("0"))
        XCTAssertNil(SettingsView.parsedNumber("abc"))
    }
}
