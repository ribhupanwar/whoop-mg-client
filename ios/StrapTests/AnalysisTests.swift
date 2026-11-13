import XCTest
@testable import Strap

// MARK: - Synthetic sample helpers (no hardware, no capture files)

private func makeSample(
    _ unix: Int,
    hr: Int,
    accel: Double? = 0.0,
    rr: [Int] = [],
    steps: Int? = nil,
    gait: Int? = 0,
    spo2: Int? = nil,
    sleepState: Int? = nil
) -> V18Sample {
    let candidate = V18Decoder.spo2Candidate(raw: spo2)
    return V18Sample(
        header: BandRecordHeader(
            version: 18, flags: 0x80, recordIndex: UInt32(unix),
            unix: UInt32(unix), subsecQ15: 0
        ),
        heartRate: hr,
        rrIntervalsMS: rr,
        dynamicAccelG: accel,
        gravityXG: nil,
        gravityYG: nil,
        gravityZG: nil,
        stepCounter: steps,
        stepCadence: nil,
        activityClass: gait,
        skinTempC: nil,
        tempAux1C: nil,
        tempAux2C: nil,
        sleepStateByte: sleepState.map { $0 << 4 },
        sleepState: sleepState,
        cardiacFlags: nil,
        hrQualityFlags: nil,
        spo2CandidateRaw: spo2,
        spo2CandidatePct: candidate.pct,
        spo2CandidateKind: candidate.kind,
        signalQualityLogVariance: nil,
        psnrB: nil,
        psnrA: nil
    )
}

private func stretch(
    _ start: Int,
    _ seconds: Int,
    hr: Int,
    accel: Double?,
    rr: [Int] = []
) -> [V18Sample] {
    (0..<seconds).map { makeSample(start + $0, hr: hr, accel: accel, rr: rr) }
}

private func stream(
    _ start: Int,
    _ seconds: Int,
    hr: Int,
    accel: Double = 0.0,
    spm: Int = 0,
    gait: Int? = 0,
    withSteps: Bool = true,
    step0: Int = 0
) -> [V18Sample] {
    (0..<seconds).map { index in
        makeSample(
            start + index,
            hr: hr,
            accel: accel,
            steps: withSteps ? step0 + index * spm / 60 : nil,
            gait: gait
        )
    }
}

private func rest(_ start: Int = 0, _ seconds: Int = 900) -> [V18Sample] {
    stream(start, seconds, hr: 70, accel: 0.02)
}

private func coolDown(_ start: Int, _ seconds: Int = 600) -> [V18Sample] {
    stream(start, seconds, hr: 70, accel: 0.02, step0: 9000)
}

private func steadyBaseline(days: Int = 14) -> Baseline {
    Baseline(lnRMSSDMean: 4.0, lnRMSSDSD: 0.3, rhrMean: 55.0, rhrSD: 3.0, days: days)
}

// MARK: - HRV

final class HrvTests: XCTestCase {
    func testCleanSeriesPassesThrough() {
        let series: [Double] = [800, 810, 795, 805, 800]
        XCTAssertEqual(Hrv.nnIntervals(series), series)
    }

    func testEctopicPairRejectedButRecoveryBeatKept() {
        XCTAssertEqual(
            Hrv.nnIntervals([800, 800, 400, 1200, 805, 800]),
            [800, 800, 805, 800]
        )
    }

    func testOutOfRangeRejected() {
        XCTAssertEqual(Hrv.nnIntervals([50, 800, 5000, 810]), [800, 810])
    }

    func testEmpty() {
        XCTAssertEqual(Hrv.nnIntervals([]), [])
    }

    func testLeadingArtefactMustNotBecomeTheReference() {
        var series: [Double] = [449, 840, 838, 744, 794, 849, 837, 859]
        series += Array(repeating: 800, count: 40)
        let kept = Hrv.nnIntervals(series)
        XCTAssertFalse(kept.contains(449))
        XCTAssertGreaterThan(kept.count, 40)
        XCTAssertEqual(Array(kept.prefix(6)), [840, 838, 744, 794, 849, 837])
    }

