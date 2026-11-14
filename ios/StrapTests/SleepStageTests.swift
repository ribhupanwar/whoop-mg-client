import Foundation
import XCTest
@testable import Strap

private let base = 1_720_000_000
private let alignedBase = base + 20  // An absolute 30-second epoch boundary.

private func stageSample(
    unix: Int,
    hr: Int = 53,
    rr: [Int] = [],
    gravity: (Double, Double, Double)? = (0, 0, 1),
    recordIndex: UInt32 = 0,
    subsecQ15: Int = 0
) -> V18Sample {
    V18Sample(
        header: BandRecordHeader(
            version: 18, flags: 0x80, recordIndex: recordIndex,
            unix: UInt32(unix), subsecQ15: subsecQ15
        ),
        heartRate: hr, rrIntervalsMS: rr, dynamicAccelG: 0.02,
        gravityXG: gravity?.0, gravityYG: gravity?.1, gravityZG: gravity?.2,
        stepCounter: nil, stepCadence: nil, activityClass: nil,
        skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
        sleepStateByte: nil, sleepState: nil, cardiacFlags: nil, hrQualityFlags: nil,
        spo2CandidateRaw: nil, spo2CandidatePct: nil, spo2CandidateKind: .absent,
        signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
    )
}

private func stageWindow(start: Int = alignedBase, seconds: Int) -> SleepPeriod {
    SleepPeriod(
        startUnix: start, endUnix: start + seconds - 1,
        quietFraction: 0.95, meanHR: 53, wakeEvents: 0
    )
}

private func makeNight(
    minutes: Int = 60,
    hr: Double = 53,
    bursts: [(Int, Int)] = [],
    breathing: Bool = true,
    heartRateOverride: Int? = nil
) -> ([V18Sample], SleepPeriod) {
    var samples: [V18Sample] = []
    let seconds = minutes * 60
    for second in 0..<seconds {
        var rate = hr + 1.5 * sin(2 * Double.pi * Double(second) / 2400.0)
        var gravity = (0.0, 0.0, 1.0)
        for (startMinute, endMinute) in bursts
        where startMinute * 60 <= second && second < endMinute * 60 {
            gravity = (
                0.6 * sin(Double(second) * 7.1),
                0.6 * cos(Double(second) * 5.3),
                1.0 + 0.4 * sin(Double(second) * 3.7)
            )
            rate = 88
        }
        let rr = breathing ? [Int(1000 + 45 * sin(2 * Double.pi * Double(second) / 4.0))] : []
        samples.append(
            stageSample(
                unix: base + second,
                hr: heartRateOverride ?? Int(rate.rounded()),
                rr: rr, gravity: gravity, recordIndex: UInt32(second)
            )
        )
    }
    let period = SleepPeriod(
        startUnix: base,
        endUnix: base + seconds - 1,
        quietFraction: 0.95,
        meanHR: hr,
        wakeEvents: 0
    )
    return (samples, period)
}

final class SleepStageTests: XCTestCase {
    func testQuietNightTilesTheWindow() throws {
        let (samples, period) = makeNight()
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertNil(staging.reason)
        XCTAssertTrue(staging.stageable)

        let segments = try XCTUnwrap(staging.segments.first)
        XCTAssertEqual(segments.startUnix, period.startUnix)
        XCTAssertEqual(staging.segments.last?.endUnix, period.endUnix + 1)
        for (left, right) in zip(staging.segments, staging.segments.dropFirst()) {
            XCTAssertEqual(left.endUnix, right.startUnix)
        }
        XCTAssertEqual(staging.totalMinutes, 60, accuracy: 0.001)
    }

    func testQuietNightIsMostlyLightWithoutWake() {
        let (samples, period) = makeNight()
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertEqual(staging.wakeMinutes, 0)
        XCTAssertGreaterThan(staging.lightMinutes, staging.deepMinutes)
        XCTAssertGreaterThan(staging.restorativeMinutes, 0)
        XCTAssertEqual(staging.asleepMinutes + staging.wakeMinutes, staging.totalMinutes, accuracy: 0.001)
    }

    func testTotalsMatchSegments() {
        let (samples, period) = makeNight(bursts: [(20, 23)])
        let staging = SleepStager.stage(samples: samples, period: period)
        for stage in SleepStage.allCases {
            let expected = staging.segments
                .filter { $0.stage == stage }
                .reduce(0.0) { $0 + $1.minutes }
            XCTAssertEqual(staging.minutes(for: stage), expected, accuracy: 0.001)
        }
    }

