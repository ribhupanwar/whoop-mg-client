import XCTest
@testable import Strap

final class SleepCoachTests: XCTestCase {

    // MARK: Need

    func testNeedByIntentWithoutDebt() {
        let easy = SleepCoach.recommendation(baseNeedHours: 8, intent: .easy, debtHours: nil, wakeMinutes: 420)
        let hard = SleepCoach.recommendation(baseNeedHours: 8, intent: .hard, debtHours: nil, wakeMinutes: 420)
        let rest = SleepCoach.recommendation(baseNeedHours: 8, intent: .rest, debtHours: nil, wakeMinutes: 420)

        XCTAssertEqual(easy.needHours, 8.0, accuracy: 0.0001)
        XCTAssertEqual(hard.needHours, 8.0, accuracy: 0.0001)
        XCTAssertEqual(rest.needHours, 8.0, accuracy: 0.0001)
        XCTAssertNil(easy.debtHours)
    }

    func testTimeInBedUsesValidatedEfficiencyAndKeepsWakeTime() {
        let wake = 7 * 60
        let baseline = SleepCoach.recommendation(baseNeedHours: 8, intent: .easy, debtHours: nil, wakeMinutes: wake)
        XCTAssertEqual(baseline.timeInBedHours, 8)
        XCTAssertEqual(baseline.bedtimeMinutes, 23 * 60)
        XCTAssertNil(baseline.measuredEfficiency)

        let rec = SleepCoach.recommendation(baseNeedHours: 8, intent: .easy, debtHours: nil,
                                            wakeMinutes: wake, measuredEfficiency: 0.85)
        XCTAssertEqual(rec.timeInBedHours, 8.0 / 0.85, accuracy: 0.000001)
        XCTAssertEqual(CoachFormat.duration(rec.timeInBedHours), "9:25")
        XCTAssertEqual(rec.bedtimeMinutes, 21 * 60 + 35)
        XCTAssertEqual(rec.wakeMinutes, wake)
        XCTAssertEqual((rec.bedtimeMinutes + Int((rec.timeInBedHours * 60).rounded())) % 1440, wake)
    }

    func testBedtimeWrapsPastMidnight() {
        let rec = SleepCoach.recommendation(baseNeedHours: 8, intent: .easy, debtHours: nil, wakeMinutes: 30)
        XCTAssertEqual(rec.bedtimeMinutes, 16 * 60 + 30)
    }

    func testBedtimeCanFallAfterMidnight() {
        let rec = SleepCoach.recommendation(baseNeedHours: 7.5, intent: .easy, debtHours: nil, wakeMinutes: 8 * 60)
        XCTAssertEqual(rec.bedtimeMinutes, 30)
    }