    func testReferenceRecoversAfterLongArtefactBurst() {
        var series: [Double] = [800, 805]
        for _ in 0..<6 { series += [1500, 350] }
        series += [790, 800, 810]
        XCTAssertEqual(Hrv.nnIntervals(series), [800, 805, 790, 800, 810])
    }

    func testTwoBeatsAreNeededToSeed() {
        XCTAssertEqual(Hrv.nnIntervals([800]), [])
    }

    func testSeedCandidateSurvivesADropout() {
        XCTAssertEqual(Hrv.nnIntervals([800, 5000, 810]), [800, 810])
    }

    func testRmssdKnownVector() {
        // diffs 10, -20, 15 -> mean square 725/3 -> sqrt = 15.5456
        XCTAssertEqual(Hrv.rmssd([800, 810, 790, 805])!, 15.5456, accuracy: 0.001)
    }

    func testRmssdConstantIsZero() {
        XCTAssertEqual(Hrv.rmssd([800, 800, 800]), 0.0)
    }

    func testRmssdNeedsTwoBeats() {
        XCTAssertNil(Hrv.rmssd([800]))
        XCTAssertNil(Hrv.rmssd([]))
    }

    func testSdnnKnownVector() {
        XCTAssertEqual(Hrv.sdnn([100, 102, 104])!, 2.0, accuracy: 0.000001)
    }

    func testPnn50KnownVector() {
        // |60|, |60|, |10| -> two of three exceed 50 ms
        XCTAssertEqual(Hrv.pnn50([800, 860, 800, 810])!, 200.0 / 3.0, accuracy: 0.000001)
    }

    func testPnn50FlatIsZero() {
        XCTAssertEqual(Hrv.pnn50([800, 800, 800]), 0.0)
    }

    func testResultCountsAndLog() {
        let result = Hrv.fromRR([800, 800, 400, 1200, 805, 800])
        XCTAssertEqual(result.beats, 6)
        XCTAssertEqual(result.nnBeats, 4)
        XCTAssertEqual(result.rejectedBeats, 2)
        XCTAssertEqual(result.lnRMSSD!, log(result.rmssdMS!), accuracy: 1e-9)
    }

    func testEmptyResultIsAbsentNotZero() {
        let result = Hrv.fromRR([])
        XCTAssertNil(result.rmssdMS)
        XCTAssertNil(result.lnRMSSD)
        XCTAssertNil(result.meanRRMS)
    }
}

final class RestingHrvTests: XCTestCase {
    func testNeedsALongEnoughQuietRun() {
        let rows = stretch(0, 30, hr: 70, accel: 0.01, rr: [800, 810])
        let result = Hrv.restingHRV(rows)
        XCTAssertEqual(result.windowSeconds, 0)
        XCTAssertNil(result.result.rmssdMS)
    }

    func testMotionSecondsAreExcluded() {
        var rows = stretch(0, 120, hr: 70, accel: 0.01, rr: [800, 810])
        rows += stretch(120, 120, hr: 110, accel: 0.9, rr: [400, 1200])
        let result = Hrv.restingHRV(rows)
        XCTAssertEqual(result.windowSeconds, 120)
        XCTAssertEqual(result.result.beats, 240)
    }

    func testLongestRunWins() {
        var rows = stretch(0, 70, hr: 70, accel: 0.01, rr: [800, 810])
        rows += stretch(200, 200, hr: 70, accel: 0.01, rr: [700, 720])
        let result = Hrv.restingHRV(rows)
        XCTAssertEqual(result.windowSeconds, 200)
        XCTAssertEqual(result.result.meanRRMS!, 710.0, accuracy: 1e-6)
    }

    func testGapSplitsTheRun() {
        var rows = stretch(0, 100, hr: 70, accel: 0.01, rr: [800, 810])
        rows += stretch(500, 100, hr: 70, accel: 0.01, rr: [800, 810])
        XCTAssertEqual(Hrv.restingHRV(rows).windowSeconds, 100)
    }

    func testMissingAccelIsNotAssumedQuiet() {
        let rows = stretch(0, 120, hr: 70, accel: nil, rr: [800, 810])
        XCTAssertEqual(Hrv.restingHRV(rows).windowSeconds, 0)
    }