    func testMotionBurstsAreStagedAsWake() {
        let (samples, period) = makeNight(bursts: [(20, 24)])
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertNil(staging.reason)
        XCTAssertGreaterThan(staging.wakeMinutes, 0)
        XCTAssertTrue(staging.segments.contains { $0.stage == .wake })
    }

    func testMissingHeartRateRefusesToInventStages() {
        let (samples, period) = makeNight(heartRateOverride: 0)
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertFalse(staging.stageable)
        XCTAssertTrue(staging.segments.isEmpty)
        XCTAssertEqual(staging.totalMinutes, 0)
        XCTAssertTrue(staging.reason?.contains("heart rate covers 0%") == true)
    }

    func testShortWindowWithoutDataRefusesForCoverage() {
        let period = stageWindow(start: base, seconds: 11)
        let staging = SleepStager.stage(samples: [], period: period)
        XCTAssertTrue(staging.reason?.contains("heart rate covers 0%") == true)
        XCTAssertTrue(staging.segments.isEmpty)
    }

    func testShortWindowWithDataStagesItsActualDuration() {
        let period = stageWindow(start: base, seconds: 11)
        let samples = (0..<11).map { stageSample(unix: base + $0) }
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertNil(staging.reason)
        XCTAssertEqual(staging.epochs, 1)
        XCTAssertEqual(staging.hrCoverage, 1)
        assertTotals(staging, period: period, classifiedSeconds: 11)
        XCTAssertEqual(staging.segments.first?.startUnix, base)
        XCTAssertEqual(staging.segments.last?.endUnix, base + 11)
    }

    func testInitialAndFinalPartialEpochsTileOnlyTheWindow() {
        // base % 30 == 10: the actual epoch lengths are 20, 30 and 15 seconds.
        let period = stageWindow(start: base, seconds: 65)
        let samples = (0..<65).map { stageSample(unix: base + $0) }
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertNil(staging.reason)
        XCTAssertEqual(staging.epochs, 3)
        XCTAssertEqual(staging.hrCoverage, 1)
        XCTAssertEqual(staging.segments.first?.startUnix, base)
        XCTAssertEqual(staging.segments.last?.endUnix, base + 65)
        assertTotals(staging, period: period, classifiedSeconds: 65)
    }

    func testPartialEpochsUseTheirActualLengthForTheHalfCoverageGate() {
        let period = stageWindow(start: base, seconds: 65)
        // Exactly half of the initial 20 seconds; 8 of the final 15 seconds.
        let offsets = Array(0..<10) + Array(20..<58)
        let samples = offsets.map { stageSample(unix: base + $0) }
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertNil(staging.reason)
        XCTAssertEqual(staging.hrCoverage, 48.0 / 65.0, accuracy: 1e-12)
        XCTAssertEqual(staging.epochs, 3)
        assertTotals(staging, period: period, classifiedSeconds: 65)
    }

    func testInsufficientInitialAndFinalPartialEpochsStayHoles() {
        let period = stageWindow(start: base, seconds: 65)
        // 9/20 initial and 7/15 final seconds: neither boundary is classifiable.
        let offsets = Array(0..<9) + Array(20..<57)
        let samples = offsets.map { stageSample(unix: base + $0) }
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertNil(staging.reason)
        XCTAssertEqual(staging.hrCoverage, 46.0 / 65.0, accuracy: 1e-12)
        XCTAssertEqual(staging.epochs, 1)
        XCTAssertEqual(staging.segments.first?.startUnix, base + 20)
        XCTAssertEqual(staging.segments.last?.endUnix, base + 50)
        assertTotals(staging, period: period, classifiedSeconds: 30)
    }

