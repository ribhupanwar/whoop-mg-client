import XCTest
@testable import Strap

final class WakeAlarmTests: XCTestCase {
    func testUpgradePreservesExistingWakeTimeAndNeverOverwritesNewPreference() throws {
        let name = "WakeAlarmTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        WakeAlarm.restoreWakeTimeIfNeeded(6 * 60 + 40, defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: "strap.wake.alarm.minutes.v1"), 400)
        WakeAlarm.restoreWakeTimeIfNeeded(7 * 60, defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: "strap.wake.alarm.minutes.v1"), 400)
        XCTAssertNil(defaults.object(forKey: "strap.wake.alarm.enabled.v1"))
    }
}
