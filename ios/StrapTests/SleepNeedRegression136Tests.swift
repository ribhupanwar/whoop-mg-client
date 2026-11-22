import XCTest
@testable import Strap

/// Production-path regression gates for the canonical SleepCoach calculation.
/// No Python replica, network, BLE hardware, or private user records required.
final class SleepNeedRegression136Tests: XCTestCase {
    private func calendar(_ identifier: String) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: identifier)!
        return result
    }

    func testScoredNightExcludesSameNightAndFutureEvenWhenInputIsUnsorted() throws {
        let cal = calendar("Asia/Kolkata")
        let wake = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 7)))
        let history = [
            RecordedNight(dateKey: "2026-11-23", neededHours: 8, actualHours: 1),
            RecordedNight(dateKey: "2026-11-22", neededHours: 8, actualHours: 2),
            RecordedNight(dateKey: "2026-11-21", neededHours: 8, actualHours: 7.5),
            RecordedNight(dateKey: "2026-11-20", neededHours: 8, actualHours: 7.5),
            RecordedNight(dateKey: "2026-11-19", neededHours: 8, actualHours: 7.5)
        ]
        let scored = SleepCoach.scoredNightNeed(baseNeedHours: 8, priorNights: history,
                                                 wakeDate: wake, calendar: cal)
        XCTAssertEqual(scored.baselineHours, 8)
        XCTAssertEqual(scored.appliedDebtHours, 1.5, accuracy: 0.000001)
        XCTAssertEqual(scored.totalHours, 9.5, accuracy: 0.000001)
    }

    func testDebtRepaymentAndDuplicateNightCannotChangePriorScore() throws {
        let cal = calendar("Asia/Kolkata")
        let wake = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 7)))
        let history = [
            RecordedNight(dateKey: "2026-11-18", neededHours: 8, actualHours: 8),
            RecordedNight(dateKey: "2026-11-19", neededHours: 8, actualHours: 6),
            RecordedNight(dateKey: "2026-11-20", neededHours: 8, actualHours: 9),
            RecordedNight(dateKey: "2026-11-21", neededHours: 8, actualHours: 9)
        ]
        let once = SleepCoach.scoredNightNeed(baseNeedHours: 8, priorNights: history,
                                               wakeDate: wake, calendar: cal)
        let twice = SleepCoach.scoredNightNeed(baseNeedHours: 8, priorNights: history + history,
                                                wakeDate: wake, calendar: cal)
        XCTAssertEqual(once.totalHours, 8, accuracy: 0.000001)
        XCTAssertEqual(twice, once)
    }

    func testPlannerAndCompletedNightUseSameCappedDebtTarget() throws {
        let cal = calendar("UTC")
        let wake = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 7)))
        let prior = (18...21).map {
            RecordedNight(dateKey: "2026-11-\($0)", neededHours: 8, actualHours: 6)
        }
        let scored = SleepCoach.scoredNightNeed(baseNeedHours: 8, priorNights: prior,
                                                 wakeDate: wake, calendar: cal)
        let planner = SleepCoach.recommendation(baseNeedHours: 8, intent: .rest,
                                                  debtHours: SleepCoach.sleepDebt(nights: prior),
                                                  wakeMinutes: 420, measuredEfficiency: 0.8)
        XCTAssertEqual(scored.totalHours, 10, accuracy: 0.000001)
        XCTAssertEqual(planner.needHours, scored.totalHours, accuracy: 0.000001)
        XCTAssertEqual(planner.timeInBedHours, 12.5, accuracy: 0.000001)
        XCTAssertEqual(planner.appliedDebtHours, 2, accuracy: 0.000001)
    }

    func testUnusableDebtDoesNotPoisonSleepNeed() {
        for debt in [Double.nan, Double.infinity, -1] {
            let result = SleepCoach.sleepNeed(baseNeedHours: 8, debtHours: debt)
            XCTAssertEqual(result.totalHours, 8, accuracy: 0.000001)
            XCTAssertEqual(result.appliedDebtHours, 0, accuracy: 0.000001)
        }
    }
}
