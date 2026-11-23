import XCTest
@testable import Strap

/// Regression for the verified 22:00 cutoff: a delayed coarse band sleep hint
/// must not erase physiological overnight onset, while daytime rest still
/// requires independently confirmed band sleep evidence.
final class SleepOvernightOnsetBoundaryTests: XCTestCase {
    func testChangedSleepStagingRecipeInvalidatesVersionFiveSnapshots() {
        XCTAssertGreaterThan(SleepSession.algorithmVersion, 5)
    }

    private func row(_ unix: Int, seconds: Int, sleeping: Bool, sleepState: Int?, heartRate: Int? = nil, dynamicAccelG: Double? = nil) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(version: 18, flags: 0x80,
                recordIndex: UInt32(seconds), unix: UInt32(unix), subsecQ15: 0),
            heartRate: heartRate ?? (sleeping ? 56 : 91), rrIntervalsMS: [],
            dynamicAccelG: dynamicAccelG ?? (sleeping ? 0.012 : 0.23),
            gravityXG: 0, gravityYG: 0, gravityZG: 1,
            stepCounter: nil, stepCadence: nil, activityClass: 0,
            skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: sleepState.map { $0 << 4 }, sleepState: sleepState,
            cardiacFlags: nil, hrQualityFlags: nil,
            spo2CandidateRaw: nil, spo2CandidatePct: nil,
            spo2CandidateKind: .absent,
            signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
        )
    }

    private func capture(startHour: Int, startMinute: Int,
                         totalMinutes: Int = 75,
                         sleepStateDelay: Int = 14 * 60,
                         evidence: Bool = true) -> ([V18Sample], Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = Int(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 18,
            hour: startHour, minute: startMinute
        ))!.timeIntervalSince1970)
        var records: [V18Sample] = []
        for second in 0..<900 {
            records.append(row(start - 900 + second, seconds: second,
                               sleeping: false, sleepState: 0))
        }
        for second in 0..<(totalMinutes * 60) {
            let state: Int? = second >= sleepStateDelay && evidence ? 2 : 1
            records.append(row(start + second, seconds: second + 900,
                               sleeping: true, sleepState: state))
        }
        return (records, start)
    }

    func testNightAt2351RetainsFourteenMinutesBeforeDelayedBandStateTwo() throws {
        let (rows, start) = capture(startHour: 23, startMinute: 51)
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertEqual(night.startUnix, start,
                       "The coarse state=2 hint may lag recorded nighttime onset")
        XCTAssertEqual(night.endUnix, start + 75 * 60 - 1)
    }

    private func laptopThenSleep(totalMinutes: Int, sleepStateDelay: Int) -> ([V18Sample], Int, Int) {
        let (settled, start) = capture(startHour: 1, startMinute: 45, totalMinutes: totalMinutes,
                                       sleepStateDelay: sleepStateDelay)
        let awakeStart = start - 50 * 60
        let active = (0..<600).map { row(awakeStart - 600 + $0, seconds: $0,
                                        sleeping: false, sleepState: 0) }
        // Low motion persists through both activities. The independent HR
        // transition and delayed state hint distinguish the settled portion.
        let laptop = (0..<(50 * 60)).map { second in
            row(awakeStart + second, seconds: second + 600,
                sleeping: true, sleepState: second % 120 < 60 ? 0 : 1,
                heartRate: second < 30 * 60 ? 86 : 76)
        }
        return (active + laptop + Array(settled.dropFirst(900)), awakeStart, start)
    }

    func testMotionlessLaptopUseBeforeSleepDoesNotSetOvernightOnset() throws {
        let (rows, _, start) = laptopThenSleep(totalMinutes: 130, sleepStateDelay: 14 * 60)
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertEqual(night.startUnix, start)
        XCTAssertEqual(night.endUnix, start + 130 * 60 - 1)
    }

    func testLookbackLimitDoesNotInventOnsetOrDiscardSleep() throws {
        let (rows, _, start) = laptopThenSleep(totalMinutes: 75, sleepStateDelay: 50 * 60)
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        // With 90-min backtrack window, the algorithm can look back further through valid quiet+low-HR evidence.
        // The laptop period (HR 86/76) fails the HR transition check vs confirmed sleep HR (~56), so backtrack
        // stops at the transition to low HR (start). The onset is accurately set to start, neither pushed
        // back to awakeStart (which would invent sleep during laptop use) nor pushed forward to hintStart
        // (which would discard 50 minutes of genuine sleep).
        XCTAssertEqual(night.startUnix, start,
                       "Onset must be at true physiological sleep onset (start), neither inventing laptop onset nor discarding genuine sleep")
        XCTAssertEqual(night.endUnix, start + 75 * 60 - 1)
    }

    func testDelayedBandHintDoesNotTrimAStableLowHROvernightPrefix() throws {
        let (rows, start) = capture(startHour: 1, startMinute: 45, totalMinutes: 130, sleepStateDelay: 50 * 60)
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertEqual(night.startUnix, start)
    }

    func testLateEveningBefore2200StillTrimsUnconfirmedRest() throws {
        let (rows, start) = capture(startHour: 21, startMinute: 45, totalMinutes: 105)
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertEqual(night.startUnix, start + 14 * 60,
                       "Pre-22:00 lying-still evidence must not bypass the safety gate")
    }

    func testDaytimeStillnessWithoutBandSleepEvidenceIsNotSleep() {
        let (rows, _) = capture(startHour: 13, startMinute: 0, evidence: false)
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty)
    }

    func testSustainedBandUpRunIsNeverReportedAsDeepOrREM() throws {
        let (original, start) = capture(startHour: 23, startMinute: 51)
        let upStart = start + 30 * 60
        let upEnd = upStart + 16 * 60
        let rows = original.map { sample -> V18Sample in
            guard upStart <= sample.unix, sample.unix < upEnd else { return sample }
            return row(sample.unix, seconds: Int(sample.header.recordIndex),
                       sleeping: false, sleepState: 3)
        }
        let period = SleepPeriod(
            startUnix: start, endUnix: start + 75 * 60 - 1,
            quietFraction: 0.95, meanHR: 60, wakeEvents: 1
        )
        let stages = SleepStager.stage(samples: rows, period: period)
        let duringUp = stages.segments.filter {
            max($0.startUnix, upStart) < min($0.endUnix, upEnd)
        }
        let nonWakeSeconds = duringUp.reduce(0) { acc, segment in
            acc + (segment.stage == .wake ? 0
                : max(0, min(segment.endUnix, upEnd) - max(segment.startUnix, upStart)))
        }
        XCTAssertLessThanOrEqual(nonWakeSeconds, 30,
            "Sustained explicit 16-minute band-up evidence must not be labeled Deep or REM")
    }

    func testSleepStateHintDoesNotFabricateMissingMotionRecords() {
        let (rows, _) = capture(startHour: 23, startMinute: 51)
        let invalid = rows.map { sample -> V18Sample in
            V18Sample(header: sample.header, heartRate: sample.heartRate,
                rrIntervalsMS: sample.rrIntervalsMS, dynamicAccelG: nil,
                gravityXG: sample.gravityXG, gravityYG: sample.gravityYG,
                gravityZG: sample.gravityZG,
                stepCounter: sample.stepCounter, stepCadence: sample.stepCadence,
                activityClass: sample.activityClass,
                skinTempC: sample.skinTempC, tempAux1C: sample.tempAux1C,
                tempAux2C: sample.tempAux2C, sleepStateByte: sample.sleepStateByte,
                sleepState: sample.sleepState,
                cardiacFlags: sample.cardiacFlags, hrQualityFlags: sample.hrQualityFlags,
                spo2CandidateRaw: sample.spo2CandidateRaw,
                spo2CandidatePct: sample.spo2CandidatePct,
                spo2CandidateKind: sample.spo2CandidateKind,
                signalQualityLogVariance: sample.signalQualityLogVariance,
                psnrB: sample.psnrB, psnrA: sample.psnrA)
        }
        XCTAssertTrue(SleepDetect.detect(invalid).isEmpty)
    }

    func testGenuineSleepExceeding12HoursIsNotDiscarded() throws {
        // Issue #126: Genuine extended sleep (>12 hours) during illness or deep recovery
        // must not be discarded with a hard 12-hour ceiling.
        let (rows, start) = capture(startHour: 22, startMinute: 0, totalMinutes: 13 * 60)
        let periods = SleepDetect.detect(rows)
        XCTAssertFalse(periods.isEmpty, "Genuine sleep >12 hours must be detected and not dropped")
        let night = try XCTUnwrap(periods.first)
        XCTAssertEqual(night.startUnix, start)
        XCTAssertEqual(night.endUnix, start + 13 * 3600 - 1)
        XCTAssertGreaterThan(night.durationS, 12 * 3600)
    }

    func testLyingAwakeInBedWithLowMotionDoesNotTriggerFalseSleepOnset() {
        // Issue #126: Sedentary evening awake stillness with low motion but WITHOUT
        // autonomic heart-rate drop must not trigger a false sleep onset.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = Int(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 18, hour: 22, minute: 30
        ))!.timeIntervalSince1970)

        // 90 minutes of active awake baseline (HR ~90, moving)
        var records: [V18Sample] = []
        for second in 0..<5400 {
            records.append(row(start - 5400 + second, seconds: second,
                               sleeping: false, sleepState: 0))
        }
        // 75 minutes of lying awake in bed (low motion 0.02g, but HR remains high ~88 bpm, no drop)
        for second in 0..<(75 * 60) {
            let sample = V18Sample(
                header: BandRecordHeader(version: 18, flags: 0x80,
                    recordIndex: UInt32(5400 + second), unix: UInt32(start + second), subsecQ15: 0),
                heartRate: 88, // No significant HR drop compared to active 91 bpm
                rrIntervalsMS: [],
                dynamicAccelG: 0.015, // Low motion
                gravityXG: 0, gravityYG: 0, gravityZG: 1,
                stepCounter: nil, stepCadence: nil, activityClass: 0,
                skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
                sleepStateByte: 0x10, sleepState: 1, // band says still (1), not sleep (2)
                cardiacFlags: nil, hrQualityFlags: nil,
                spo2CandidateRaw: nil, spo2CandidatePct: nil,
                spo2CandidateKind: .absent,
                signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
            )
            records.append(sample)
        }
        // Should NOT be detected as confirmed overnight sleep because HR drop is absent
        XCTAssertTrue(SleepDetect.detect(records).isEmpty,
                      "Lying awake with low motion but without HR drop must not be detected as sleep")
    }

    // MARK: - Delayed Band State=2 Onset Regression Tests

    private func buildDelayedOnsetScenario(
        startHour: Int, startMinute: Int,
        preSleepMinutes: Int = 15,
        elevatedHRMinutes: Int,
        sleepState: Int = 1,
        elevatedHR: Int = 95,
        confirmedSleepMinutes: Int = 12,
        confirmedHR: Int = 77,
        confirmedSleepState: Int = 2
    ) -> ([V18Sample], Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = Int(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 23, hour: startHour, minute: startMinute
        ))!.timeIntervalSince1970)

        var records: [V18Sample] = []
        // Active awake baseline before onset (high motion, high HR)
        for second in 0..<(preSleepMinutes * 60) {
            records.append(row(start - preSleepMinutes * 60 + second, seconds: second,
                               sleeping: false, sleepState: 0, heartRate: elevatedHR + 10, dynamicAccelG: 0.23))
        }
        // Elevated HR quiet period (lying awake, state=0/1) - HR drops slightly but not enough
        for second in 0..<(elevatedHRMinutes * 60) {
            records.append(row(start + second, seconds: second + preSleepMinutes * 60,
                               sleeping: true, sleepState: sleepState, heartRate: elevatedHR))
        }
        // Sustained state=2 with lower HR (true sleep)
        for second in 0..<(confirmedSleepMinutes * 60) {
            records.append(row(start + elevatedHRMinutes * 60 + second, seconds: second + (preSleepMinutes + elevatedHRMinutes) * 60,
                               sleeping: true, sleepState: confirmedSleepState, heartRate: confirmedHR))
        }
        return (records, start)
    }

    /// Test 1: 44-minute delayed band state=2 hint (reported case from 2026-11-22/23)
    /// Band state=2 arrives at 01:43 but true HR transition was at ~02:28.
    /// With 90-min backtrack window, should recover onset at 00:59.
    func testFortyFourMinuteDelayedBandStateTwoRecoversTrueOnset() throws {
        let (records, start) = buildDelayedOnsetScenario(
            startHour: 0, startMinute: 59,
            elevatedHRMinutes: 44,
            sleepState: 1,
            confirmedSleepMinutes: 75  // Ensure >=60 min of physiologically confirmed sleep
        )
        let night = try XCTUnwrap(SleepDetect.detect(records).first)
        XCTAssertEqual(night.startUnix, start + 44 * 60,
                       "Elevated-HR quiet time must not be counted as sleep before the observed HR drop")
    }

    /// Test 2: Normal 14-minute delayed hint (existing behavior preserved)
    func testFourteenMinuteDelayedBandStateTwoPreservesExistingBehavior() throws {
        let (records, start) = buildDelayedOnsetScenario(
            startHour: 1, startMinute: 45,
            elevatedHRMinutes: 14,
            sleepState: 1,
            confirmedSleepMinutes: 50  // 14 + 50 = 64 min > 60 min minimum
        )
        let night = try XCTUnwrap(SleepDetect.detect(records).first)
        XCTAssertEqual(night.startUnix, start,
                       "14-minute delay (within original 30-min lookback) must still work")
    }

    /// Test 3: 90-minute delayed hint at the supported boundary
    func testNinetyMinuteDelayedBandStateTwoAtBoundary() throws {
        let (records, start) = buildDelayedOnsetScenario(
            startHour: 1, startMinute: 0,
            elevatedHRMinutes: 90,
            sleepState: 1
        )
        let night = try XCTUnwrap(SleepDetect.detect(records).first)
        XCTAssertEqual(night.startUnix, start,
                       "90-minute delay (at backtrack boundary) must recover onset")
    }

    /// Test 4: Delay beyond allowed backtracking window (95 minutes)
    func testBeyondBacktrackWindowDoesNotRecoverOnset() throws {
        // 95 min delay exceeds 90-min backtrack window
        let (records, start) = buildDelayedOnsetScenario(
            startHour: 1, startMinute: 0,
            elevatedHRMinutes: 95,
            sleepState: 1
        )
        let night = try XCTUnwrap(SleepDetect.detect(records).first)
        // Should fall back to actigraphy onset (start of quiet period)
        // because backtrack window cannot reach the HR transition
        XCTAssertEqual(night.startUnix, start,
                       "Delay beyond 90-min window must not invent onset from missing data")
    }

    /// Test 5: Awake-in-bed false positive with low motion but no HR drop
    func testAwakeInBedNoHRDropDoesNotTriggerSleep() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = Int(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 18, hour: 22, minute: 30
        ))!.timeIntervalSince1970)

        var records: [V18Sample] = []
        // 90 min active baseline
        for second in 0..<5400 {
            records.append(row(start - 5400 + second, seconds: second,
                               sleeping: false, sleepState: 0, heartRate: 92))
        }
        // 80 min lying awake in bed - low motion but HR stays elevated (no autonomic drop)
        for second in 0..<(80 * 60) {
            records.append(row(start + second, seconds: second + 5400,
                               sleeping: true, sleepState: 1, heartRate: 89,
                               dynamicAccelG: 0.015))
        }
        // No state=2, no HR drop - should not detect sleep
        XCTAssertTrue(SleepDetect.detect(records).isEmpty,
                      "Awake in bed without HR drop must not be detected as sleep")
    }

    /// Test 6: Bathroom awakening (short state=3) within sleep
    func testShortBathroomAwakeningDoesNotSplitSleep() throws {
        let (records, start) = buildDelayedOnsetScenario(
            startHour: 0, startMinute: 59,
            elevatedHRMinutes: 14,
            sleepState: 1
        )
        // Insert a 5-minute state=3 (up) at 2 hours into sleep
        let bathroomStart = start + 14 * 60 + 2 * 3600
        var modified = records
        for second in 0..<(5 * 60) {
            if let idx = modified.firstIndex(where: { $0.unix == bathroomStart + second }) {
                modified[idx] = row(bathroomStart + second, seconds: Int(modified[idx].header.recordIndex),
                                    sleeping: false, sleepState: 3, heartRate: 85)
            }
        }
        let night = try XCTUnwrap(SleepDetect.detect(modified).first)
        XCTAssertEqual(night.startUnix, start,
                       "Short bathroom awakening must not reset sleep onset")
        // Duration should still be ~7+ hours
        XCTAssertGreaterThan(night.durationS, 7 * 3600)
    }

    /// Test 7: Off-wrist period (no wearing samples) during sleep
    func testOffWristPeriodDoesNotSplitSleep() throws {
        let (records, start) = buildDelayedOnsetScenario(
            startHour: 0, startMinute: 59,
            elevatedHRMinutes: 14,
            sleepState: 1
        )
        // Insert 10-minute off-wrist period (wearing=false)
        let offWristStart = start + 14 * 60 + 3 * 3600
        var modified = records
        for second in 0..<(10 * 60) {
            if let idx = modified.firstIndex(where: { $0.unix == offWristStart + second }) {
                let sample = modified[idx]
                modified[idx] = V18Sample(
                    header: sample.header,
                    heartRate: 0,
                    rrIntervalsMS: [],
                    dynamicAccelG: nil,
                    gravityXG: nil, gravityYG: nil, gravityZG: nil,
                    stepCounter: nil, stepCadence: nil, activityClass: 0,
                    skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
                    sleepStateByte: nil, sleepState: nil,
                    cardiacFlags: nil, hrQualityFlags: nil,
                    spo2CandidateRaw: nil, spo2CandidatePct: nil,
                    spo2CandidateKind: .absent,
                    signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
                )
            }
        }
        let night = try XCTUnwrap(SleepDetect.detect(modified).first)
        XCTAssertEqual(night.startUnix, start,
                       "Off-wrist period must not reset sleep onset")
    }

    /// Test 8: Missing, duplicated and out-of-order packets
    func testPacketAnomaliesDoNotAffectOnset() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = Int(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 23, hour: 1, minute: 0
        ))!.timeIntervalSince1970)

        var records: [V18Sample] = []
        // Build normal sleep with 14-min delay
        for second in 0..<(15 * 60) {
            records.append(row(start - 15 * 60 + second, seconds: second,
                               sleeping: false, sleepState: 0, heartRate: 95))
        }
        for second in 0..<(14 * 60) {
            records.append(row(start + second, seconds: second + 15 * 60,
                               sleeping: true, sleepState: 1, heartRate: 95))
        }
        for second in 0..<(120 * 60) {
            records.append(row(start + 14 * 60 + second, seconds: second + 29 * 60,
                               sleeping: true, sleepState: 2, heartRate: 77))
        }

        // Add duplicate packets (same timestamp)
        var withDuplicates = records
        for sample in records[0..<min(100, records.count)] {
            withDuplicates.append(sample) // duplicate
        }
        // Add out-of-order packets
        withDuplicates.append(row(start + 5000, seconds: 5000, sleeping: true, sleepState: 2, heartRate: 77))
        withDuplicates.sort { $0.unix < $1.unix }

        let night = try XCTUnwrap(SleepDetect.detect(withDuplicates).first)
        XCTAssertEqual(night.startUnix, start,
                       "Duplicate and out-of-order packets must not affect onset")
    }

    /// Test 9: Stable low-HR sleep without clear HR transition
    func testStableLowHRWithoutTransitionKeepsActigraphyOnset() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = Int(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 23, hour: 1, minute: 0
        ))!.timeIntervalSince1970)

        var records: [V18Sample] = []
        // All low HR from the beginning - no elevated period
        for second in 0..<(15 * 60) {
            records.append(row(start - 15 * 60 + second, seconds: second,
                               sleeping: false, sleepState: 0, heartRate: 60))
        }
        for second in 0..<(14 * 60) {
            records.append(row(start + second, seconds: second + 15 * 60,
                               sleeping: true, sleepState: 1, heartRate: 60))
        }
        for second in 0..<(120 * 60) {
            records.append(row(start + 14 * 60 + second, seconds: second + 29 * 60,
                               sleeping: true, sleepState: 2, heartRate: 60))
        }

        let night = try XCTUnwrap(SleepDetect.detect(records).first)
        // Without elevated HR prefix, refineOvernightOnset should not trigger
        // because prefix median won't exceed confirmedHR + 8
        XCTAssertEqual(night.startUnix, start,
                       "Stable low HR without transition must keep actigraphy onset")
    }

    /// Test 10: Midnight boundary handling (sleep crossing midnight)
    func testMidnightBoundaryOnsetDetection() throws {
        // Sleep starting at 23:45 (before midnight) with delayed state=2
        let (records, start) = buildDelayedOnsetScenario(
            startHour: 23, startMinute: 45,
            elevatedHRMinutes: 44,
            sleepState: 1,
            confirmedSleepMinutes: 20  // 44 + 20 = 64 min > 60 min minimum
        )
        let night = try XCTUnwrap(SleepDetect.detect(records).first)
        XCTAssertEqual(night.startUnix, start,
                       "Onset before midnight with delayed state=2 must backtrack correctly")
    }

    /// Test 11: Timezone boundary (sleep crossing DST or timezone change)
    func testTimezoneBoundaryOnsetDetection() throws {
        // Use a timezone with DST transition
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = Int(calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 8, hour: 1, minute: 0 // DST spring forward
        ))!.timeIntervalSince1970)

        var records: [V18Sample] = []
        for second in 0..<(15 * 60) {
            records.append(row(start - 15 * 60 + second, seconds: second,
                               sleeping: false, sleepState: 0, heartRate: 95))
        }
        for second in 0..<(44 * 60) {
            records.append(row(start + second, seconds: second + 15 * 60,
                               sleeping: true, sleepState: 1, heartRate: 95))
        }
        for second in 0..<(20 * 60) {  // 44 + 20 = 64 min > 60 min minimum
            records.append(row(start + 44 * 60 + second, seconds: second + 59 * 60,
                               sleeping: true, sleepState: 2, heartRate: 77))
        }

        let night = try XCTUnwrap(SleepDetect.detect(records).first)
        XCTAssertEqual(night.startUnix, start,
                       "DST boundary must not affect onset detection")
    }

    /// Test 12: Existing PR #55/#72 regression - 14-min delay with laptop use
    func testPR55_PR72_LaptopUseRegression() throws {
        let (rows, _, start) = laptopThenSleep(totalMinutes: 130, sleepStateDelay: 14 * 60)
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertEqual(night.startUnix, start,
                       "PR #55/#72: Laptop use before sleep must not set overnight onset")
    }

    /// Test 13: 30-minute minimum delay gate - refinement not attempted if hint < 30 min
    func testMinimumDelayGatePreventsPrematureRefinement() throws {
        // 20-minute delay (less than 30-min minimum)
        let (records, start) = buildDelayedOnsetScenario(
            startHour: 1, startMinute: 45,
            elevatedHRMinutes: 20,
            sleepState: 1,
            confirmedSleepMinutes: 45  // 20 + 45 = 65 min > 60 min minimum
        )
        let night = try XCTUnwrap(SleepDetect.detect(records).first)
        // Should NOT refine because hintStart - start < minimumDelay (30 min)
        // Falls back to actigraphy onset
        XCTAssertEqual(night.startUnix, start,
                       "Delay < 30 min must not trigger refinement")
    }

    /// Test 14: Anchor quiet requirement (270/300 seconds)
    func testAnchorQuietRequirementPreventsNoisyRefinement() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = Int(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 23, hour: 1, minute: 0
        ))!.timeIntervalSince1970)

        var records: [V18Sample] = []
        for second in 0..<(15 * 60) {
            records.append(row(start - 15 * 60 + second, seconds: second,
                               sleeping: false, sleepState: 0, heartRate: 95))
        }
        for second in 0..<(44 * 60) {
            records.append(row(start + second, seconds: second + 15 * 60,
                               sleeping: true, sleepState: 1, heartRate: 95))
        }
        // First 5 minutes of state=2 are noisy (accel > 0.08), then quiet
        for second in 0..<(5 * 60) {
            records.append(row(start + 44 * 60 + second, seconds: second + 59 * 60,
                               sleeping: true, sleepState: 2, heartRate: 77,
                               dynamicAccelG: 0.15)) // noisy
        }
        for second in 0..<(120 * 60) {
            records.append(row(start + 49 * 60 + second, seconds: second + 64 * 60,
                               sleeping: true, sleepState: 2, heartRate: 77,
                               dynamicAccelG: 0.02)) // quiet
        }

        let night = try XCTUnwrap(SleepDetect.detect(records).first)
        // Anchor (first 300s of state=2) has only 5 min quiet, need 270s
        // Should NOT refine, keep actigraphy onset
        XCTAssertEqual(night.startUnix, start,
                       "Noisy anchor must prevent refinement")
    }

    /// Test 15: Prefix HR coverage requirement (80% of minimumDelay)
    func testPrefixHRCoverageRequirement() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = Int(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 23, hour: 1, minute: 0
        ))!.timeIntervalSince1970)

        var records: [V18Sample] = []
        // Only 10 minutes of HR data in first 30 minutes (below 80% = 24 min)
        for second in 0..<(15 * 60) {
            records.append(row(start - 15 * 60 + second, seconds: second,
                               sleeping: false, sleepState: 0, heartRate: 95))
        }
        for second in 0..<(44 * 60) {
            let hr = second < 10 * 60 ? 95 : 0 // HR only for first 10 min
            let sample = V18Sample(
                header: BandRecordHeader(version: 18, flags: 0x80,
                    recordIndex: UInt32(second + 15 * 60), unix: UInt32(start + second), subsecQ15: 0),
                heartRate: hr,
                rrIntervalsMS: [],
                dynamicAccelG: 0.02,
                gravityXG: 0, gravityYG: 0, gravityZG: 1,
                stepCounter: nil, stepCadence: nil, activityClass: 0,
                skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
                sleepStateByte: 0x10, sleepState: 1,
                cardiacFlags: nil, hrQualityFlags: nil,
                spo2CandidateRaw: nil, spo2CandidatePct: nil,
                spo2CandidateKind: .absent,
                signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
            )
            records.append(sample)
        }
        for second in 0..<(20 * 60) {  // 44 + 20 = 64 min > 60 min minimum
            records.append(row(start + 44 * 60 + second, seconds: second + 59 * 60,
                               sleeping: true, sleepState: 2, heartRate: 77))
        }

        let night = try XCTUnwrap(SleepDetect.detect(records).first)
        // Prefix HR coverage < 80% of 30 min = 24 min
        // Should NOT refine
        XCTAssertEqual(night.startUnix, start,
                       "Insufficient prefix HR coverage must prevent refinement")
    }
}