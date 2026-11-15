import XCTest
@testable import Strap

final class HistoryProgressTests: XCTestCase {
    func testProgressHasNoInventedFractionBeforeWorkAndReportsStalls() {
        let began = Date(timeIntervalSince1970: 1000)
        let preparing = HistoryProgress(stage: .preparing, completed: 0, total: 0, reused: 0,
                                        startedAt: began, lastStepAt: began)
        XCTAssertNil(preparing.fraction)
        XCTAssertTrue(preparing.detail(now: began.addingTimeInterval(120)).contains("Last progress 120s ago"))
        let days = HistoryProgress(stage: .days, completed: 3, total: 6, reused: 0,
                                  startedAt: began, lastStepAt: began.addingTimeInterval(30))
        XCTAssertEqual(days.fraction, 0.5)
        XCTAssertTrue(days.detail(now: began.addingTimeInterval(30)).contains("about 1 min left"))
        let cached = HistoryProgress(stage: .days, completed: 3, total: 6, reused: 3,
                                    startedAt: began, lastStepAt: began.addingTimeInterval(30))
        XCTAssertFalse(cached.detail(now: began.addingTimeInterval(30)).contains("left"))
    }
    func testAutomaticSyncBackoffNeverDelaysManualOrForegroundSync() {
        let last = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(HistorySyncPolicy.shouldSync(now: last.addingTimeInterval(899), lastAttempt: last))
        XCTAssertTrue(HistorySyncPolicy.shouldSync(now: last.addingTimeInterval(900), lastAttempt: last))
        XCTAssertFalse(HistorySyncPolicy.shouldSync(now: last.addingTimeInterval(900), lastAttempt: last, emptyStreak: 8))
        XCTAssertTrue(HistorySyncPolicy.shouldSync(now: last.addingTimeInterval(3600), lastAttempt: last, emptyStreak: 8))
        XCTAssertTrue(HistorySyncPolicy.shouldSync(now: last, lastAttempt: last, manual: true, emptyStreak: 8))
        XCTAssertTrue(HistorySyncPolicy.shouldSync(now: last.addingTimeInterval(90), lastAttempt: last,
                                                 foreground: true, emptyStreak: 8))
        XCTAssertTrue(HistorySyncPolicy.shouldSync(now: last, lastAttempt: nil))
    }
    func testBacklogContinuationRequiresProgressAndHasHardStop() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(HistorySyncPolicy.shouldContinue(timedOut: true, newest: 8000, previous: 7000, attempts: 0, now: now))
        XCTAssertFalse(HistorySyncPolicy.shouldContinue(timedOut: false, newest: 8000, previous: 7000, attempts: 0, now: now))
        XCTAssertFalse(HistorySyncPolicy.shouldContinue(timedOut: true, newest: 8000, previous: 8000, attempts: 0, now: now))
        XCTAssertFalse(HistorySyncPolicy.shouldContinue(timedOut: true, newest: nil, previous: 7000, attempts: 0, now: now))
        XCTAssertFalse(HistorySyncPolicy.shouldContinue(timedOut: true, newest: 8000, previous: 7000, attempts: 3, now: now))
        XCTAssertFalse(HistorySyncPolicy.shouldContinue(timedOut: true, newest: 9900, previous: 7000, attempts: 0, now: now))
        XCTAssertFalse(HistorySyncPolicy.shouldContinue(timedOut: true, newest: 11_000, previous: 7000, attempts: 0, now: now))
    }
}