    func testPoolingWouldInflateRmssd() {
        let quiet = stretch(0, 200, hr: 70, accel: 0.01, rr: [800, 802])
        let moving = stretch(200, 200, hr: 110, accel: 0.9, rr: [760, 850])
        let resting = Hrv.restingHRV(quiet + moving).result
        let pooled = Hrv.fromSamples(quiet + moving)
        XCTAssertLessThan(resting.rmssdMS!, 5.0)
        XCTAssertGreaterThan(pooled.rmssdMS!, 40.0)
    }

    func testRestingHeartRateIsLowestSustainedWindow() {
        var rows = stretch(0, 120, hr: 70, accel: 0.01)
        rows[60] = makeSample(60, hr: 50, accel: 0.01)
        let value = Hrv.restingHeartRate(rows)
        XCTAssertEqual(value!, 69.6667, accuracy: 0.0001)
    }

    func testRestingHeartRateNeedsQuietAndContiguousSeconds() {
        let rows = stretch(0, 120, hr: 60, accel: 0.5)
        XCTAssertNil(Hrv.restingHeartRate(rows))
    }
}

final class StrainTests: XCTestCase {
    func testMaleTrimpOverOneMinute() {
        let rows = stretch(0, 300, hr: 60, accel: 0.01)
            + stretch(300, 60, hr: 150, accel: 0.5)
        let value = Hrv.trimp(rows, maxHR: 180, restingHR: 60, sex: .male)!
        // 60 * (1/60) * 0.75 * 0.64 * exp(1.92 * 0.75)
        XCTAssertEqual(value, 2.0259, accuracy: 0.0001)
    }

    func testFemaleTrimpIsHigherAtTheSameEffort() {
        let rows = stretch(0, 300, hr: 60, accel: 0.01)
            + stretch(300, 60, hr: 150, accel: 0.5)
        let male = Hrv.trimp(rows, maxHR: 180, restingHR: 60, sex: .male)!
        let female = Hrv.trimp(rows, maxHR: 180, restingHR: 60, sex: .female)!
        XCTAssertGreaterThan(female, male)
    }

    func testUnsetSexProducesNoTrimp() {
        let rows = stretch(0, 60, hr: 150, accel: 0.0)
        XCTAssertNil(Hrv.trimp(rows, maxHR: 180, restingHR: 60, sex: .unspecified))
    }

    func testTrimpNeedsMaxAboveResting() {
        let rows = stretch(0, 60, hr: 150, accel: 0.0)
        XCTAssertNil(Hrv.trimp(rows, maxHR: 60, restingHR: 60, sex: .male))
    }

    func testStrainScaleConstant() {
        XCTAssertEqual(Hrv.strainScore(150.0)!, 21.0 * (1.0 - 1.0 / exp(1.0)), accuracy: 0.000001)
        XCTAssertEqual(Hrv.strainScore(0.0), 0.0)
        XCTAssertNil(Hrv.strainScore(nil))
        XCTAssertNil(Hrv.strainScore(-1))
    }

    func testStrainLabels() {
        XCTAssertEqual(Hrv.strainLabel(nil), "unknown")
        XCTAssertEqual(Hrv.strainLabel(5), "light")
        XCTAssertEqual(Hrv.strainLabel(12), "moderate")
        XCTAssertEqual(Hrv.strainLabel(16), "high")
        XCTAssertEqual(Hrv.strainLabel(20), "all-out")
    }
}

// MARK: - Activity detection

