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

    func testDeletedOrMovedAllArchivesTriggersReplacementBackup() {
        let now = Date(timeIntervalSince1970: 1_795_600_000)
        let recentSuccess = now.addingTimeInterval(-60)
        let last = DailyLocalBackup.effectiveLastSuccess(
            newestArchive: nil, recordedSuccess: recentSuccess)
        XCTAssertNil(last, "A remembered success cannot replace a real archive")
        XCTAssertTrue(DailyLocalBackup.isDue(now: now, lastSuccess: last, interval: 86_400))
    }

    func testExistingArchivesStillRespectScheduleAndRecordedSuccess() {
        let now = Date(timeIntervalSince1970: 1_795_600_000)
        let archive = now.addingTimeInterval(-4_000)
        let recorded = now.addingTimeInterval(-1_000)
        XCTAssertEqual(DailyLocalBackup.effectiveLastSuccess(
            newestArchive: archive, recordedSuccess: recorded), recorded)
        XCTAssertEqual(DailyLocalBackup.effectiveLastSuccess(
            newestArchive: archive, recordedSuccess: nil), archive)
        XCTAssertFalse(DailyLocalBackup.isDue(now: now, lastSuccess: recorded, interval: 3_600))
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
