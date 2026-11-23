import XCTest
@testable import Strap

/// Regression for the verified 22:00 cutoff: a delayed coarse band sleep hint
/// must not erase physiological overnight onset, while daytime rest still
/// requires independently confirmed band sleep evidence.
final class SleepOvernightOnsetBoundaryTests: XCTestCase {
    func testChangedSleepStagingRecipeInvalidatesVersionFiveSnapshots() {
        XCTAssertGreaterThan(SleepSession.algorithmVersion, 5)
    }

    private func row(_ unix: Int, seconds: Int, sleeping: Bool, sleepState: Int?, heartRate: Int? = nil) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(version: 18, flags: 0x80,
                recordIndex: UInt32(seconds), unix: UInt32(unix), subsecQ15: 0),
            heartRate: heartRate ?? (sleeping ? 56 : 91), rrIntervalsMS: [],
            dynamicAccelG: sleeping ? 0.012 : 0.23,
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
        let (rows, awakeStart, start) = laptopThenSleep(totalMinutes: 75, sleepStateDelay: 50 * 60)
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertEqual(night.startUnix, awakeStart)
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
}