final class ActivityDetectTests: XCTestCase {
    func testRunDetectedAndLabelledFromGait() {
        var rows = rest()
        rows += stream(900, 1200, hr: 150, accel: 0.4, spm: 160, gait: 2, step0: 100)
        rows += coolDown(2100)
        let sessions = ActivityDetect.detect(rows)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].kind, "run")
        XCTAssertEqual(sessions[0].minutes, 20.0, accuracy: 1e-6)
        XCTAssertEqual(sessions[0].runTicks, 1200)
        XCTAssertGreaterThan(sessions[0].steps, 3000)
        XCTAssertEqual(sessions[0].meanHR!, 150.0, accuracy: 1e-6)
    }

    func testWalkBelowThresholdDetectedFromGaitAndSteps() {
        var rows = rest()
        rows += stream(900, 1200, hr: 95, accel: 0.12, spm: 110, gait: 1, step0: 100)
        rows += coolDown(2100)
        let sessions = ActivityDetect.detect(rows)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].kind, "walk")
    }

    func testElevatedHeartRateWithoutGaitIsAWorkout() {
        var rows = rest()
        rows += stream(900, 1200, hr: 130, accel: 0.25, gait: 0, step0: 100)
        rows += coolDown(2100)
        let sessions = ActivityDetect.detect(rows)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].kind, "workout")
    }

    func testFourMinuteBurstIsNotASession() {
        var rows = rest()
        rows += stream(900, 240, hr: 150, accel: 0.4, spm: 160, gait: 2, step0: 100)
        rows += coolDown(1140)
        XCTAssertTrue(ActivityDetect.detect(rows).isEmpty)
    }

    func testBriefStopInsideSessionIsClosed() {
        var rows = rest()
        rows += stream(900, 600, hr: 150, accel: 0.4, spm: 160, gait: 2, step0: 100)
        rows += stream(1500, 120, hr: 90, accel: 0.02, step0: 1700)
        rows += stream(1620, 600, hr: 150, accel: 0.4, spm: 160, gait: 2, step0: 1700)
        rows += coolDown(2220)
        let sessions = ActivityDetect.detect(rows)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].minutes, 22.0, accuracy: 1e-6)
        XCTAssertEqual(sessions[0].kind, "run")
    }

    func testRestingCadenceByteCreatesNothing() {
        XCTAssertTrue(ActivityDetect.detect(stream(0, 1800, hr: 70, accel: 0.02)).isEmpty)
    }

    func testGaitWorksWithoutABaseline() {
        let rows = stream(0, 1200, hr: 150, accel: 0.4, spm: 160, gait: 2)
        let sessions = ActivityDetect.detect(rows)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].kind, "run")
    }

    func testNoStepsAndNoGaitIsCardio() {
        var rows = stream(0, 900, hr: 70, accel: 0.02, gait: nil, withSteps: false)
        rows += stream(900, 1200, hr: 130, accel: 0.25, gait: nil, withSteps: false)
        let sessions = ActivityDetect.detect(rows)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].kind, "cardio")
    }

    func testUnverifiedGaitAloneDoesNotCreateActivityWithoutSteps() {
        let rows = stream(0, 1200, hr: 70, accel: 0.4, gait: 2, withSteps: false)
        XCTAssertTrue(ActivityDetect.detect(rows).isEmpty)
    }

    func testArmMotionWhileStillIsNotASession() {
        XCTAssertTrue(ActivityDetect.detect(stream(0, 1800, hr: 70, accel: 0.5)).isEmpty)
    }

    func testSteppingWithoutGaitClassifiesByRate() {
        var rows = rest()
        rows += stream(900, 1200, hr: 80, accel: 0.12, spm: 110, gait: nil, step0: 100)
        rows += coolDown(2100)
        let sessions = ActivityDetect.detect(rows)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].kind, "walk")
    }

    func testOffWristSecondsAreIgnored() {
        var rows = rest()
        rows += stream(900, 1200, hr: 0, accel: 0.4, spm: 160, gait: 2, step0: 100)
        rows += coolDown(2100)
        XCTAssertTrue(ActivityDetect.detect(rows).isEmpty)
    }
}

// MARK: - Sleep detection