    func testScheduledWakeUsesElapsedHoursAcrossDaylightSaving() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let wake = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 7))!
        let rec = SleepCoach.recommendation(baseNeedHours: 8, intent: .easy, debtHours: nil,
                                            wakeMinutes: 420, scheduledWake: wake, calendar: calendar)
        XCTAssertEqual(rec.wakeMinutes, 420)
        XCTAssertEqual(rec.bedtimeMinutes, 22 * 60)
    }

    func testEfficiencyNeedsThreeDistinctNights() {
        let nights = (1...3).map { day in
            RecordedNight(dateKey: "2026-11-0\(day)", neededHours: 8, actualHours: 7,
                          efficiency: [0.8, 0.85, 0.9][day - 1])
        }
        XCTAssertNil(SleepCoach.efficiency(nights: [nights[0], nights[0], nights[1]]))
        XCTAssertEqual(SleepCoach.efficiency(nights: nights), 0.85)
    }

    func testOldFutureAndRemovedNightsDoNotCountTowardDebt() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21))!
        let nights = ["2026-11-01", "2026-11-19", "2026-11-20", "2026-11-21", "2026-11-22"].map {
            RecordedNight(dateKey: $0, neededHours: 8, actualHours: 7)
        }
        let recent = SleepCoach.recentNights(nights, ending: now, calendar: calendar)
        XCTAssertEqual(recent.map(\.dateKey), ["2026-11-19", "2026-11-20", "2026-11-21"])
        XCTAssertEqual(SleepCoach.sleepDebt(nights: recent), 3)
        XCTAssertNil(SleepCoach.sleepDebt(nights: Array(recent.dropLast())))
    }

    func testPendingManualCorrectionExcludesOldBounds() {
        let corrections = ["1800000000": [1_800_000_060, 1_800_028_800]]
        XCTAssertFalse(SleepCoach.matchesSavedCorrection(start: 1_800_000_000, end: 1_800_028_799,
                                                          corrections: corrections))
        XCTAssertTrue(SleepCoach.matchesSavedCorrection(start: 1_800_000_060, end: 1_800_028_799,
                                                         corrections: corrections))
    }

    // MARK: Debt

    func testScoredNightUsesPriorQualifiedNightsAndExcludesItsOwnDeficit() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let wake = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22))!
        let prior = (19...21).map { day in
            RecordedNight(dateKey: "2026-11-\(day)", neededHours: 8, actualHours: 8)
        }
        let target = RecordedNight(dateKey: "2026-11-22", neededHours: 8, actualHours: 5.570555555555556)
        let noDebt = SleepCoach.scoredNightNeed(baseNeedHours: 8, priorNights: prior + [target],
                                               wakeDate: wake, calendar: calendar)
        XCTAssertEqual(noDebt.totalHours, 8)
        let shorter = prior.map { RecordedNight(dateKey: $0.dateKey, neededHours: 8, actualHours: 7.5) }
        let withDebt = SleepCoach.scoredNightNeed(baseNeedHours: 8, priorNights: shorter + [target],
                                                 wakeDate: wake, calendar: calendar)
        XCTAssertEqual(withDebt.appliedDebtHours, 1.5)
        XCTAssertEqual(withDebt.totalHours, 9.5)
    }

    func testNovember22ScoreComponentsUsingExportedDurations() throws {
        let start = 1_795_288_513
        let end = 1_795_309_557
        let staging = SleepStaging(segments: [.init(startUnix: start, endUnix: end, stage: .light)],
            deepMinutes: 56.5, lightMinutes: 192.73333333333332, remMinutes: 85,
            wakeMinutes: 16.5, epochs: 702, hrCoverage: 0.999952480517012, reason: nil)
        let session = SleepSession(version: 6, sourceStartUnix: start, startUnix: start, endUnix: end,
            staging: staging, heartRate: [], movementBouts: 0, isEdited: false)
        // Five aligned nights and one outlier reproduce the exported consistency component.
        let aligned = (1...5).map { day in
            let offset = day * 86_400
            return NightSpan(startUnix: start - offset, endUnix: end - offset)
        }
        let nights = aligned + [NightSpan(startUnix: start + 10_800, endUnix: end + 10_800)]
        let old = try XCTUnwrap(SleepReport.analyze(samples: [], session: session, needHours: 8,
            nights: nights, sleepBaseline: nil))
        XCTAssertEqual(old.hoursVsNeededPct, 69.63194444444444, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(old.performancePct), 82.74250520954332, accuracy: 0.000001)
        let target = SleepCoach.sleepNeed(baseNeedHours: 8, debtHours: 2)
        let revised = try XCTUnwrap(SleepReport.analyze(samples: [], session: session,
            needHours: target.totalHours, nights: nights, sleepBaseline: nil, sleepNeedBreakdown: target))
        XCTAssertEqual(revised.hoursVsNeededPct, 55.705555555555556, accuracy: 0.000001)
        XCTAssertEqual(revised.sleepNeedBreakdown, target)
    }

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
        XCTAssertNil(SleepCoach.sleepDebt(nights: nights))
        let baseline = RecordedNight(dateKey: "2026-11-06", neededHours: 8, actualHours: 8)
        XCTAssertEqual(SleepCoach.sleepDebt(nights: [baseline] + nights) ?? -1, 1.0, accuracy: 0.0001)
    }

    func testDebtFlooredAtZero() {
        // A surplus night cannot bank credit below zero.
        let baseline = RecordedNight(dateKey: "2026-11-06", neededHours: 8, actualHours: 8)
        let before = RecordedNight(dateKey: "2026-11-05", neededHours: 8, actualHours: 8)
        let surplusOnly = [before, baseline, RecordedNight(dateKey: "2026-11-07", neededHours: 8, actualHours: 10)]
        XCTAssertEqual(SleepCoach.sleepDebt(nights: surplusOnly) ?? -1, 0.0, accuracy: 0.0001)

        // Surplus first is floored to 0, then the deficit adds fully.
        let mixed = [
            RecordedNight(dateKey: "2026-11-07", neededHours: 8, actualHours: 10),
            RecordedNight(dateKey: "2026-11-08", neededHours: 8, actualHours: 6)
        ]
        XCTAssertEqual(SleepCoach.sleepDebt(nights: [baseline] + mixed) ?? -1, 2.0, accuracy: 0.0001)

        // A longer night repays existing debt but never below zero.
        let repaid = [
            RecordedNight(dateKey: "2026-11-07", neededHours: 8, actualHours: 6),
            RecordedNight(dateKey: "2026-11-08", neededHours: 8, actualHours: 12)
        ]
        XCTAssertEqual(SleepCoach.sleepDebt(nights: [baseline] + repaid) ?? -1, 0.0, accuracy: 0.0001)
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
        XCTAssertEqual(rec.baselineHours, 8)
        XCTAssertEqual(rec.appliedDebtHours, 2)
        XCTAssertEqual(rec.debtHours ?? -1, 5.0, accuracy: 0.0001)
    }

    func testNightsAreSortedChronologically() {
        let shuffled = [
            RecordedNight(dateKey: "2026-11-06", neededHours: 8, actualHours: 8),
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
        XCTAssertEqual(rec.timeInBedHours, 9.0, accuracy: 0.0001)
        XCTAssertEqual(CoachFormat.clock(rec.bedtimeMinutes), "21:30")
        XCTAssertEqual(CoachFormat.duration(rec.needHours), "9:00")
        XCTAssertEqual(CoachFormat.duration(rec.timeInBedHours), "9:00")
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