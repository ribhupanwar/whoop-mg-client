import XCTest
@testable import Strap

final class DailyLocalBackupScheduleTests: XCTestCase {
    func testDefaultAndSupportedIntervals() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        XCTAssertEqual(DailyLocalBackup.interval(defaults), 86_400)
        for seconds in [3_600, 21_600, 43_200, 86_400, 604_800] {
            defaults.set(seconds, forKey: DailyLocalBackup.intervalKey)
            XCTAssertEqual(DailyLocalBackup.interval(defaults), TimeInterval(seconds))
        }
        defaults.set(0, forKey: DailyLocalBackup.intervalKey)
        XCTAssertNil(DailyLocalBackup.interval(defaults))
        defaults.set(-1, forKey: DailyLocalBackup.intervalKey)
        XCTAssertEqual(DailyLocalBackup.interval(defaults), 86_400)
    }

    func testDueEligibilityUsesElapsedTimeNotCalendarDay() {
        let now = Date(timeIntervalSince1970: 1_795_600_000)
        XCTAssertTrue(DailyLocalBackup.isDue(now: now, lastSuccess: nil, interval: 3_600))
        XCTAssertFalse(DailyLocalBackup.isDue(now: now, lastSuccess: now.addingTimeInterval(-3_599), interval: 3_600))
        XCTAssertTrue(DailyLocalBackup.isDue(now: now, lastSuccess: now.addingTimeInterval(-3_600), interval: 3_600))
        XCTAssertFalse(DailyLocalBackup.isDue(now: now, lastSuccess: now.addingTimeInterval(-86_400), interval: nil))
        XCTAssertFalse(DailyLocalBackup.isDue(now: now, lastSuccess: now.addingTimeInterval(100), interval: 3_600))
    }

    func testRetentionDefaultsAndNeverRequestsNegativeDays() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        XCTAssertEqual(DailyLocalBackup.retentionDays(defaults), 30)
        defaults.set(7, forKey: DailyLocalBackup.retentionKey)
        XCTAssertEqual(DailyLocalBackup.retentionDays(defaults), 7)
        defaults.set(0, forKey: DailyLocalBackup.retentionKey)
        XCTAssertNil(DailyLocalBackup.retentionDays(defaults))
        defaults.set(-30, forKey: DailyLocalBackup.retentionKey)
        XCTAssertEqual(DailyLocalBackup.retentionDays(defaults), 30)
    }
}