final class SleepDetectTests: XCTestCase {
    func testOvernightFiftyMinuteStillnessIsNotSleep() {
        let night = Calendar.current.date(
            bySettingHour: 23, minute: 0, second: 0, of: Date()
        )!
        let start = Int(night.timeIntervalSince1970)
        var rows = stretch(start, 600, hr: 100, accel: 0.5)
        rows += stretch(start + 600, 3000, hr: 60, accel: 0.02)
        rows += stretch(start + 3600, 600, hr: 100, accel: 0.5)
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty)
    }

    func testEveningLyingStillForFortyFiveMinutesIsNotSleep() {
        let evening = Calendar.current.date(
            bySettingHour: 19, minute: 0, second: 0, of: Date()
        )!
        let start = Int(evening.timeIntervalSince1970)
        var rows = stretch(start, 600, hr: 100, accel: 0.5)
        rows += stretch(start + 600, 2700, hr: 65, accel: 0.02)
        rows += stretch(start + 3300, 600, hr: 100, accel: 0.5)
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty)
    }

    func testQuietPeriodWithHrDropIsSleep() {
        var rows = stretch(0, 600, hr: 100, accel: 0.5)
        rows += stretch(600, 3600, hr: 60, accel: 0.02)
        rows += stretch(4200, 600, hr: 100, accel: 0.5)
        let periods = SleepDetect.detect(rows)
        XCTAssertEqual(periods.count, 1)
        XCTAssertEqual(periods[0].startUnix, 600)
        XCTAssertEqual(periods[0].durationS, 3600)
        XCTAssertEqual(periods[0].meanHR, 60.0, accuracy: 1e-6)
    }

    func testSustainedBandUpVetoesFalseSleep() {
        var rows = stretch(0, 600, hr: 100, accel: 0.5)
        rows += (600..<4200).map {
            makeSample($0, hr: 60, accel: 0.02, sleepState: 3)
        }
        rows += stretch(4200, 600, hr: 100, accel: 0.5)
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty)
    }

    func testBandStillDoesNotForceSleepOrOverrideHrEvidence() {
        var rows = stretch(0, 600, hr: 100, accel: 0.5)
        rows += (600..<4200).map {
            makeSample($0, hr: 100, accel: 0.02, sleepState: 1)
        }
        rows += stretch(4200, 600, hr: 100, accel: 0.5)
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty)
    }

    func testBandSleepSupportsExistingActigraphyEvidence() {
        var rows = stretch(0, 600, hr: 100, accel: 0.5)
        rows += (600..<4200).map {
            makeSample($0, hr: 60, accel: 0.02, sleepState: 2)
        }
        rows += stretch(4200, 600, hr: 100, accel: 0.5)
        XCTAssertEqual(SleepDetect.detect(rows).count, 1)
    }

    func testSittingStillWithoutHrDropIsNotSleep() {
        var rows = stretch(0, 600, hr: 100, accel: 0.5)
        rows += stretch(600, 3600, hr: 100, accel: 0.02)
        rows += stretch(4200, 600, hr: 100, accel: 0.5)
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty)
    }

    func testShortQuietPeriodIsNotSleep() {
        var rows = stretch(0, 600, hr: 100, accel: 0.5)
        rows += stretch(600, 1200, hr: 60, accel: 0.02)
        rows += stretch(1800, 600, hr: 100, accel: 0.5)
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty)
    }

    func testBriefMovementIsClosedIntoOnePeriod() {
        var rows = stretch(0, 600, hr: 100, accel: 0.5)
        rows += stretch(600, 1200, hr: 60, accel: 0.02)
        rows += stretch(1800, 120, hr: 70, accel: 0.5)
        rows += stretch(1920, 1200, hr: 60, accel: 0.02)
        rows += stretch(3120, 600, hr: 100, accel: 0.5)
        let periods = SleepDetect.detect(rows, minSleepS: 1800)
        XCTAssertEqual(periods.count, 1)
        XCTAssertEqual(periods[0].durationS, 2520)
        XCTAssertEqual(periods[0].quietFraction, 2400.0 / 2520.0, accuracy: 1e-6)
    }

    func testLongMovementSplitsAndFragmentsAreTooShort() {
        var rows = stretch(0, 600, hr: 100, accel: 0.5)
        rows += stretch(600, 1200, hr: 60, accel: 0.02)
        rows += stretch(1800, 400, hr: 80, accel: 0.5)
        rows += stretch(2200, 1200, hr: 60, accel: 0.02)
        rows += stretch(3400, 600, hr: 100, accel: 0.5)
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty)
    }

    func testNoActiveSecondsMeansNoReference() {
        XCTAssertTrue(SleepDetect.detect(stretch(0, 3600, hr: 60, accel: 0.02)).isEmpty)
    }

    func testMissingAccelIsNotQuiet() {
        var rows = stretch(0, 600, hr: 100, accel: 0.5)
        rows += stretch(600, 3600, hr: 60, accel: nil)
        rows += stretch(4200, 600, hr: 100, accel: 0.5)
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty)
    }

    func testEmpty() {
        XCTAssertTrue(SleepDetect.detect([]).isEmpty)
    }

    func testTotalHoursSumsPeriods() {
        var rows = stretch(0, 600, hr: 100, accel: 0.5)
        rows += stretch(600, 3600, hr: 60, accel: 0.02)
        rows += stretch(4200, 1800, hr: 100, accel: 0.5)
        rows += stretch(6000, 3600, hr: 60, accel: 0.02)
        rows += stretch(9600, 600, hr: 100, accel: 0.5)
        XCTAssertEqual(SleepDetect.totalHours(SleepDetect.detect(rows)), 2.0, accuracy: 1e-6)
    }
}

