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
        XCTAssertTrue(HistorySyncPolicy.shouldContinue(timedOut: true, sealedAndAcknowledged: true, newestInserted: 8000, previous: 7000, attempts: 0, now: now))
        XCTAssertFalse(HistorySyncPolicy.shouldContinue(timedOut: false, sealedAndAcknowledged: true, newestInserted: 8000, previous: 7000, attempts: 0, now: now))
        XCTAssertFalse(HistorySyncPolicy.shouldContinue(timedOut: true, sealedAndAcknowledged: true, newestInserted: 8000, previous: 8000, attempts: 0, now: now))
        XCTAssertFalse(HistorySyncPolicy.shouldContinue(timedOut: true, sealedAndAcknowledged: true, newestInserted: nil, previous: 7000, attempts: 0, now: now))
        XCTAssertFalse(HistorySyncPolicy.shouldContinue(timedOut: true, sealedAndAcknowledged: true, newestInserted: 8000, previous: 7000, attempts: 3, now: now))
        XCTAssertFalse(HistorySyncPolicy.shouldContinue(timedOut: true, sealedAndAcknowledged: true, newestInserted: 9900, previous: 7000, attempts: 0, now: now))
        XCTAssertFalse(HistorySyncPolicy.shouldContinue(timedOut: true, sealedAndAcknowledged: true, newestInserted: 11_000, previous: 7000, attempts: 0, now: now))
    }
    func testClockLossRequiresSynchronizationFromTheSameBand() {
        let first = UUID()
        let second = UUID()
        var gate = HistoryClockGate()
        let originalRevision = gate.revision
        gate.noteLoss(on: first)
        XCTAssertNotEqual(gate.revision, originalRevision)
        XCTAssertFalse(gate.permitsHistory(on: first))
        XCTAssertTrue(gate.permitsHistory(on: second))
        gate.noteLoss(on: second)
        XCTAssertFalse(gate.permitsHistory(on: first))
        XCTAssertFalse(gate.permitsHistory(on: second))
        gate.noteSynchronization(on: second)
        XCTAssertTrue(gate.permitsHistory(on: second))
        XCTAssertFalse(gate.permitsHistory(on: first))
        gate.noteSynchronization(on: first)
        XCTAssertTrue(gate.permitsHistory(on: first))
        XCTAssertNotEqual(gate.revision, originalRevision, "Old continuation work stays invalid after RTC recovery")
    }
    func testContinuationRequiresASealedAndAcknowledgedPass() {
        let now = Date(timeIntervalSince1970: 50_000)
        XCTAssertFalse(HistorySyncPolicy.shouldContinue(timedOut: true, sealedAndAcknowledged: false,
            newestInserted: 2_000, previous: 1_000, attempts: 0, now: now))
    }

    func testContinuationBudgetRemainsBoundedWhileDurableRowsAdvance() {
        let now = Date(timeIntervalSince1970: 50_000)
        var frontier: Int? = 1_000
        for attempt in 0..<3 {
            let committed = 2_000 + attempt * 1_000
            XCTAssertTrue(HistorySyncPolicy.shouldContinue(timedOut: true, sealedAndAcknowledged: true, newestInserted: committed,
                previous: frontier, attempts: attempt, now: now))
            frontier = committed
        }
        XCTAssertFalse(HistorySyncPolicy.shouldContinue(timedOut: true, sealedAndAcknowledged: true, newestInserted: 5_000,
            previous: frontier, attempts: 3, now: now))
    }
}
