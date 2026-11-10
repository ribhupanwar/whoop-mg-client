import XCTest
@testable import Strap

final class SleepCoachTests: XCTestCase {

    // MARK: Need

    func testNeedByIntentWithoutDebt() {
        let easy = SleepCoach.recommendation(baseNeedHours: 8, intent: .easy, debtHours: nil, wakeMinutes: 420)
        let hard = SleepCoach.recommendation(baseNeedHours: 8, intent: .hard, debtHours: nil, wakeMinutes: 420)
        let rest = SleepCoach.recommendation(baseNeedHours: 8, intent: .rest, debtHours: nil, wakeMinutes: 420)

        XCTAssertEqual(easy.needHours, 8.0, accuracy: 0.0001)
        XCTAssertEqual(hard.needHours, 8.5, accuracy: 0.0001)
        XCTAssertEqual(rest.needHours, 8.25, accuracy: 0.0001)
        XCTAssertNil(easy.debtHours)
    }

    func testTimeInBedFormula() {
        let rec = SleepCoach.recommendation(baseNeedHours: 8, intent: .easy, debtHours: nil, wakeMinutes: 420)
        // timeInBed = need / 0.90 + 0.25
        XCTAssertEqual(rec.timeInBedHours, 8.0 / 0.90 + 0.25, accuracy: 0.000001)
    }

    // MARK: Bedtime wrap

    func testBedtimeWrapsPastMidnight() {
        // Wake 06:30, need 8 h → in bed 9:08 (548 min) → bedtime 21:22 previous day.
        let rec = SleepCoach.recommendation(baseNeedHours: 8, intent: .easy, debtHours: nil, wakeMinutes: 6 * 60 + 30)
        XCTAssertEqual(rec.bedtimeMinutes, 21 * 60 + 22)
        XCTAssertEqual(CoachFormat.clock(rec.bedtimeMinutes), "21:22")
    }

    func testBedtimeWrapJustAfterMidnightWake() {
        // Wake 00:30 → 30 − 548 = −518 → wraps to 15:22.
        let rec = SleepCoach.recommendation(baseNeedHours: 8, intent: .easy, debtHours: nil, wakeMinutes: 30)
        XCTAssertEqual(rec.bedtimeMinutes, 15 * 60 + 22)
        XCTAssertTrue((0..<1440).contains(rec.bedtimeMinutes))
    }

    // MARK: Debt

    func testDebtUnknownWithNoNights() {
        XCTAssertNil(SleepCoach.sleepDebt(nights: []))
        let rec = SleepCoach.recommendation(baseNeedHours: 8, intent: .easy, debtHours: nil, wakeMinutes: 420)
        XCTAssertEqual(rec.needHours, 8.0, accuracy: 0.0001)
        XCTAssertNil(rec.debtHours)
    }

    func testDebtRunningBalance() {
        let nights = [
            RecordedNight(dateKey: "2026-11-07", neededHours: 8, actualHours: 7.5),
            RecordedNight(dateKey: "2026-11-08", neededHours: 8, actualHours: 7.5)
        ]
        XCTAssertEqual(SleepCoach.sleepDebt(nights: nights) ?? -1, 1.0, accuracy: 0.0001)
    }

    func testDebtFlooredAtZero() {
        // A surplus night cannot bank credit below zero.
        let surplusOnly = [RecordedNight(dateKey: "2026-11-07", neededHours: 8, actualHours: 10)]
        XCTAssertEqual(SleepCoach.sleepDebt(nights: surplusOnly) ?? -1, 0.0, accuracy: 0.0001)

        // Surplus first is floored to 0, then the deficit adds fully.
        let mixed = [
            RecordedNight(dateKey: "2026-11-07", neededHours: 8, actualHours: 10),
            RecordedNight(dateKey: "2026-11-08", neededHours: 8, actualHours: 6)
        ]
        XCTAssertEqual(SleepCoach.sleepDebt(nights: mixed) ?? -1, 2.0, accuracy: 0.0001)

        // A longer night repays existing debt but never below zero.
        let repaid = [
            RecordedNight(dateKey: "2026-11-07", neededHours: 8, actualHours: 6),
            RecordedNight(dateKey: "2026-11-08", neededHours: 8, actualHours: 12)
        ]
        XCTAssertEqual(SleepCoach.sleepDebt(nights: repaid) ?? -1, 0.0, accuracy: 0.0001)
    }

    func testDebtWindowIsFourteenNights() {
        let nights = (1...15).map { day in
            RecordedNight(
                dateKey: String(format: "2026-01-%02d", day),
                neededHours: 8,
                actualHours: 7
            )
        }
        // 15 nights of 1 h shortfall, but only the last 14 count.
        XCTAssertEqual(SleepCoach.sleepDebt(nights: nights) ?? -1, 14.0, accuracy: 0.0001)
    }

    func testDebtCapAtTwoHours() {
        let rec = SleepCoach.recommendation(baseNeedHours: 8, intent: .easy, debtHours: 5.0, wakeMinutes: 420)
        // need = 8 + 0 + min(5, 2) = 10 — a bad week cannot demand an impossible bedtime.
        XCTAssertEqual(rec.needHours, 10.0, accuracy: 0.0001)
        XCTAssertEqual(rec.debtHours ?? -1, 5.0, accuracy: 0.0001)
    }

    func testNightsAreSortedChronologically() {
        let shuffled = [
            RecordedNight(dateKey: "2026-11-08", neededHours: 8, actualHours: 6),
            RecordedNight(dateKey: "2026-11-07", neededHours: 8, actualHours: 10)
        ]
        // Chronological: surplus floored to 0, then +2 → 2 (not 0).
        XCTAssertEqual(SleepCoach.sleepDebt(nights: shuffled) ?? -1, 2.0, accuracy: 0.0001)
    }

    // MARK: Demo coach numbers (mockup parity)

    func testDemoCoachNumbers() {
        let debt = SleepCoach.sleepDebt(nights: SampleData.nights)
        let rec = SleepCoach.recommendation(
            baseNeedHours: 8,
            intent: .easy,
            debtHours: debt,
            wakeMinutes: SampleData.demoWakeMinutes
        )
        XCTAssertEqual(rec.needHours, 9.0, accuracy: 0.0001)
        XCTAssertEqual(rec.timeInBedHours, 10.25, accuracy: 0.0001)
        XCTAssertEqual(CoachFormat.clock(rec.bedtimeMinutes), "20:15")
        XCTAssertEqual(CoachFormat.duration(rec.needHours), "9:00")
        XCTAssertEqual(CoachFormat.duration(rec.timeInBedHours), "10:15")
    }

    // MARK: Formatting

    func testClockWraps() {
        XCTAssertEqual(CoachFormat.clock(1282), "21:22")
        XCTAssertEqual(CoachFormat.clock(-158), "21:22")
        XCTAssertEqual(CoachFormat.clock(0), "00:00")
        XCTAssertEqual(CoachFormat.clock(1440), "00:00")
    }

    func testDurationRoundsToMinute() {
        XCTAssertEqual(CoachFormat.duration(10.25), "10:15")
        XCTAssertEqual(CoachFormat.duration(8.0 / 0.90 + 0.25), "9:08")
        XCTAssertEqual(CoachFormat.duration(5.0 + 49.0 / 60.0), "5:49")
    }
}