// MARK: - Consistency and composite

final class SleepReportTests: XCTestCase {
    func testConsistencyCountsNightsNearBothMedians() {
        let nights = [
            NightSpan(startUnix: 0, endUnix: 480 * 60),
            NightSpan(startUnix: 30 * 60, endUnix: 500 * 60),
            NightSpan(startUnix: 60 * 60, endUnix: 520 * 60),
            NightSpan(startUnix: 600 * 60, endUnix: 900 * 60)
        ]
        let result = SleepReport.consistency(nights: nights)
        XCTAssertEqual(result.pct, 75.0)
        XCTAssertEqual(result.nights, 4)
    }

    func testConsistencyNeedsTwoNights() {
        let result = SleepReport.consistency(
            nights: [NightSpan(startUnix: 0, endUnix: 480 * 60)]
        )
        XCTAssertNil(result.pct)
        XCTAssertEqual(result.nights, 1)
    }

    func testCompositeAtNeedAndHighEfficiency() {
        let periods = [
            SleepPeriod(
                startUnix: 0, endUnix: 8 * 3600 - 1,
                quietFraction: 0.9, meanHR: 50, wakeEvents: 0
            )
        ]
        let nights = [
            NightSpan(startUnix: 0, endUnix: 8 * 3600 - 1),
            NightSpan(startUnix: 86_400, endUnix: 86_400 + 8 * 3600 - 1)
        ]
        let analysis = SleepReport.analyze(
            samples: [], periods: periods, needHours: 8,
            nights: nights, sleepBaseline: nil
        )
        XCTAssertNotNil(analysis)
        XCTAssertEqual(analysis!.hours, 8.0, accuracy: 1e-6)
        // 8h in bed at 90% efficiency means 7h12m asleep, not 8h.
        XCTAssertEqual(analysis!.hoursVsNeededPct, 90.0)
        XCTAssertEqual(analysis!.efficiencyPct, 90.0)
        XCTAssertEqual(analysis!.consistencyPct, 100.0)
        XCTAssertEqual(analysis!.performancePct!, 93.3, accuracy: 0.001)
    }

    func testEmptyPeriodsProduceNoAnalysis() {
        XCTAssertNil(
            SleepReport.analyze(samples: [], periods: [], needHours: 8, nights: [], sleepBaseline: nil)
        )
    }

    func testSleepStressSplitUsesFiveMinuteWindows() {
        let period = SleepPeriod(
            startUnix: 0, endUnix: 599, quietFraction: 1.0, meanHR: 50, wakeEvents: 0
        )
        let samples = stretch(0, 600, hr: 50, accel: 0.01, rr: [800, 810])
        // ln(10) is the rmssd of an alternating 800/810 train.
        let baseline = Baseline(
            lnRMSSDMean: log(10.0), lnRMSSDSD: 0.3, rhrMean: 50, rhrSD: 2, days: 7
        )
        let split = SleepReport.stressSplit(
            samples: samples, periods: [period], baseline: baseline
        )
        XCTAssertEqual(split.windows, 2)
        XCTAssertEqual(split.lowPct, 100.0)
        XCTAssertEqual(split.highPct, 0.0)
    }

