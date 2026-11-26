import XCTest
@testable import Strap

final class StepCounterTests: XCTestCase {
    private func sample(_ unix: Int, steps: Int?, hr: Int = 70) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(
                version: 18, flags: 0x80, recordIndex: UInt32(unix),
                unix: UInt32(unix), subsecQ15: 0
            ),
            heartRate: hr,
            rrIntervalsMS: [],
            dynamicAccelG: 0.02,
            gravityXG: nil,
            gravityYG: nil,
            gravityZG: nil,
            stepCounter: steps,
            stepCadence: nil,
            activityClass: 0,
            skinTempC: nil,
            tempAux1C: nil,
            tempAux2C: nil,
            sleepStateByte: nil,
            sleepState: nil,
            cardiacFlags: nil,
            hrQualityFlags: nil,
            spo2CandidateRaw: nil,
            spo2CandidatePct: nil,
            spo2CandidateKind: .absent,
            signalQualityLogVariance: nil,
            psnrB: nil,
            psnrA: nil
        )
    }

    func testTotalSumsDeltasNotEndpoints() {
        // A counter that restarts in the middle: 100 → 130, then a new epoch
        // 0 → 20. Deltas occur over plausible five-second windows, so the
        // honest total is 50 rather than treating the reset as a 16-bit wrap.
        let samples = [
            sample(0, steps: 100), sample(5, steps: 130),
            sample(6, steps: 0), sample(11, steps: 20)
        ]
        XCTAssertEqual(StepCounter.total(samples), 50)
    }

    func testResetFirstValueIsNotInventedSteps() {
        let samples = [
            sample(0, steps: 500), sample(1, steps: 503),
            sample(2, steps: 4), sample(3, steps: 6)
        ]
        // Three before reset, two after. The reset reading of four
        // is an unknown baseline, not four measured new steps.
        XCTAssertEqual(StepCounter.total(samples), 5)
        XCTAssertEqual(StepCounter.delta(from: 503, to: 4, seconds: 1), 0)
    }

    func testWrapAtSixteenBits() {
        let samples = [
            sample(0, steps: 65_530), sample(1, steps: 65_535), sample(2, steps: 3)
        ]
        XCTAssertEqual(StepCounter.total(samples), 9)
    }

    func testNoCounterReportsNil() {
        XCTAssertNil(StepCounter.total([sample(0, steps: nil), sample(1, steps: nil)]))
        XCTAssertEqual(StepCounter.total([]), nil)
    }

    func testMissingReadingsAreSkipped() {
        let samples = [
            sample(0, steps: 10), sample(1, steps: nil), sample(2, steps: 14)
        ]
        XCTAssertEqual(StepCounter.total(samples), 4)
    }

    func testUnsortedInputIsOrderedFirst() {
        let samples = [sample(2, steps: 12), sample(0, steps: 10), sample(1, steps: 11)]
        XCTAssertEqual(StepCounter.total(samples), 2)
    }

    func testRateCountsSustainedStepping() {
        // Two steps per second for a minute → 120 steps/min.
        let samples = (0...60).map { sample($0, steps: $0 * 2) }
        XCTAssertEqual(StepCounter.rate(samples, at: 60) ?? 0, 120, accuracy: 0.001)
    }

    func testRateDropsCatchUpLeaps() {
        // A quiet minute that ends in one 12-step catch-up must not read as
        // twelve steps in a second of walking.
        var samples = (0...59).map { sample($0, steps: 0) }
        samples.append(sample(60, steps: 12))
        XCTAssertEqual(StepCounter.rate(samples, at: 60) ?? 0, 0, accuracy: 0.001)
    }

    func testResetDoesNotProduceAHugeRate() {
        let samples = [
            sample(0, steps: 60_000), sample(1, steps: 0), sample(2, steps: 2)
        ]
        XCTAssertEqual(StepCounter.rate(samples, at: 2) ?? -1, 60, accuracy: 0.001)
    }
    func testCapturedTodayExcludesYesterdayAndTomorrow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = Date(timeIntervalSince1970: 1_700_006_400)
        let start = Int(calendar.startOfDay(for: today).timeIntervalSince1970)
        let samples = [
            sample(start - 1, steps: 90),
            sample(start, steps: 100),
            sample(start + 1, steps: 103),
            sample(start + 2, steps: 105),
            sample(start + 86_400, steps: 110)
        ]
        XCTAssertEqual(StepCounter.capturedToday(samples, now: today, calendar: calendar), 5)
    }

    func testCapturedTodayDoesNotClaimMissingHistoryAsZero() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_006_400)
        XCTAssertNil(StepCounter.capturedToday([], now: now, calendar: calendar))
    }

    func testConflictingSameSecondReplayDoesNotInventSteps() {
        let records = [
            sample(10, steps: 100), sample(11, steps: 101),
            sample(11, steps: 120), sample(12, steps: 122),
            sample(13, steps: 124)
        ]
        // The disputed second is discarded. Only 12 -> 13 is certain.
        XCTAssertEqual(StepCounter.total(records), 2)
        XCTAssertEqual(StepCounter.total(records.reversed().map { $0 }), 2)
    }

    func testRateRejectsConflictingSameSecondReplay() {
        let records = [sample(10, steps: 100), sample(11, steps: 101),
                       sample(11, steps: 120), sample(12, steps: 122),
                       sample(13, steps: 124)]
        // Only the 12 -> 13 delta is proven; 2 steps over 3 seconds.
        XCTAssertEqual(StepCounter.rate(records, at: 4) ?? -1, 40, accuracy: 0.001)
    }

    func testIdenticalSameSecondRetransmissionIsIdempotent() {
        let records = [sample(10, steps: 100), sample(11, steps: 102),
                       sample(11, steps: 102), sample(12, steps: 104)]
        XCTAssertEqual(StepCounter.total(records), 4)
    }


    func testPersistentLedgerReplayAndConflict() async throws {
        let suite = "strap.step-ledger.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_700_006_400)
        let start = Int(calendar.startOfDay(for: now).timeIntervalSince1970)
        let rows = [sample(start, steps: 100), sample(start + 1, steps: 102),
                    sample(start + 2, steps: 104), sample(start + 3, steps: 106)]
        let ledger = DailyStepLedger(defaults: defaults)
        await ledger.ingest(rows, calendar: calendar, now: now)
        await ledger.ingest(rows.reversed().map { $0 }, calendar: calendar, now: now)
        let before = await ledger.capturedToday(now: now, calendar: calendar)
        XCTAssertEqual(before, 6)
        let restored = DailyStepLedger(defaults: defaults)
        let persisted = await restored.capturedToday(now: now, calendar: calendar)
        XCTAssertEqual(persisted, 6)
        await restored.ingest([sample(start + 1, steps: 110)], calendar: calendar, now: now)
        let conflict = await restored.capturedToday(now: now, calendar: calendar)
        XCTAssertEqual(conflict, 2)
        await restored.ingest(rows, calendar: calendar, now: now)
        let replay = await restored.capturedToday(now: now, calendar: calendar)
        XCTAssertEqual(replay, 2)
    }

    func testPersistentLedgerLocalMidnightAndMissingDay() async throws {
        let suite = "strap.step-ledger.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        let now = Date(timeIntervalSince1970: 1_700_006_400)
        let start = Int(calendar.startOfDay(for: now).timeIntervalSince1970)
        let ledger = DailyStepLedger(defaults: defaults)
        let absent = await ledger.capturedToday(now: now, calendar: calendar)
        XCTAssertNil(absent)
        await ledger.ingest([sample(start - 1, steps: 100), sample(start, steps: 103),
                             sample(start + 1, steps: 105)], calendar: calendar, now: now)
        let today = await ledger.capturedToday(now: now, calendar: calendar)
        XCTAssertEqual(today, 2)
        let next = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let tomorrow = await ledger.capturedToday(now: next, calendar: calendar)
        XCTAssertNil(tomorrow)
    }


    func testPersistentLedgerRebucketsWhenTimezoneChanges() async throws {
        let suite = "strap.step-ledger.timezone." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var kolkata = Calendar(identifier: .gregorian)
        kolkata.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        let midnightUTC = 1_700_006_400
        let now = Date(timeIntervalSince1970: Double(midnightUTC + 60))
        let ledger = DailyStepLedger(defaults: defaults)
        await ledger.ingest([sample(midnightUTC - 2, steps: 100),
                             sample(midnightUTC - 1, steps: 102),
                             sample(midnightUTC, steps: 104),
                             sample(midnightUTC + 1, steps: 106)], calendar: utc, now: now)
        let utcCount = await ledger.capturedToday(now: now, calendar: utc)
        let kolkataCount = await ledger.capturedToday(now: now, calendar: kolkata)
        XCTAssertEqual(utcCount, 2)
        XCTAssertEqual(kolkataCount, 6)
        let restored = DailyStepLedger(defaults: defaults)
        let restoredCount = await restored.capturedToday(now: now, calendar: kolkata)
        XCTAssertEqual(restoredCount, 6)
    }


    func testPersistentLedgerLargeReplayAndStationaryEvidence() async throws {
        let suite = "strap.step-ledger.volume." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let reference = Date(timeIntervalSince1970: 1_700_006_400)
        let start = Int(calendar.startOfDay(for: reference).timeIntervalSince1970)
        let now = Date(timeIntervalSince1970: Double(start + 14_000))
        let rows = (0..<12_000).map { sample(start + $0, steps: 100 + $0 * 2) }
        let ledger = DailyStepLedger(defaults: defaults)
        await ledger.ingest(rows, calendar: calendar, now: now)
        await ledger.ingest(Array(rows.reversed()), calendar: calendar, now: now)
        let moving = await ledger.todaySnapshot(now: now, calendar: calendar)
        XCTAssertEqual(moving.steps, 23_998)
        XCTAssertEqual(moving.lastObservedAt, Date(timeIntervalSince1970: Double(start + 11_999)))
        XCTAssertEqual(moving.lastIncreaseAt, moving.lastObservedAt)
        let stopped = (12_000...12_030).map { sample(start + $0, steps: 24_098) }
        await ledger.ingest(stopped, calendar: calendar, now: now)
        let still = await ledger.todaySnapshot(now: now, calendar: calendar)
        XCTAssertEqual(still.steps, 23_998)
        XCTAssertEqual(still.lastObservedAt, Date(timeIntervalSince1970: Double(start + 12_030)))
        XCTAssertEqual(still.lastIncreaseAt, moving.lastIncreaseAt)
        let reopened = DailyStepLedger(defaults: defaults)
        let restored = await reopened.todaySnapshot(now: now, calendar: calendar)
        XCTAssertEqual(restored, still)
    }

    func testPersistentLedgerWrapResetGapsAndNoFabricatedSteps() async throws {
        let suite = "strap.step-ledger.wrap." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_700_006_400)
        let start = Int(calendar.startOfDay(for: now).timeIntervalSince1970)
        let ledger = DailyStepLedger(defaults: defaults)
        await ledger.ingest([
            sample(start, steps: 65_530), sample(start + 1, steps: 65_534),
            sample(start + 2, steps: 3), sample(start + 100, steps: 1_000),
            sample(start + 101, steps: 1_002), sample(start + 102, steps: 2),
            sample(start + 103, steps: 4)
        ], calendar: calendar, now: now)
        let verified = await ledger.capturedToday(now: now, calendar: calendar)
        XCTAssertEqual(verified, 13)
    }

    func testPersistentLedgerStationaryHasNoMovementEvidence() async throws {
        let suite = "strap.step-ledger.quiet." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_700_006_400)
        let start = Int(calendar.startOfDay(for: now).timeIntervalSince1970)
        let ledger = DailyStepLedger(defaults: defaults)
        await ledger.ingest((0..<90).map { sample(start + $0, steps: 500) }, calendar: calendar, now: now)
        let snapshot = await ledger.todaySnapshot(now: now, calendar: calendar)
        XCTAssertEqual(snapshot.steps, 0)
        XCTAssertNil(snapshot.lastIncreaseAt)
        XCTAssertNotNil(snapshot.lastObservedAt)
    }

    func testRecordedMinimumNeverAddsOverlappingCaptureWindows() {
        XCTAssertEqual(DailyStepLedger.bestRecordedMinimum(archive: 500, ledger: 420), 500)
        XCTAssertEqual(DailyStepLedger.bestRecordedMinimum(archive: 500, ledger: 620), 620)
        XCTAssertEqual(DailyStepLedger.bestRecordedMinimum(archive: nil, ledger: 5), 5)
        XCTAssertNil(DailyStepLedger.bestRecordedMinimum(archive: nil, ledger: nil))
        XCTAssertNil(DailyStepLedger.bestRecordedMinimum(archive: -1, ledger: nil))
    }


    func testOffWristStepCounterBreaksContinuityInCaptureAndLedger() async throws {
        let suite = "strap.step-ledger.offwrist." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_700_006_400)
        let start = Int(calendar.startOfDay(for: now).timeIntervalSince1970)
        let rows = [sample(start, steps: 100),
                    sample(start + 1, steps: 105, hr: 0), // off wrist
                    sample(start + 2, steps: 107),
                    sample(start + 3, steps: 109)]
        XCTAssertEqual(StepCounter.total(rows), 2)
        let ledger = DailyStepLedger(defaults: defaults)
        await ledger.ingest(rows, calendar: calendar, now: now)
        let count = await ledger.capturedToday(now: now, calendar: calendar)
        XCTAssertEqual(count, 2)
        await ledger.ingest([sample(start + 1, steps: 105)], calendar: calendar, now: now)
        let replay = await ledger.capturedToday(now: now, calendar: calendar)
        XCTAssertEqual(replay, 2)
    }

}