    func testOutOfWindowSamplesCannotFillMissingBoundaryEpochs() {
        let period = stageWindow(start: base, seconds: 65)
        let inside = (20..<50).map { stageSample(unix: base + $0) }
        let outside = (Array(-30..<0) + Array(65..<95)).map {
            stageSample(unix: base + $0, hr: 200, rr: [1000])
        }
        let expected = SleepStager.stage(samples: inside, period: period)
        let actual = SleepStager.stage(samples: outside + inside, period: period)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.hrCoverage, 30.0 / 65.0, accuracy: 1e-12)
        XCTAssertFalse(actual.stageable)
        XCTAssertTrue(actual.segments.isEmpty)
    }

    func testOncePerThirtySecondsHRDoesNotPassCoverage() {
        let period = stageWindow(seconds: 600)
        let samples = stride(from: 0, to: 600, by: 30).map {
            stageSample(unix: alignedBase + $0, rr: [1000])
        }
        // Replaying sparse packets cannot turn 20 observed seconds into 600.
        let staging = SleepStager.stage(samples: samples + samples, period: period)
        XCTAssertEqual(staging.hrCoverage, 1.0 / 30.0, accuracy: 1e-12)
        XCTAssertEqual(staging.epochs, 0)
        XCTAssertFalse(staging.stageable)
        XCTAssertTrue(staging.segments.isEmpty)
    }

    func testPhysiologicallyInvalidHRDoesNotCountAsWear() {
        let period = stageWindow(seconds: 60)
        for hr in [-1, 1, 34, 221, 300] {
            let samples = (0..<60).map {
                stageSample(unix: alignedBase + $0, hr: hr, rr: [1000])
            }
            let staging = SleepStager.stage(samples: samples, period: period)
            XCTAssertEqual(staging.hrCoverage, 0, "HR \(hr)")
            XCTAssertFalse(staging.stageable)
            XCTAssertTrue(staging.segments.isEmpty)
        }
    }

    func testOffWristMotionAndRRAreIgnored() {
        let period = stageWindow(seconds: 180)
        let worn = (0..<180).filter { !(60..<90).contains($0) }.map {
            stageSample(unix: alignedBase + $0, rr: [1000])
        }
        // Include same-second off-wrist duplicates as well as the missing epoch.
        let offWrist = (0..<180).map {
            stageSample(
                unix: alignedBase + $0, hr: 0, rr: [350, 1900, 700, 1200],
                gravity: (Double($0 % 2) * 10, 0, 1)
            )
        }
        let expected = SleepStager.stage(samples: worn, period: period)
        let actual = SleepStager.stage(samples: worn + offWrist, period: period)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.hrCoverage, 5.0 / 6.0, accuracy: 1e-12)
        assertTotals(actual, period: period, classifiedSeconds: 150)
        assertHole(actual, start: alignedBase + 60, end: alignedBase + 90)
    }

    func testCoverageGateRemainsAtFiftyPercent() {
        let period = stageWindow(seconds: 120)
        let half = (0..<60).map { stageSample(unix: alignedBase + $0) }
        let accepted = SleepStager.stage(samples: half, period: period)
        XCTAssertNil(accepted.reason)
        XCTAssertEqual(accepted.hrCoverage, 0.5)
        assertTotals(accepted, period: period, classifiedSeconds: 60)
        let refused = SleepStager.stage(samples: Array(half.dropLast()), period: period)
        XCTAssertEqual(refused.hrCoverage, 59.0 / 120.0, accuracy: 1e-12)
        XCTAssertFalse(refused.stageable)
        XCTAssertTrue(refused.segments.isEmpty)
    }

    func test42PercentNightKeepsObservedStagesWithoutFillingMissingHours() {
        let period = stageWindow(seconds: 492 * 60)
        let observed = 207 * 60
        let samples = (0..<observed).map { stageSample(unix: alignedBase + $0) }
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertEqual(Int((staging.hrCoverage * 100).rounded()), 42)
        XCTAssertFalse(staging.stageable)
        XCTAssertNotNil(staging.reason)
        XCTAssertFalse(staging.segments.isEmpty)
        assertTotals(staging, period: period, classifiedSeconds: observed)
        XCTAssertTrue(staging.segments.allSatisfy { $0.endUnix <= alignedBase + observed })
    }

    func testAnEpochBelowHalfCoverageIsNotLightOrWake() {
        let period = stageWindow(seconds: 90)
        let samples = (0..<90).filter { !(44..<60).contains($0) }.map {
            stageSample(unix: alignedBase + $0, rr: [1000])
        }
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertNil(staging.reason)
        XCTAssertEqual(staging.hrCoverage, 74.0 / 90.0, accuracy: 1e-12)
        XCTAssertEqual(staging.epochs, 2)
        assertTotals(staging, period: period, classifiedSeconds: 60)
        assertHole(staging, start: alignedBase + 30, end: alignedBase + 60)
    }

    func testMissingMiddleStartAndEndEpochsStayHoles() {
        let period = stageWindow(seconds: 180)
        for missing in [0..<30, 60..<90, 150..<180] {
            let samples = (0..<180).filter { !missing.contains($0) }.map {
                stageSample(unix: alignedBase + $0)
            }
            let staging = SleepStager.stage(samples: samples, period: period)
            XCTAssertNil(staging.reason)
            XCTAssertEqual(staging.epochs, 5)
            XCTAssertEqual(staging.hrCoverage, 5.0 / 6.0, accuracy: 1e-12)
            assertTotals(staging, period: period, classifiedSeconds: 150)
            assertHole(staging, start: alignedBase + missing.lowerBound, end: alignedBase + missing.upperBound)
            if missing.lowerBound == 0 {
                XCTAssertEqual(staging.segments.first?.startUnix, alignedBase + 30)
            } else if missing.upperBound == 180 {
                XCTAssertEqual(staging.segments.last?.endUnix, alignedBase + 150)
            } else {
                // Constant features label both sides identically; do not merge across the hole.
                XCTAssertEqual(staging.segments.count, 2)
                XCTAssertEqual(staging.segments[0].stage, staging.segments[1].stage)
            }
        }
    }

    func testCombinedMissingBoundariesAndMiddleHaveExactTotals() {
        let period = stageWindow(seconds: 300)
        let missing = [0..<30, 120..<150, 270..<300]
        let samples = (0..<300).filter { second in
            !missing.contains { $0.contains(second) }
        }.map { stageSample(unix: alignedBase + $0) }
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertNil(staging.reason)
        XCTAssertEqual(staging.hrCoverage, 0.7, accuracy: 1e-12)
        XCTAssertEqual(staging.epochs, 7)
        XCTAssertEqual(staging.segments.first?.startUnix, alignedBase + 30)
        XCTAssertEqual(staging.segments.last?.endUnix, alignedBase + 270)
        assertTotals(staging, period: period, classifiedSeconds: 210)
        for gap in missing {
            assertHole(staging, start: alignedBase + gap.lowerBound, end: alignedBase + gap.upperBound)
        }
        XCTAssertEqual(Double(period.durationS) - staging.totalMinutes * 60, 90, accuracy: 1e-9)
    }

    func testHMMRestartsAfterMissingEpoch() {
        let period = stageWindow(seconds: 900)
        let samples = (0..<900).filter { !(840..<870).contains($0) }.map { second in
            let moving = (720..<840).contains(second)
            return stageSample(
                unix: alignedBase + second,
                gravity: moving ? (Double(second % 2), 0, 1) : (0, 0, 1)
            )
        }
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertNil(staging.reason)
        XCTAssertGreaterThan(staging.wakeMinutes, 0)
        XCTAssertEqual(staging.segments.last?.startUnix, alignedBase + 870)
        XCTAssertNotEqual(staging.segments.last?.stage, .wake)
        assertHole(staging, start: alignedBase + 840, end: alignedBase + 870)
        assertTotals(staging, period: period, classifiedSeconds: 870)
    }

    func testSingleMissingEpochAfterTwoHoursStaysUnclassified() {
        let seconds = 4 * 60 * 60
        let missing = 2 * 60 * 60..<(2 * 60 * 60 + 30)
        let period = stageWindow(seconds: seconds)
        let samples = (0..<seconds).filter { !missing.contains($0) }.map {
            stageSample(unix: alignedBase + $0)
        }

        let staging = SleepStager.stage(samples: samples, period: period)

        XCTAssertNil(staging.reason)
        XCTAssertEqual(staging.hrCoverage, Double(seconds - 30) / Double(seconds), accuracy: 1e-12)
        XCTAssertEqual(staging.epochs, seconds / 30 - 1)
        assertHole(staging, start: alignedBase + missing.lowerBound, end: alignedBase + missing.upperBound)
        assertTotals(staging, period: period, classifiedSeconds: seconds - 30)
    }

    func testTenMinuteMidnightWindowGapStaysUnclassified() {
        let seconds = 4 * 60 * 60
        let missing = 2 * 60 * 60..<(2 * 60 * 60 + 10 * 60)
        // 16:00 UTC is 21:30 in the app's Asia/Kolkata timezone, so this
        // four-hour window crosses local midnight.
        let nightStart = (alignedBase / 86_400) * 86_400 + 16 * 60 * 60
        let period = stageWindow(start: nightStart, seconds: seconds)
        let samples = (0..<seconds).filter { !missing.contains($0) }.map {
            stageSample(unix: nightStart + $0)
        }

        let staging = SleepStager.stage(samples: samples, period: period)

        XCTAssertNil(staging.reason)
        XCTAssertEqual(staging.hrCoverage, Double(seconds - 600) / Double(seconds), accuracy: 1e-12)
        XCTAssertEqual(staging.epochs, seconds / 30 - 20)
        assertHole(staging, start: nightStart + missing.lowerBound, end: nightStart + missing.upperBound)
        assertTotals(staging, period: period, classifiedSeconds: seconds - 600)
    }

    func testSessionOnsetAndLatencyGuardsDoNotRestartAcrossRuns() throws {
        let firstRun: [SleepStage] = Array(repeating: SleepStage.wake, count: 10)
            + Array(repeating: SleepStage.light, count: 12)
        let secondRun = Array(repeating: SleepStage.light, count: 12)
        let firstMinutes = (0..<firstRun.count).map { Double($0) / 2 }
        let secondMinutes = (0..<secondRun.count).map { 120 + Double($0) / 2 }

        XCTAssertEqual(
            try XCTUnwrap(SleepStager.sessionSleepOnsetMinutes(
                provisionalRuns: [firstRun], epochMinutes: [firstMinutes]
            )),
            5,
            accuracy: 1e-12
        )
        let onset = try XCTUnwrap(SleepStager.sessionSleepOnsetMinutes(
            provisionalRuns: [firstRun, secondRun],
            epochMinutes: [firstMinutes, secondMinutes]
        ))

        XCTAssertEqual(onset, 5, accuracy: 1e-12)
        let afterGapMinutes = secondMinutes[0] - onset
        XCTAssertEqual(SleepStager.remGuard(afterGapMinutes), 0, accuracy: 1e-12)
        XCTAssertEqual(SleepStager.deepGuard(afterGapMinutes), 0, accuracy: 1e-12)
        // The second run's own sustained onset is recent, so it would still receive
        // both latency penalties if the onset clock were incorrectly restarted.
        XCTAssertGreaterThan(SleepStager.remGuard(0), 0)
        XCTAssertGreaterThan(SleepStager.deepGuard(0), 0)
    }

    func testMultipleRunsUseOnlyReliableOnsetFromFirstRun() throws {
        let firstRun: [SleepStage] = Array(repeating: .wake, count: 10)
            + Array(repeating: .light, count: 10)
        let secondRun: [SleepStage] = Array(repeating: .wake, count: 10)
            + Array(repeating: .light, count: 10)
        let thirdRun: [SleepStage] = Array(repeating: .light, count: 10)
        var runs: [[SleepStage]] = []
        runs.append(firstRun)
        runs.append(secondRun)
        runs.append(thirdRun)
        let firstMinutes: [Double] = (0..<20).map { Double($0) / 2 }
        let secondMinutes: [Double] = (0..<20).map { 90 + Double($0) / 2 }
        let thirdMinutes: [Double] = (0..<10).map { 180 + Double($0) / 2 }
        var minutes: [[Double]] = []
        minutes.append(firstMinutes)
        minutes.append(secondMinutes)
        minutes.append(thirdMinutes)

        XCTAssertEqual(
            try XCTUnwrap(SleepStager.sessionSleepOnsetMinutes(provisionalRuns: runs, epochMinutes: minutes)),
            5,
            accuracy: 1e-12
        )
    }

    func testQuietBedtimeLabelsCannotCreateAnEarlySessionOnset() {
        // 15 minutes of quiet bedtime (30 epochs) followed by 40 epochs of sleep.
        let quietWakeAndSleep = Array(repeating: SleepStage.light, count: 30)
            + Array(repeating: SleepStage.light, count: 40)
        let minutes = quietWakeAndSleep.indices.map { Double($0) / 2 }

        XCTAssertNil(SleepStager.sessionSleepOnsetMinutes(
            provisionalRuns: [quietWakeAndSleep], epochMinutes: [minutes]
        ))
    }

    func testFifteenMinutesOfQuietBedtimeKeepsRecordedWindowAndModelStages() throws {
        let (samples, period) = makeNight(minutes: 60)
        let staging = SleepStager.stage(samples: samples, period: period)

        XCTAssertNil(staging.reason)
        XCTAssertEqual(staging.segments.first?.startUnix, period.startUnix)
        XCTAssertEqual(staging.segments.first?.stage, .light)
        XCTAssertEqual(staging.segments.last?.endUnix, period.endUnix + 1)
        XCTAssertEqual(staging.segments.last?.stage, .light)
        XCTAssertEqual(staging.wakeMinutes, 0)
    }

    func testFifteenMinutesOfQuietMorningDoesNotCreateAWakeOffset() throws {
        let (samples, period) = makeNight(minutes: 60)
        let staging = SleepStager.stage(samples: samples, period: period)

        XCTAssertNil(staging.reason)
        XCTAssertEqual(staging.segments.last?.endUnix, period.endUnix + 1)
        XCTAssertEqual(staging.segments.last?.stage, .light)
        XCTAssertEqual(staging.wakeMinutes, 0)
    }

    func testProlongedMiddleAwakeningDoesNotRestartSessionOnset() throws {
        let firstRun = Array(repeating: SleepStage.wake, count: 10)
            + Array(repeating: .light, count: 20)
            + Array(repeating: .wake, count: 20)
            + Array(repeating: .light, count: 20)
        let minutes = firstRun.indices.map { Double($0) / 2 }

        let onset = try XCTUnwrap(SleepStager.sessionSleepOnsetMinutes(
            provisionalRuns: [firstRun], epochMinutes: [minutes]
        ))

        XCTAssertEqual(onset, 5, accuracy: 1e-12)
        XCTAssertEqual(SleepStager.remGuard(minutes[50] - onset), SleepStager.remGuard(20), accuracy: 1e-12)
        XCTAssertLessThan(SleepStager.remGuard(minutes[50] - onset), SleepStager.remGuard(0))
        XCTAssertEqual(SleepStager.deepGuard(minutes[50] - onset), 0, accuracy: 1e-12)
    }

    func testFinalValidRunShorterThanTenEpochsIsNotForceLabelledWake() {
        let seconds = 4 * 60 * 60
        // Leave nine valid 30-second epochs after the gap.
        let gap = (3 * 60 * 60 + 30 * 60)..<(3 * 60 * 60 + 55 * 60 + 30)
        let period = stageWindow(seconds: seconds)
        let samples = (0..<seconds).filter { !gap.contains($0) }.map {
            stageSample(unix: alignedBase + $0)
        }

        let staging = SleepStager.stage(samples: samples, period: period)

        XCTAssertNil(staging.reason)
        XCTAssertEqual(staging.segments.last?.endUnix, alignedBase + seconds)
        XCTAssertNotEqual(staging.segments.last?.stage, .wake)
        XCTAssertEqual(staging.wakeMinutes, 0)
        assertHole(staging, start: alignedBase + gap.lowerBound, end: alignedBase + gap.upperBound)
    }

    func testMissingHRNearFinalAwakeningRemainsUnclassified() {
        let seconds = 4 * 60 * 60
        let missing = (3 * 60 * 60 + 20 * 60)..<seconds
        let period = stageWindow(seconds: seconds)
        let samples = (0..<seconds).filter { !missing.contains($0) }.map {
            stageSample(unix: alignedBase + $0)
        }

        let staging = SleepStager.stage(samples: samples, period: period)

        XCTAssertNil(staging.reason)
        XCTAssertEqual(staging.segments.last?.endUnix, alignedBase + missing.lowerBound)
        XCTAssertFalse(staging.segments.contains { $0.endUnix > alignedBase + missing.lowerBound })
        assertHole(staging, start: alignedBase + missing.lowerBound, end: alignedBase + seconds)
    }

    func testMissingHRSpanAcrossSleepOnsetLeavesGapUnclassified() {
        let seconds = 4 * 60 * 60
        // Missing HR covers the first 30 minutes, spanning the onset of the window.
        let missing = 0..<(30 * 60)
        let period = stageWindow(seconds: seconds)
        let samples = (0..<seconds).filter { !missing.contains($0) }.map {
            stageSample(unix: alignedBase + $0)
        }

        let staging = SleepStager.stage(samples: samples, period: period)

        XCTAssertNil(staging.reason)
        XCTAssertEqual(staging.segments.first?.startUnix, alignedBase + 30 * 60)
        assertHole(staging, start: alignedBase, end: alignedBase + 30 * 60)
        assertTotals(staging, period: period, classifiedSeconds: seconds - 30 * 60)
    }

    func testShortNapDoesNotApplyForcedBoundaryRelabelling() {
        let seconds = 45 * 60
        let period = stageWindow(seconds: seconds)
        let samples = (0..<seconds).map { stageSample(unix: alignedBase + $0) }

        let staging = SleepStager.stage(samples: samples, period: period)

        XCTAssertNil(staging.reason)
        XCTAssertEqual(staging.segments.first?.startUnix, alignedBase)
        XCTAssertEqual(staging.segments.first?.stage, .light)
        XCTAssertEqual(staging.segments.last?.endUnix, alignedBase + seconds)
        XCTAssertEqual(staging.segments.last?.stage, .light)
        XCTAssertEqual(staging.wakeMinutes, 0)
        assertTotals(staging, period: period, classifiedSeconds: seconds)
    }

    func testGapStagingIsDeterministic() {
        let seconds = 90 * 60
        let gap = 45 * 60..<(45 * 60 + 10 * 60)
        let period = stageWindow(seconds: seconds)
        let samples = (0..<seconds).filter { !gap.contains($0) }.map {
            stageSample(unix: alignedBase + $0)
        }

        XCTAssertEqual(
            SleepStager.stage(samples: samples, period: period),
            SleepStager.stage(samples: samples, period: period)
        )
    }

    func testRepeatedPacketsDoNotChangeStagingOrCoverage() {
        let (samples, period) = makeNight(minutes: 15, bursts: [(5, 7)])
        let expected = SleepStager.stage(samples: samples, period: period)
        let replay = samples + samples + Array(samples.reversed())
        XCTAssertEqual(SleepStager.stage(samples: replay, period: period), expected)
        XCTAssertEqual(expected.hrCoverage, 1)
    }

    func testSameSecondSelectsRichestValidRRPacketWithoutCombiningRecords() {
        let period = stageWindow(seconds: 300)
        let rich = (0..<300).map {
            stageSample(
                unix: alignedBase + $0, rr: [1040, 950, 1010], recordIndex: UInt32($0 + 1000)
            )
        }
        let poor = (0..<300).map {
            stageSample(
                unix: alignedBase + $0, hr: 190, rr: [1000, 1, 2500, 0],
                gravity: (Double($0 % 2), 0, 1), recordIndex: UInt32($0)
            )
        }
        let expected = SleepStager.stage(samples: rich, period: period)
        XCTAssertNil(expected.reason)
        XCTAssertEqual(SleepStager.stage(samples: poor + rich + poor, period: period), expected)
        XCTAssertEqual(SleepStager.stage(samples: Array((rich + poor).reversed()), period: period), expected)
    }

    func testDuplicateTieBreakIsIndependentOfPacketInputOrder() {
        let period = stageWindow(seconds: 180)
        let preferred = (0..<180).map {
            stageSample(unix: alignedBase + $0, rr: [1040, 950], recordIndex: UInt32($0))
        }
        let later = (0..<180).map {
            stageSample(
                unix: alignedBase + $0, hr: 180, rr: [900, 1100],
                gravity: (Double($0 % 2), 0, 1), recordIndex: UInt32($0 + 1000)
            )
        }
        let expected = SleepStager.stage(samples: preferred, period: period)
        XCTAssertEqual(SleepStager.stage(samples: preferred + later, period: period), expected)
        XCTAssertEqual(SleepStager.stage(samples: later + preferred, period: period), expected)
    }

    func testGravityDifferencesDoNotBridgeMissingSeconds() {
        let period = stageWindow(seconds: 300)
        let baseline = (0..<300).map { stageSample(unix: alignedBase + $0, gravity: nil) }
        let sparseGravity = (0..<300).map { second in
            stageSample(
                unix: alignedBase + second,
                gravity: second % 10 == 0 ? (Double((second / 10) % 2) * 10, 0, 1) : nil
            )
        }
        let expected = SleepStager.stage(samples: baseline, period: period)
        XCTAssertEqual(SleepStager.stage(samples: sparseGravity, period: period), expected)
        XCTAssertEqual(expected.wakeMinutes, 0)
    }

    func testNonfiniteGravityIsIgnored() {
        let period = stageWindow(seconds: 300)
        let baseline = (0..<300).map { stageSample(unix: alignedBase + $0, gravity: nil) }
        let invalidGravity = (0..<300).map {
            stageSample(unix: alignedBase + $0, gravity: $0 % 2 == 0 ? (Double.nan, 0, 1) : (0, Double.infinity, 1))
        }
        XCTAssertEqual(
            SleepStager.stage(samples: invalidGravity, period: period),
            SleepStager.stage(samples: baseline, period: period)
        )
    }

    func testSameDurationShiftedWindowsUseTheirOwnObservedSeconds() {
        let samples = (0..<180).filter { !(60..<120).contains($0) }.map {
            stageSample(unix: alignedBase + $0)
        }
        let firstPeriod = stageWindow(seconds: 120)
        let shiftedPeriod = stageWindow(start: alignedBase + 60, seconds: 120)
        let first = SleepStager.stage(samples: samples, period: firstPeriod)
        let shifted = SleepStager.stage(samples: samples, period: shiftedPeriod)
        XCTAssertEqual(first.hrCoverage, 0.5)
        XCTAssertEqual(shifted.hrCoverage, 0.5)
        assertTotals(first, period: firstPeriod, classifiedSeconds: 60)
        assertTotals(shifted, period: shiftedPeriod, classifiedSeconds: 60)
        XCTAssertEqual(first.segments.first?.startUnix, alignedBase)
        XCTAssertEqual(first.segments.last?.endUnix, alignedBase + 60)
        XCTAssertEqual(shifted.segments.first?.startUnix, alignedBase + 120)
        XCTAssertEqual(shifted.segments.last?.endUnix, alignedBase + 180)
    }

    func testSameDurationWindowsAtDifferentGridOffsetsDoNotLoseBoundaries() {
        let samples = (0..<300).map { stageSample(unix: base + $0) }
        for offset in [0, 7, 20, 29] {
            let period = stageWindow(start: base + offset, seconds: 65)
            let staging = SleepStager.stage(samples: samples, period: period)
            XCTAssertNil(staging.reason)
            XCTAssertEqual(staging.hrCoverage, 1)
            XCTAssertEqual(staging.segments.first?.startUnix, period.startUnix)
            XCTAssertEqual(staging.segments.last?.endUnix, period.endUnix + 1)
            assertTotals(staging, period: period, classifiedSeconds: 65)
        }
    }

    func testOutOfWindowHighHRAndMotionCannotChangeFeaturesOrStages() {
        let (samples, period) = makeNight(minutes: 15, bursts: [(5, 7)])
        let outsideSeconds = Array((period.startUnix - 360)..<period.startUnix)
            + Array((period.endUnix + 1)..<(period.endUnix + 421))
        let outside = outsideSeconds.map {
            stageSample(unix: $0, hr: $0 % 2 == 0 ? 210 : 150, rr: [350, 1900], gravity: (10, 0, 1))
        }
        let expected = SleepStager.stage(samples: samples, period: period)
        XCTAssertEqual(SleepStager.stage(samples: outside + samples, period: period), expected)
        assertTotals(expected, period: period, classifiedSeconds: period.durationS)
    }

    private func assertHole(
        _ staging: SleepStaging, start: Int, end: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(
            staging.segments.contains { $0.startUnix < end && $0.endUnix > start },
            "No segment may overlap an unclassified epoch", file: file, line: line
        )
    }

    private func assertTotals(
        _ staging: SleepStaging, period: SleepPeriod, classifiedSeconds: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(staging.segments.reduce(0) { $0 + $1.durationS }, classifiedSeconds, file: file, line: line)
        XCTAssertEqual(staging.totalMinutes * 60, Double(classifiedSeconds), accuracy: 1e-9, file: file, line: line)
        for segment in staging.segments {
            XCTAssertGreaterThan(segment.durationS, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(segment.startUnix, period.startUnix, file: file, line: line)
            XCTAssertLessThanOrEqual(segment.endUnix, period.endUnix + 1, file: file, line: line)
        }
        for (left, right) in zip(staging.segments, staging.segments.dropFirst()) {
            XCTAssertLessThanOrEqual(left.endUnix, right.startUnix, file: file, line: line)
            XCTAssertFalse(left.endUnix == right.startUnix && left.stage == right.stage, file: file, line: line)
        }
        for stage in SleepStage.allCases {
            let seconds = staging.segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.durationS }
            XCTAssertEqual(staging.minutes(for: stage) * 60, Double(seconds), accuracy: 1e-9, file: file, line: line)
        }
    }
}