    func testSleepStressNeedsSevenNights() {
        let split = SleepReport.stressSplit(
            samples: [], periods: [], baseline: steadyBaseline(days: 6)
        )
        XCTAssertNil(split.highPct)
        XCTAssertNotNil(split.reason)
    }
}

// MARK: - Recovery, stress and SpO2

final class RecoveryTests: XCTestCase {
    func testNoBaselineGivesNoScore() {
        let result = Recovery.score(
            lnRMSSD: 4.0, rhr: 55.0, sleepHours: 8, sleepNeedHours: 8, baseline: nil
        )
        XCTAssertNil(result.score)
        XCTAssertEqual(result.band, "unavailable")
    }

    func testShortBaselineGivesNoScore() {
        let result = Recovery.score(
            lnRMSSD: 4.0, rhr: 55.0, sleepHours: 8, sleepNeedHours: 8,
            baseline: steadyBaseline(days: 3)
        )
        XCTAssertNil(result.score)
    }

    func testMissingHrvOrRhrGivesNoScore() {
        XCTAssertNil(
            Recovery.score(
                lnRMSSD: nil, rhr: 55, sleepHours: 8, sleepNeedHours: 8,
                baseline: steadyBaseline()
            ).score
        )
        XCTAssertNil(
            Recovery.score(
                lnRMSSD: 4, rhr: nil, sleepHours: 8, sleepNeedHours: 8,
                baseline: steadyBaseline()
            ).score
        )
    }

    func testAtBaselineWithFullSleep() {
        let result = Recovery.score(
            lnRMSSD: 4.0, rhr: 55.0, sleepHours: 8, sleepNeedHours: 8,
            baseline: steadyBaseline()
        )
        XCTAssertEqual(result.score!, 65.0, accuracy: 1e-6)
        XCTAssertEqual(result.band, "yellow")
    }

    func testMissingSleepRenormalises() {
        let result = Recovery.score(
            lnRMSSD: 4.0, rhr: 55.0, sleepHours: nil, sleepNeedHours: nil,
            baseline: steadyBaseline()
        )
        XCTAssertEqual(result.score!, 50.0, accuracy: 1e-6)
        XCTAssertNil(result.sleepComponent)
    }

    func testSleepIsCappedAtNeed() {
        let atNeed = Recovery.score(
            lnRMSSD: 4, rhr: 55, sleepHours: 8, sleepNeedHours: 8, baseline: steadyBaseline()
        )
        let overslept = Recovery.score(
            lnRMSSD: 4, rhr: 55, sleepHours: 12, sleepNeedHours: 8, baseline: steadyBaseline()
        )
        XCTAssertEqual(atNeed.score, overslept.score)
    }

    func testZeroVariationIsNeutralNotACrash() {
        let flat = Baseline(lnRMSSDMean: 4, lnRMSSDSD: 0, rhrMean: 55, rhrSD: 0, days: 14)
        let result = Recovery.score(
            lnRMSSD: 4, rhr: 55, sleepHours: 8, sleepNeedHours: 8, baseline: flat
        )
        XCTAssertEqual(result.score!, 65.0, accuracy: 1e-6)
    }

    func testStressIndexCountsDeviationsBelowTheNorm() {
        let baseline = steadyBaseline()
        XCTAssertEqual(Recovery.stressIndex(lnRMSSD: 4.0, baseline: baseline).index, 0.0)
        XCTAssertEqual(Recovery.stressIndex(lnRMSSD: 4.9, baseline: baseline).index, 0.0)
        XCTAssertEqual(Recovery.stressIndex(lnRMSSD: 3.7, baseline: baseline).index!, 1.0, accuracy: 1e-6)
        XCTAssertEqual(Recovery.stressIndex(lnRMSSD: 3.4, baseline: baseline).index!, 2.0, accuracy: 1e-6)
        XCTAssertEqual(Recovery.stressIndex(lnRMSSD: 3.1, baseline: baseline).index!, 3.0, accuracy: 1e-6)
        XCTAssertEqual(Recovery.stressIndex(lnRMSSD: 1.0, baseline: baseline).index, 3.0)
    }

    func testStressBands() {
        let baseline = steadyBaseline()
        XCTAssertEqual(Recovery.stressIndex(lnRMSSD: 4.0, baseline: baseline).band, "low")
        XCTAssertEqual(Recovery.stressIndex(lnRMSSD: 3.71, baseline: baseline).band, "low")
        XCTAssertEqual(Recovery.stressIndex(lnRMSSD: 3.7, baseline: baseline).band, "elevated")
        XCTAssertEqual(Recovery.stressIndex(lnRMSSD: 3.4, baseline: baseline).band, "high")
    }

    func testStressRefusals() {
        XCTAssertNil(Recovery.stressIndex(lnRMSSD: 3.4, baseline: nil).index)
        XCTAssertNil(Recovery.stressIndex(lnRMSSD: 3.4, baseline: steadyBaseline(days: 6)).index)
        XCTAssertNil(Recovery.stressIndex(lnRMSSD: nil, baseline: steadyBaseline()).index)
        let flat = Baseline(lnRMSSDMean: 4, lnRMSSDSD: 0, rhrMean: 55, rhrSD: 3, days: 14)
        XCTAssertNil(Recovery.stressIndex(lnRMSSD: 3.4, baseline: flat).index)
    }

    func testSpo2MeansInBandCandidates() {
        let rows = [
            makeSample(0, hr: 60, spo2: 96),
            makeSample(1, hr: 60, spo2: 97),
            makeSample(2, hr: 60, spo2: 0),
            makeSample(3, hr: 60, spo2: 0x80),
            makeSample(4, hr: 60, spo2: 5)
        ]
        let summary = Recovery.spo2Summary(rows)
        XCTAssertEqual(summary.pct!, 96.5, accuracy: 1e-6)
        XCTAssertEqual(summary.readings, 2)
        XCTAssertEqual(summary.saturated, 1)
        XCTAssertEqual(summary.diagnostic, 1)
        XCTAssertNil(summary.reason)
    }

    func testSpo2WithoutInBandCandidateProducesNoValue() {
        let rows = [
            makeSample(0, hr: 60, spo2: 0),
            makeSample(1, hr: 60, spo2: 0x80),
            makeSample(2, hr: 60, spo2: 5)
        ]
        let summary = Recovery.spo2Summary(rows)
        XCTAssertNil(summary.pct)
        XCTAssertEqual(summary.readings, 0)
    }
}

// MARK: - Respiration

final class RespirationTests: XCTestCase {
    /// A continuous beat train whose R-R swings with a 4 s breathing period.
    private func breathingSamples(beats: Int) -> [V18Sample] {
        var samples: [V18Sample] = []
        var elapsed = 0.0
        for index in 0..<beats {
            let rr = Int((900.0 + 60.0 * sin(2.0 * Double.pi * elapsed / 4.0)).rounded())
            samples.append(makeSample(index, hr: 67, rr: [rr]))
            elapsed += Double(rr) / 1000.0
        }
        return samples
    }

    func testFifteenBreathsPerMinuteIsRecovered() {
        let estimate = Respiration.estimate(breathingSamples(beats: 700))
        XCTAssertTrue(estimate.available, estimate.reason ?? "")
        XCTAssertEqual(estimate.breathsPerMinute!, 15.0, accuracy: 2.5)
        XCTAssertGreaterThan(estimate.windows, 0)
    }

    func testFlatBeatTrainProducesNoRate() {
        let rows = stretch(0, 600, hr: 67, accel: 0.01, rr: [900])
        let estimate = Respiration.estimate(rows)
        XCTAssertFalse(estimate.available)
    }

    func testTooFewBeatsIsUnavailable() {
        let estimate = Respiration.estimate(stretch(0, 3, hr: 67, accel: 0.01, rr: [900]))
        XCTAssertFalse(estimate.available)
        XCTAssertEqual(estimate.beats, 3)
    }
}
