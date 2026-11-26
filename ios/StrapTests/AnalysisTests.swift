import SQLite3
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


// MARK: - NN seed continuity

final class NNSeedBoundaryTests: XCTestCase {
    func testInvalidPaddingCannotJoinSeparatedRRSeedBeats() {
        XCTAssertTrue(Hrv.nnIntervals([800, 0, 800]).isEmpty)
        XCTAssertEqual(Hrv.nnIntervals([800, 0, 800, 800]), [800, 800])
    }

    func testOutOfRangeIntervalResetsPendingSeed() {
        let invalid = Double(V18Decoder.maxRRMS + 1)
        XCTAssertTrue(Hrv.nnIntervals([800, invalid, 800]).isEmpty)
        XCTAssertEqual(Hrv.nnIntervals([800, invalid, 800, 810]), [800, 810])
    }
}

// MARK: - HRV

final class LiveRRReplayDedupTests: XCTestCase {
    func testReplayedSecondDoesNotInflateLiveBeatCountOrHRV() {
        let original = (0..<40).map { index in
            LiveSample(unix: 1_800_000_000 + index, heartRate: 65,
                       rrIntervalsMS: [index.isMultiple(of: 2) ? 900 : 930])
        }
        let baseline = Hrv.fromLiveSamples(original)
        let replayed = Hrv.fromLiveSamples(original + original)
        XCTAssertEqual(replayed.beats, baseline.beats)
        XCTAssertEqual(replayed.nnBeats, baseline.nnBeats)
        XCTAssertEqual(replayed.rmssdMS, baseline.rmssdMS)
    }

    func testDuplicateSecondPrefersMoreRRBeats() {
        let original = (0..<40).map { index in
            LiveSample(unix: 1_800_000_000 + index, heartRate: 65,
                       rrIntervalsMS: [900, 930])
        }
        let weaker = original.map {
            LiveSample(unix: $0.unix, heartRate: 65, rrIntervalsMS: [900])
        }
        let baseline = Hrv.fromLiveSamples(original)
        let replayed = Hrv.fromLiveSamples(weaker + original)
        XCTAssertEqual(replayed.beats, baseline.beats)
        XCTAssertEqual(replayed.rmssdMS, baseline.rmssdMS)
    }
}

final class OvernightHRVSelectionRegressionTests: XCTestCase {
    // Synthetic analogue of the 26 Nov diagnostic: a longer deep/quiet run
    // has lower RMSSD than a shorter quiet run. Do not silently cherry-pick
    // the higher HRV to match another wearable's displayed value.
    func testSWSSelectionPrefersLongestEligibleDeepRunNotHighestRMSSD() throws {
        let longDeep = (0..<1380).map { second in
            makeSample(10000 + second, hr: 69, accel: 0.01,
                       rr: [800, second.isMultiple(of: 2) ? 835 : 825])
        }
        let shortDeep = (0..<570).map { second in
            makeSample(12000 + second, hr: 67, accel: 0.01,
                       rr: [800, second.isMultiple(of: 2) ? 850 : 840])
        }
        let longResult = Hrv.fromSamples(longDeep)
        let shortResult = Hrv.fromSamples(shortDeep)
        XCTAssertGreaterThan(try XCTUnwrap(shortResult.rmssdMS),
                             try XCTUnwrap(longResult.rmssdMS))
        let selected = Hrv.swsRestingHRV(
            longDeep + shortDeep,
            deepEpochs: [10000...11379, 12000...12569],
            minWindowS: 300
        )
        XCTAssertTrue(selected.isSWS)
        XCTAssertEqual(selected.windowSeconds, 1380)
        XCTAssertEqual(try XCTUnwrap(selected.result.rmssdMS),
                       try XCTUnwrap(longResult.rmssdMS), accuracy: 0.000001)
    }

    func testSWSSelectionFallsBackWhenDeepRRUnavailable() throws {
        let deepWithoutRR = (0..<600).map {
            makeSample(10000 + $0, hr: 65, accel: 0.01)
        }
        let quietWithRR = (0..<600).map {
            makeSample(12000 + $0, hr: 65, accel: 0.01, rr: [800, 840])
        }
        let selected = Hrv.swsRestingHRV(
            deepWithoutRR + quietWithRR,
            deepEpochs: [10000...10599],
            minWindowS: 300
        )
        XCTAssertFalse(selected.isSWS)
        XCTAssertEqual(selected.windowSeconds, 600)
        XCTAssertNotNil(selected.result.rmssdMS)
    }
}

final class HrvTests: XCTestCase {
    func testPrimarySleepWithoutRRDoesNotBorrowNapHRV() throws {
        // A valid nap must not fabricate overnight recovery when the
        // longer primary sleep has no measured R-R intervals.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let overnight = stretch(0, 25_200, hr: 60, accel: 0.01)
        // Sleep detection requires a measured awake-HR reference. Without
        // awake samples this fixture detects no night, testing the wrong gate.
        let awake = stretch(26_000, 3_600, hr: 80, accel: 0.15)
        let nap = stretch(50_000, 2_700, hr: 50, accel: 0.01, rr: [760, 840])
        let days = DailyAnalysis.metrics(
            from: overnight + awake + nap, sex: .male, maxHR: 180, calendar: calendar
        )
        let night = try XCTUnwrap(days.first(where: { $0.restingHR != nil }))
        XCTAssertEqual(try XCTUnwrap(night.restingHR), 60, accuracy: 1e-9)
        XCTAssertNil(night.lnRMSSD, "Nap RR must never fill missing primary-sleep HRV")
    }

    func testDaytimeNapDoesNotAlterOvernightHRVOrRHR() throws {
        // Phase 15 regression: an afternoon nap must not contaminate the
        // primary night's HRV or RHR. This uses only synthetic samples.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let overnight = stretch(0, 25_200, hr: 60, accel: 0.01, rr: [790, 810])
        let awake = stretch(26_000, 3_600, hr: 80, accel: 0.15, rr: [750, 750])
        let nap = stretch(50_000, 2_700, hr: 50, accel: 0.01, rr: [760, 840])
        let days = DailyAnalysis.metrics(
            from: overnight + awake + nap, sex: .male, maxHR: 180, calendar: calendar
        )
        let night = try XCTUnwrap(days.first(where: { $0.lnRMSSD != nil }))
        XCTAssertEqual(try XCTUnwrap(night.restingHR), 60, accuracy: 1e-9)
        XCTAssertEqual(exp(try XCTUnwrap(night.lnRMSSD)), 20, accuracy: 1e-9)
    }

    func testOvernightRMSSD28MillisecondsKeepsRRUnits() throws {
        let rows = (0..<600).map { makeSample(5000 + $0, hr: 76, accel: 0.01, rr: [800, 828]) }
        let result = Hrv.restingHRV(rows, minWindowS: 300)
        XCTAssertEqual(result.windowSeconds, 600)
        XCTAssertEqual(try XCTUnwrap(result.result.rmssdMS), 28, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(result.result.lnRMSSD), log(28), accuracy: 0.000001)
    }

    func testQuietWindowDiagnosticExplainsMinimumVersusWholeNightMean() throws {
        let rows = (0..<600).map { makeSample(5000 + $0, hr: $0 < 300 ? 63 : 89, accel: 0.01, rr: [800, 828]) }
        let run = try XCTUnwrap(Hrv.restingWindowDiagnostics(rows).first)
        XCTAssertEqual(run.durationSeconds, 600)
        XCTAssertEqual(run.meanHeartRate, 76, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(run.minimumRollingHeartRate), 63, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(run.rmssdMS), 28, accuracy: 0.000001)
    }

    func testStreamingRRRejectsUnconfirmedLeadingArtefact() {
        let clean = (0..<40).map { second in
            makeSample(5000 + second, hr: 65, accel: 0.01,
                       rr: [800, 810])
        }
        let leadingSpike = makeSample(4999, hr: 65, accel: 0.01, rr: [449])
        let expected = Hrv.fromSamples(clean)
        let actual = Hrv.fromSamples([leadingSpike] + clean)
        XCTAssertNotNil(expected.rmssdMS)
        XCTAssertEqual(actual.rmssdMS!, expected.rmssdMS!, accuracy: 0.00001)
        XCTAssertEqual(actual.nnBeats, expected.nnBeats)
    }

    func testReplayOfIdenticalSecondDoesNotInflateHRV() {
        let original = (0..<90).map { second in
            makeSample(1000 + second, hr: 65, accel: 0.01,
                       rr: second.isMultiple(of: 2) ? [800, 810] : [805, 795])
        }
        let once = Hrv.fromSamples(original)
        let replayed = Hrv.fromSamples(original + original)
        XCTAssertEqual(replayed.beats, once.beats)
        XCTAssertEqual(replayed.nnBeats, once.nnBeats)
        XCTAssertEqual(replayed.rmssdMS!, once.rmssdMS!, accuracy: 0.00001)
    }

    func testReplayPrefersMoreCompleteSecond() {
        let full = (0..<90).map { second in
            makeSample(2000 + second, hr: 65, accel: 0.01, rr: [800, 805])
        }
        let truncated = (0..<90).map { second in
            makeSample(2000 + second, hr: 65, accel: 0.01, rr: [800])
        }
        let expected = Hrv.fromSamples(full)
        let combined = Hrv.fromSamples(truncated + full)
        XCTAssertEqual(combined.beats, expected.beats)
        XCTAssertEqual(combined.rmssdMS!, expected.rmssdMS!, accuracy: 0.00001)
    }

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
        XCTAssertEqual(Hrv.nnIntervals([50, 800, 5000, 810]), [])
        XCTAssertEqual(Hrv.nnIntervals([50, 800, 5000, 810, 815]), [810, 815])
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

    func testSeedCandidateResetsAtDropout() {
        XCTAssertTrue(Hrv.nnIntervals([800, 5000, 810]).isEmpty)
        XCTAssertEqual(Hrv.nnIntervals([800, 5000, 810, 815]), [810, 815])
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

final class LiveHrvTests: XCTestCase {
    private func makeLive(_ unix: Int, _ rr: [Int]) -> LiveSample {
        LiveSample(unix: unix, heartRate: 60, rrIntervalsMS: rr)
    }

    func testRmssdMatchesIndependentPairSumAcrossAnArtifactAndReplayedSeconds() throws {
        let first = (0..<15).map { makeLive($0, [$0.isMultiple(of: 2) ? 800 : 810]) }
        let second = (0..<15).map { makeLive(17 + $0, [$0.isMultiple(of: 2) ? 850 : 880]) }

        let result = Hrv.fromLiveSamples(Array(second.reversed()) + first + [makeLive(15, [1550])] + first)
        // Fourteen measured 10-ms deltas and fourteen 30-ms deltas.
        // The missing second and the rejected beat contribute no pair.
        XCTAssertEqual(try XCTUnwrap(result.rmssdMS), sqrt(500), accuracy: 0.000001)
        XCTAssertEqual(result.beats, 31)
        XCTAssertEqual(result.rejectedBeats, 1)
        XCTAssertEqual(first[0].rrIntervalsMS, [800])
    }

    /// Two clusters of 15 beats each separated by a 30-second gap.
    /// Cluster 1 has 800 ms RR; Cluster 2 has 850 ms RR.
    /// Flattening across the gap would yield a false (850 - 800)^2 = 2500 delta,
    /// giving RMSSD ≈ 9.28 ms. With gap splitting, no cross-gap delta is computed,
    /// so RMSSD is 0.0 ms.
    func testGapSeparatedClustersDoNotBridgeRRDiff() {
        var samples: [LiveSample] = []
        // Cluster 1: 15 seconds at 800 ms
        for t in 0..<15 {
            samples.append(makeLive(t, [800]))
        }
        // 30-second gap (t = 15..<45 missing)
        // Cluster 2: 15 seconds at 850 ms
        for t in 45..<60 {
            samples.append(makeLive(t, [850]))
        }

        let result = Hrv.fromLiveSamples(samples)
        XCTAssertEqual(result.beats, 30)
        XCTAssertEqual(result.nnBeats, 30)
        XCTAssertNotNil(result.rmssdMS)
        XCTAssertEqual(result.rmssdMS!, 0.0, accuracy: 1e-6)
    }

    /// Contiguous samples without gaps produce identical RMSSD to fromRR.
    func testContiguousSamplesPreserveRmssdBehavior() {
        var samples: [LiveSample] = []
        var flatRR: [Double] = []
        // 20 contiguous seconds with alternating 800 and 810 ms intervals
        for t in 0..<20 {
            let rr = (t % 2 == 0) ? 800 : 810
            samples.append(makeLive(t, [rr]))
            flatRR.append(Double(rr))
        }

        let liveResult = Hrv.fromLiveSamples(samples)
        let rrResult = Hrv.fromRR(flatRR)

        XCTAssertEqual(liveResult.beats, 20)
        XCTAssertEqual(liveResult.nnBeats, 20)
        XCTAssertNotNil(liveResult.rmssdMS)
        XCTAssertNotNil(rrResult.rmssdMS)
        XCTAssertEqual(liveResult.rmssdMS!, rrResult.rmssdMS!, accuracy: 1e-6)
        XCTAssertEqual(liveResult.rmssdMS!, 10.0, accuracy: 1e-6)
    }

    /// When splitting creates runs with insufficient beats (< 20 clean beats)
    /// or no successive pairs (e.g. isolated samples), rmssdMS returns nil.
    func testInsufficientValidPairsAfterSplittingReturnsNil() {
        // Sub-case A: Total beats < 20 across split runs (two 5-beat clusters)
        var shortSamples: [LiveSample] = []
        for t in 0..<5 { shortSamples.append(makeLive(t, [800])) }
        for t in 35..<40 { shortSamples.append(makeLive(t, [800])) }

        let shortResult = Hrv.fromLiveSamples(shortSamples)
        XCTAssertEqual(shortResult.beats, 10)
        XCTAssertNil(shortResult.rmssdMS)

        // Sub-case B: 25 beats total, but each beat is isolated by a 2-second gap (0 successive pairs)
        var isolatedSamples: [LiveSample] = []
        for i in 0..<25 {
            isolatedSamples.append(makeLive(i * 2, [800]))
        }

        let isolatedResult = Hrv.fromLiveSamples(isolatedSamples)
        XCTAssertEqual(isolatedResult.beats, 25)
        // Isolated one-beat runs cannot seed the NN filter: no confirmed pair.
        XCTAssertEqual(isolatedResult.nnBeats, 0)
        XCTAssertNil(isolatedResult.rmssdMS)
    }

    /// Multiple RR intervals in a single LiveSample are processed in beat order
    /// and produce the expected successive-difference RMSSD across intra-sample
    /// and inter-sample boundaries.
    func testMultipleRRInSingleSampleComputesSuccessiveDiffs() {
        var samples: [LiveSample] = []
        var flatRR: [Double] = []
        // 12 contiguous seconds, each carrying two alternating intervals: [800, 810]
        // Yields 24 beats total: 800, 810, 800, 810, ...
        // Every successive difference (both intra-sample and inter-sample) is ±10 ms.
        for t in 0..<12 {
            samples.append(makeLive(t, [800, 810]))
            flatRR.append(800)
            flatRR.append(810)
        }

        let liveResult = Hrv.fromLiveSamples(samples)
        let rrResult = Hrv.fromRR(flatRR)

        XCTAssertEqual(liveResult.beats, 24)
        XCTAssertEqual(liveResult.nnBeats, 24)
        XCTAssertNotNil(liveResult.rmssdMS)
        XCTAssertNotNil(rrResult.rmssdMS)
        XCTAssertEqual(liveResult.rmssdMS!, 10.0, accuracy: 1e-6)
        XCTAssertEqual(liveResult.rmssdMS!, rrResult.rmssdMS!, accuracy: 1e-6)
    }

    /// An empty RR sample in the middle of a contiguous timestamp run resets the
    /// predecessor chain, preventing an RMSSD delta across that empty sample.
    func testEmptyRRSampleResetsPredecessorChainInContiguousRun() {
        var samples: [LiveSample] = []
        // Cluster 1: 15 contiguous seconds at 800 ms (t = 0..<15)
        for t in 0..<15 {
            samples.append(makeLive(t, [800]))
        }
        // Empty sample at t = 15 (contiguous: 15 == 14 + 1)
        samples.append(makeLive(15, []))
        // Cluster 2: 15 contiguous seconds at 850 ms (t = 16..<31, contiguous: 16 == 15 + 1)
        for t in 16..<31 {
            samples.append(makeLive(t, [850]))
        }

        let result = Hrv.fromLiveSamples(samples)
        XCTAssertEqual(result.beats, 30)
        XCTAssertEqual(result.nnBeats, 30)
        XCTAssertNotNil(result.rmssdMS)
        // If the empty sample failed to reset previous, a false (850 - 800)^2 = 2500
        // delta would be included, giving RMSSD ≈ 9.28 ms. With reset, RMSSD is 0.0 ms.
        XCTAssertEqual(result.rmssdMS!, 0.0, accuracy: 1e-6)
    }

    /// A rejected outlier (ectopic/artefact) resets the predecessor chain,
    /// preventing a false difference from being computed across the rejected beat.
    func testRejectedOutlierResetsPredecessorChain() {
        var samples: [LiveSample] = []
        // Cluster 1: 15 contiguous seconds at 800 ms (t = 0..<15)
        for t in 0..<15 {
            samples.append(makeLive(t, [800]))
        }
        // Outlier at t = 15: 1500 ms (> 20% deviation from 800 ms reference)
        samples.append(makeLive(15, [1500]))
        // Cluster 2: 15 contiguous seconds at 850 ms (t = 16..<31)
        for t in 16..<31 {
            samples.append(makeLive(t, [850]))
        }

        let result = Hrv.fromLiveSamples(samples)
        XCTAssertEqual(result.beats, 31)
        XCTAssertEqual(result.nnBeats, 30)
        XCTAssertEqual(result.rejectedBeats, 1)
        XCTAssertNotNil(result.rmssdMS)
        // If the outlier did not reset previous, (850 - 800)^2 = 2500 would be
        // computed across the rejected beat, giving RMSSD ≈ 9.28 ms.
        XCTAssertEqual(result.rmssdMS!, 0.0, accuracy: 1e-6)
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

    func testLongerQuietWindowWithoutRRDoesNotHideUsableWindow() throws {
        let rows = stretch(0, 900, hr: 60, accel: 0.01)
            + stretch(1200, 300, hr: 60, accel: 0.01, rr: [990, 1010])
        let result = Hrv.restingHRV(rows, minWindowS: 300)
        XCTAssertEqual(result.windowSeconds, 300)
        XCTAssertEqual(try XCTUnwrap(result.result.rmssdMS), 20, accuracy: 1e-9)
    }

    func testShortUsableWindowCannotBorrowDurationFromLongEmptyWindow() {
        let rows = stretch(0, 900, hr: 60, accel: 0.01)
            + stretch(1200, 120, hr: 60, accel: 0.01, rr: [990, 1010])
        let result = Hrv.restingHRV(rows, minWindowS: 300)
        XCTAssertEqual(result.windowSeconds, 0)
        XCTAssertNil(result.result.rmssdMS)
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

    func testSWSRestingHRVSelectsSWSWhenAvailable() {
        // Light sleep: RMSSD ~ 10 ms (800, 810)
        let light = stretch(0, 120, hr: 65, accel: 0.01, rr: [800, 810])
        // Deep / SWS sleep: RMSSD ~ 30 ms (780, 810)
        let deep = stretch(120, 120, hr: 58, accel: 0.01, rr: [780, 810])
        let allSamples = light + deep

        let swsResult = Hrv.swsRestingHRV(allSamples, deepEpochs: [120...239], minWindowS: 60)
        XCTAssertTrue(swsResult.isSWS)
        XCTAssertEqual(swsResult.windowSeconds, 120)
        XCTAssertEqual(swsResult.result.rmssdMS!, 30.0, accuracy: 0.5)

        let fallbackResult = Hrv.swsRestingHRV(light, deepEpochs: [], minWindowS: 60)
        XCTAssertFalse(fallbackResult.isSWS)
        XCTAssertEqual(fallbackResult.windowSeconds, 120)
        XCTAssertEqual(fallbackResult.result.rmssdMS!, 10.0, accuracy: 0.5)
    }

    func testRestingHeartRateUsesMedianAcrossEligibleWindows() {
        let rows = stretch(0, 60, hr: 50, accel: 0.01)
            + stretch(120, 120, hr: 70, accel: 0.01)
        XCTAssertEqual(Hrv.restingHeartRate(rows), 70)
    }

    func testRestingHeartRateNeedsQuietAndContiguousSeconds() {
        let rows = stretch(0, 30, hr: 60, accel: 0.01)
            + stretch(30, 1, hr: 60, accel: 0.5)
            + stretch(31, 29, hr: 60, accel: 0.01)
            + stretch(90, 59, hr: 60, accel: 0.01)
        XCTAssertNil(Hrv.restingHeartRate(rows))
    }

    func testRestingHeartRateBenchmarkAgainstPreviousMinimumWindow() {
        let rows = (0..<(8 * 3600)).map { second in
            makeSample(second, hr: 52 + ((second / 180) % 24), accel: 0.01)
        }
        let window = 300
        // Previous implementation before PR #106, using the same measured
        // samples, motion gate and contiguous-run helper as the new estimator.
        func previousEstimate() -> Double? {
            let eligible = rows.filter {
                $0.wearing && (35...220).contains($0.heartRate)
                    && ($0.dynamicAccelG ?? .infinity) <= Hrv.restingQuietAccelG
            }.sorted { $0.unix < $1.unix }
            return Hrv.contiguousRuns(eligible).compactMap {
                Hrv.minimumRollingMean($0.map { Double($0.heartRate) }, window: window)
            }.min()
        }

        XCTAssertNotNil(previousEstimate())
        XCTAssertNotNil(Hrv.restingHeartRate(rows, windowS: window))
        var minimumRuntime: UInt64 = 0
        var medianRuntime: UInt64 = 0
        for _ in 0..<5 {
            let minimumStart = DispatchTime.now().uptimeNanoseconds
            XCTAssertNotNil(previousEstimate())
            let medianStart = DispatchTime.now().uptimeNanoseconds
            XCTAssertNotNil(Hrv.restingHeartRate(rows, windowS: window))
            minimumRuntime += medianStart - minimumStart
            medianRuntime += DispatchTime.now().uptimeNanoseconds - medianStart
        }
        print("RHR benchmark (8h synthetic, mean ms): minimum=\(Double(minimumRuntime) / 5_000_000) median=\(Double(medianRuntime) / 5_000_000)")
    }

    func testRestingHeartRateAcrossLongRecording() {
        let rows = stretch(0, 300, hr: 50, accel: 0.01)
            + stretch(600, 8 * 3600, hr: 65, accel: 0.01)
        XCTAssertEqual(Hrv.restingHeartRate(rows, windowS: 300), 65)
        XCTAssertNil(Hrv.restingHeartRate(rows, windowS: 0))
    }

    func testRestingHeartRate300SecondRollingWindowPreservation() {
        // Issue #126: Minimum 300-second rolling mean on real sensor capture evaluates to 59.29 bpm,
        // matching WHOOP's screenshot ground truth (59 bpm). Verify 300-second window preservation.
        let values: [Double] = (0..<1200).map { i in
            if i >= 300 && i < 600 {
                return 59.29 // Lowest sustained 300-second window
            } else if i >= 600 && i < 900 {
                return 62.5
            } else {
                return 66.0
            }
        }
        let minRolling = Hrv.minimumRollingMean(values, window: 300)
        XCTAssertNotNil(minRolling)
        XCTAssertEqual(round(minRolling!), 59.0)
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

    func testSparseThirtySecondIntervalIsCappedAtFiveSeconds() {
        let quiet = stretch(0, 300, hr: 60, accel: 0.01)
        let sparse = quiet + [
            makeSample(300, hr: 150, accel: 0.5),
            makeSample(330, hr: 150, accel: 0.5)
        ]
        let fiveSecondCadence = quiet + [
            makeSample(300, hr: 150, accel: 0.5),
            makeSample(305, hr: 150, accel: 0.5)
        ]
        let sparseLoad = Hrv.trimp(sparse, maxHR: 180, restingHR: 60, sex: .male)
        let referenceLoad = Hrv.trimp(
            fiveSecondCadence, maxHR: 180, restingHR: 60, sex: .male
        )
        XCTAssertEqual(sparseLoad!, referenceLoad!, accuracy: 1e-9)
    }

    func testGapOverThirtySecondsDoesNotExtrapolateAcrossDisconnect() {
        let quiet = stretch(0, 300, hr: 60, accel: 0.01)
        let oneActiveSample = quiet + [makeSample(300, hr: 150, accel: 0.5)]
        let disconnected = quiet + [
            makeSample(300, hr: 150, accel: 0.5),
            makeSample(421, hr: 60, accel: 0.01)
        ]
        let expected = Hrv.trimp(
            oneActiveSample, maxHR: 180, restingHR: 60, sex: .male
        )
        let actual = Hrv.trimp(
            disconnected, maxHR: 180, restingHR: 60, sex: .male
        )
        XCTAssertEqual(actual!, expected!, accuracy: 1e-9)
    }

    func testFinalHeartRateSampleCountsOnlyOneSecond() {
        let quiet = stretch(0, 300, hr: 60, accel: 0.01)
        let finalSample = quiet + [makeSample(300, hr: 150, accel: 0.5)]
        let expected = (1.0 / 60.0) * 0.75 * 0.64 * exp(1.92 * 0.75)
        let actual = Hrv.trimp(
            finalSample, maxHR: 180, restingHR: 60, sex: .male
        )
        XCTAssertEqual(actual!, expected, accuracy: 1e-9)
    }

    func testExactlyOneHundredTwentySecondGapDoesNotExtrapolate() {
        let quiet = stretch(0, 300, hr: 60, accel: 0.01)
        let oneActiveSample = quiet + [makeSample(300, hr: 150, accel: 0.5)]
        let boundaryGap = quiet + [
            makeSample(300, hr: 150, accel: 0.5),
            makeSample(420, hr: 60, accel: 0.01)
        ]
        let expected = Hrv.trimp(
            oneActiveSample, maxHR: 180, restingHR: 60, sex: .male
        )
        let actual = Hrv.trimp(
            boundaryGap, maxHR: 180, restingHR: 60, sex: .male
        )
        XCTAssertEqual(actual!, expected!, accuracy: 1e-9)
    }

    func testDuplicateTimestampsDoNotAddExtraStrain() {
        let quiet = stretch(0, 300, hr: 60, accel: 0.01)
        let sample = makeSample(300, hr: 150, accel: 0.5)
        let once = Hrv.trimp(
            quiet + [sample], maxHR: 180, restingHR: 60, sex: .male
        )
        let duplicated = Hrv.trimp(
            quiet + [sample, sample], maxHR: 180, restingHR: 60, sex: .male
        )
        XCTAssertEqual(duplicated!, once!, accuracy: 1e-9)
    }

    func testOutOfOrderSamplesMatchChronologicalInput() {
        let quiet = stretch(0, 300, hr: 60, accel: 0.01)
        let first = makeSample(300, hr: 150, accel: 0.5)
        let second = makeSample(305, hr: 150, accel: 0.5)
        let ordered = Hrv.trimp(
            quiet + [first, second], maxHR: 180, restingHR: 60, sex: .male
        )
        let shuffled = Hrv.trimp(
            quiet + [second, first], maxHR: 180, restingHR: 60, sex: .male
        )
        XCTAssertEqual(shuffled!, ordered!, accuracy: 1e-9)
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

final class CaloriesDataQualityTests: XCTestCase {
    func testInvalidHeartRateBreaksTimestampedEnergyInterval() {
        let parameters = (resting: 60.0, max: 190.0, weight: 75.0, height: 175.0, age: 35.0)
        let clean = Calories.activeKcalTimestamped(
            heartRates: [(unix: 0, bpm: 150), (unix: 10, bpm: 150)],
            restingHR: parameters.resting, maxHR: parameters.max,
            weightKg: parameters.weight, heightCm: parameters.height,
            age: parameters.age, sex: .male)
        let corrupted = Calories.activeKcalTimestamped(
            heartRates: [(unix: 0, bpm: 150), (unix: 5, bpm: 250), (unix: 10, bpm: 150)],
            restingHR: parameters.resting, maxHR: parameters.max,
            weightKg: parameters.weight, heightCm: parameters.height,
            age: parameters.age, sex: .male)
        XCTAssertGreaterThan(clean ?? 0, 0)
        XCTAssertEqual(corrupted, 0)
    }
}

// MARK: - Activity detection

final class ActivityDetectTests: XCTestCase {
    func testInvalidHeartRateDoesNotDistortActivity() {
        var rows = rest()
        rows += stream(900, 1200, hr: 150, accel: 0.4,
                       spm: 160, gait: 2, step0: 100)
        rows += coolDown(2100)
        let expected = ActivityDetect.detect(rows)
        let corrupt = (0..<300).map {
            makeSample(900 + $0, hr: 0, accel: 0.4, steps: 100 + $0 * 2, gait: 2)
        }
        XCTAssertEqual(ActivityDetect.detect(rows + corrupt), expected)
    }


    func testHistoricalReplayDoesNotChangeDetectedActivity() {
        var rows = rest()
        rows += stream(900, 1200, hr: 150, accel: 0.4,
                       spm: 160, gait: 2, step0: 100)
        rows += coolDown(2100)
        let expected = ActivityDetect.detect(rows)
        let replayed = ActivityDetect.detect(rows + rows)
        XCTAssertEqual(replayed, expected)
    }


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

    func testCasualWalkWithStepsDoesNotBecomeWorkout() {
        var rows = rest()
        rows += stream(900, 1200, hr: 95, accel: 0.12, spm: 110, gait: 1, step0: 100)
        rows += coolDown(2100)
        let sessions = ActivityDetect.detect(rows)
        XCTAssertTrue(sessions.isEmpty)
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

    func testCasualSteppingWithoutGaitDoesNotBecomeWorkout() {
        var rows = rest()
        rows += stream(900, 1200, hr: 80, accel: 0.12, spm: 110, gait: nil, step0: 100)
        rows += coolDown(2100)
        let sessions = ActivityDetect.detect(rows)
        XCTAssertTrue(sessions.isEmpty)
    }

    func testSustainedBriskWalkingWithElevatedHeartRateIsWorkout() {
        var rows = rest()
        rows += stream(900, 1200, hr: 135, accel: 0.15, spm: 110, gait: 1, step0: 100)
        rows += coolDown(2100)
        let sessions = ActivityDetect.detect(rows)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.kind, "walk")
    }

    func testShortBriskWalkDoesNotAutoSaveWorkout() {
        var rows = rest()
        rows += stream(900, 480, hr: 135, accel: 0.15, spm: 110, gait: 1, step0: 100)
        rows += coolDown(1380)
        XCTAssertTrue(ActivityDetect.detect(rows).isEmpty)
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

    func testEveningQuietWithSparseBandStateCannotBypassSleepConfirmation() {
        let evening = Calendar.current.date(bySettingHour: 21, minute: 32, second: 0, of: Date())!
        let start = Int(evening.timeIntervalSince1970)
        var rows = stretch(start - 600, 600, hr: 100, accel: 0.5)
        rows += (0..<6420).map { offset in
            makeSample(start + offset, hr: 60, accel: 0.02,
                       sleepState: offset < 120 ? 1 : nil)
        }
        rows += stretch(start + 6420, 600, hr: 100, accel: 0.5)
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty,
                      "Sparse band-state evidence must not turn awake evening rest into sleep")
    }

    func testSparseArchiveAfterConfirmedEveningOnsetIsNotFullNight() {
        let evening = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date())!
        let start = Int(evening.timeIntervalSince1970)
        var rows = stretch(start - 600, 600, hr: 100, accel: 0.5)
        rows += (0..<3600).map {
            makeSample(start + $0, hr: 60, accel: 0.02, sleepState: 1)
        }
        // Five minutes of positive sleep-state evidence, then sparse archive
        // records across an apparent hour. The earlier awake samples must not
        // satisfy the coverage requirement for the trimmed sleep interval.
        rows += (3600..<3900).map {
            makeSample(start + $0, hr: 60, accel: 0.02, sleepState: 2)
        }
        rows += stride(from: 3900, through: 7500, by: 5).map {
            makeSample(start + $0, hr: 60, accel: 0.02, sleepState: 2)
        }
        rows += stretch(start + 7501, 600, hr: 100, accel: 0.5)
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty,
                      "Pre-onset awake coverage must not validate a sparse confirmed sleep window")
    }

    func testEveningOnsetRequiresSustainedBandEvidenceNotOnePacket() {
        let evening = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date())!
        let start = Int(evening.timeIntervalSince1970)
        var rows = stretch(start, 600, hr: 100, accel: 0.5)
        rows += (600..<14400).map { offset in
            makeSample(start + offset, hr: 60, accel: 0.02,
                       sleepState: offset == 660 || offset >= 7200 ? 2 : 1)
        }
        rows += stretch(start + 14400, 600, hr: 100, accel: 0.5)
        let periods = SleepDetect.detect(rows)
        XCTAssertEqual(periods.count, 1)
        XCTAssertEqual(periods.first?.startUnix, start + 7200)
    }

    func testLateEveningOnsetRequiresSustainedBandEvidence() {
        let bedtime = Calendar.current.date(
            bySettingHour: 21, minute: 18, second: 0, of: Date()
        )!
        let start = Int(bedtime.timeIntervalSince1970)
        var rows = stretch(start, 600, hr: 100, accel: 0.5)
        rows += (600..<14400).map { offset in
            makeSample(start + offset, hr: 60, accel: 0.02,
                       sleepState: offset >= 7200 ? 2 : 1)
        }
        rows += stretch(start + 14400, 600, hr: 100, accel: 0.5)

        let periods = SleepDetect.detect(rows)
        XCTAssertEqual(periods.count, 1)
        XCTAssertEqual(periods.first?.startUnix, start + 7200,
                       "Quiet bed time before sustained band sleep must remain awake")
    }

    func testLongEveningStillnessWithoutSustainedSleepIsNotSleep() {
        let evening = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date())!
        let start = Int(evening.timeIntervalSince1970)
        var rows = stretch(start, 600, hr: 100, accel: 0.5)
        rows += (600..<14400).map { offset in
            makeSample(start + offset, hr: 60, accel: 0.02, sleepState: offset == 660 ? 2 : 1)
        }
        rows += stretch(start + 14400, 600, hr: 100, accel: 0.5)
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

    func testSustainedBandUpTrimsQuietWakeTail() {
        var rows = stretch(0, 600, hr: 100, accel: 0.5)
        rows += (600..<4200).map {
            makeSample($0, hr: 60, accel: 0.02, sleepState: 2)
        }
        rows += (4200..<4800).map {
            makeSample($0, hr: 60, accel: 0.02, sleepState: 3)
        }
        rows += stretch(4800, 600, hr: 100, accel: 0.5)
        let periods = SleepDetect.detect(rows)
        XCTAssertEqual(periods.count, 1)
        XCTAssertEqual(periods.first?.endUnix, 4199)
    }

    func testOvernightBandUpThenSleepThenFinalUpAndUnknownTail() {
        // Observed 14 Nov archive pattern: up -> sleep -> up -> unknown.
        // The earlier up interval is not the final wake; terminal 0 must
        // not erase a sustained, later up confirmation.
        var rows = stretch(0, 600, hr: 100, accel: 0.5)
        rows += (600..<4200).map {
            makeSample($0, hr: 60, accel: 0.02, sleepState: 2)
        }
        rows += (4200..<4800).map {
            makeSample($0, hr: 60, accel: 0.02, sleepState: 3)
        }
        rows += (4800..<8400).map {
            makeSample($0, hr: 60, accel: 0.02, sleepState: 2)
        }
        rows += (8400..<9000).map {
            makeSample($0, hr: 65, accel: 0.02, sleepState: 3)
        }
        rows += (9000..<9300).map {
            makeSample($0, hr: 70, accel: 0.02, sleepState: 0)
        }
        rows += stretch(9300, 600, hr: 100, accel: 0.5)
        let periods = SleepDetect.detect(rows)
        XCTAssertEqual(periods.count, 1)
        XCTAssertEqual(periods.first?.startUnix, 600)
        XCTAssertEqual(periods.first?.endUnix, 8399)
        XCTAssertEqual(periods.first?.meanHR ?? 0, 60, accuracy: 0.01)
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

    func testMissingHoursDoNotJoinTwoShortQuietFragmentsIntoSleep() {
        let rows = stretch(0, 600, hr: 100, accel: 0.5)
            + stretch(600, 1800, hr: 60, accel: 0.02)
            + stretch(12000, 1800, hr: 60, accel: 0.02)
            + stretch(13800, 600, hr: 100, accel: 0.5)
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
    func testNonFiniteOrInvalidBaselineDoesNotProduceRecovery() {
        let invalid = Baseline(lnRMSSDMean: .nan, lnRMSSDSD: 0.3,
                               rhrMean: 55, rhrSD: 3, days: 14)
        XCTAssertNil(Recovery.score(
            lnRMSSD: 4, rhr: 55, sleepHours: 8, sleepNeedHours: 8,
            baseline: invalid
        ).score)
        let negativeSD = Baseline(lnRMSSDMean: 4, lnRMSSDSD: -1,
                                  rhrMean: 55, rhrSD: 3, days: 14)
        XCTAssertNil(Recovery.score(
            lnRMSSD: 4, rhr: 55, sleepHours: 8, sleepNeedHours: 8,
            baseline: negativeSD
        ).score)
    }

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

    func testRecoveryLevelCanonicalBoundaries() {
        // 5-case enum matching 0x10a0f2874 and raw float boundaries 0x100041d3c
        let cal = RecoveryResult(score: nil, reason: "needs at least 7 days of baseline",
                                 hrvComponent: nil, rhrComponent: nil, sleepComponent: nil)
        XCTAssertEqual(cal.level, .calibrating)
        XCTAssertEqual(cal.band, "unavailable")

        let dead = RecoveryResult(score: nil, reason: "needs HRV and resting HR",
                                  hrvComponent: nil, rhrComponent: nil, sleepComponent: nil)
        XCTAssertEqual(dead.level, .deadEnd)
        XCTAssertEqual(dead.band, "unavailable")

        let red = RecoveryResult(score: 33.0, reason: nil,
                                 hrvComponent: 33.0, rhrComponent: 33.0, sleepComponent: 33.0)
        XCTAssertEqual(red.level, .lowRecovery)
        XCTAssertEqual(red.band, "red")

        let yellowLower = RecoveryResult(score: 33.001, reason: nil,
                                         hrvComponent: 34.0, rhrComponent: 34.0, sleepComponent: 34.0)
        XCTAssertEqual(yellowLower.level, .mediumRecovery)
        XCTAssertEqual(yellowLower.band, "yellow")

        let yellowUpper = RecoveryResult(score: 66.0, reason: nil,
                                         hrvComponent: 66.0, rhrComponent: 66.0, sleepComponent: 66.0)
        XCTAssertEqual(yellowUpper.level, .mediumRecovery)
        XCTAssertEqual(yellowUpper.band, "yellow")

        let green = RecoveryResult(score: 66.001, reason: nil,
                                   hrvComponent: 67.0, rhrComponent: 67.0, sleepComponent: 67.0)
        XCTAssertEqual(green.level, .highRecovery)
        XCTAssertEqual(green.band, "green")
    }

    // Regression scenario from the 2026-11-26 WHOOP/STRAP comparison.
    // Respiratory rate must be compared to STRAP's own baseline, not WHOOP's
    // displayed 18.9 rpm. A small difference between devices is not an
    // illness penalty and must not explain a six-point recovery gap.
    func testRecoveryRespirationBelowElevationGateDoesNotChangeScore() {
        let baseline = steadyBaseline()
        let withoutRespiration = Recovery.score(
            lnRMSSD: log(36), rhr: 69, sleepHours: 6.92,
            sleepNeedHours: 10, baseline: baseline
        )
        let withRespiration = Recovery.score(
            lnRMSSD: log(36), rhr: 69, sleepHours: 6.92,
            sleepNeedHours: 10, baseline: baseline,
            respiratoryRate: 19.8, respiratoryRateBaseline: 19.0
        )
        XCTAssertEqual(withRespiration.score, withoutRespiration.score)
        XCTAssertEqual(withRespiration.hrvComponent, withoutRespiration.hrvComponent)
        XCTAssertEqual(withRespiration.rhrComponent, withoutRespiration.rhrComponent)
        XCTAssertEqual(withRespiration.sleepComponent, withoutRespiration.sleepComponent)
    }

    func testRecoveryRespondsToMeasuredHRVWithoutChangingOtherInputs() throws {
        let baseline = Baseline(
            lnRMSSDMean: log(40), lnRMSSDSD: 0.3,
            rhrMean: 68, rhrSD: 3, days: 14
        )
        let lowerHRV = Recovery.score(
            lnRMSSD: log(36), rhr: 69, sleepHours: 6.92,
            sleepNeedHours: 10, baseline: baseline
        )
        let higherHRV = Recovery.score(
            lnRMSSD: log(44), rhr: 69, sleepHours: 6.92,
            sleepNeedHours: 10, baseline: baseline
        )
        XCTAssertGreaterThan(try XCTUnwrap(higherHRV.score),
                             try XCTUnwrap(lowerHRV.score))
        XCTAssertEqual(lowerHRV.rhrComponent, higherHRV.rhrComponent)
        XCTAssertEqual(lowerHRV.sleepComponent, higherHRV.sleepComponent)
    }

    func testRespiratoryRateIllnessPenalty() {
        let baseline = steadyBaseline()
        // Normal respiration (+0.3 rpm above baseline) applies no deduction
        let normal = Recovery.score(
            lnRMSSD: 4.0, rhr: 55.0, sleepHours: 8, sleepNeedHours: 8, baseline: baseline,
            respiratoryRate: 14.3, respiratoryRateBaseline: 14.0
        )
        let unpenalized = Recovery.score(
            lnRMSSD: 4.0, rhr: 55.0, sleepHours: 8, sleepNeedHours: 8, baseline: baseline
        )
        XCTAssertEqual(normal.score, unpenalized.score)

        // Elevated respiration (+2.0 rpm above baseline, illness indicator >= 1.2 rpm)
        let sick = Recovery.score(
            lnRMSSD: 4.0, rhr: 55.0, sleepHours: 8, sleepNeedHours: 8, baseline: baseline,
            respiratoryRate: 16.0, respiratoryRateBaseline: 14.0
        )
        XCTAssertLessThan(sick.score!, unpenalized.score!)
        // Expected: 65.0 * (1 - 0.10) = 58.5
        XCTAssertEqual(sick.score!, 58.5, accuracy: 1e-6)
    }

    func testVO2MaxSourceEnumeration() {
        // 4 source strings matching 0x109748af0-0x109748b50
        XCTAssertEqual(VO2MaxSource.internalEstimate.rawValue, "INTERNAL_ESTIMATE")
        XCTAssertEqual(VO2MaxSource.manualLabTest.rawValue, "MANUAL_LAB_TEST")
        XCTAssertEqual(VO2MaxSource.manualWearable.rawValue, "MANUAL_WEARABLE")
        XCTAssertEqual(VO2MaxSource.manualOther.rawValue, "MANUAL_OTHER")
        XCTAssertEqual(VO2MaxSource.allCases.count, 4)
    }

    func testDeletedWorkoutReturnsItsSamplesToOutsideWorkoutStress() {
        let samples = (0..<600).map { second in
            makeSample(second, hr: 75, rr: [790, 810, 795, 806])
        }
        let workout = ActivitySession(startUnix: 300, endUnix: 599, kind: "workout", steps: 0,
                                      meanHR: 75, walkTicks: 0, runTicks: 0)
        let baseline = steadyBaseline()
        let before = StressWindows.outsideWorkouts(
            samples: samples, baseline: baseline, sleep: [], activities: [workout], isDeleted: { _ in false }
        )
        let after = StressWindows.outsideWorkouts(
            samples: samples, baseline: baseline, sleep: [], activities: [workout], isDeleted: { $0 == workout }
        )
        XCTAssertEqual(before.windows, 1)
        XCTAssertEqual(after.windows, 2)
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

    func testSpo2ExcludesOffWristCandidate() {
        let rows = [
            makeSample(0, hr: 60, spo2: 96),
            makeSample(1, hr: 0, spo2: 80),
            makeSample(2, hr: 60, spo2: 98)
        ]
        let summary = Recovery.spo2Summary(rows)
        XCTAssertEqual(summary.pct!, 97, accuracy: 1e-6)
        XCTAssertEqual(summary.readings, 2)
    }

    func testSpo2ReplayDoesNotBiasMeanOrCandidateCounts() {
        let original = [
            makeSample(100, hr: 60, spo2: 96),
            makeSample(101, hr: 60, spo2: 98),
            makeSample(102, hr: 60, spo2: 0x80),
            makeSample(103, hr: 60, spo2: 5)
        ]
        let baseline = Recovery.spo2Summary(original)
        let replayed = Recovery.spo2Summary(original + [original[0], original[0], original[2], original[3]])
        XCTAssertEqual(replayed.pct, baseline.pct)
        XCTAssertEqual(replayed.readings, baseline.readings)
        XCTAssertEqual(replayed.saturated, baseline.saturated)
        XCTAssertEqual(replayed.diagnostic, baseline.diagnostic)
    }

    func testSpo2OnWristReplayOutranksOffWristCandidate() {
        let offWrist = makeSample(100, hr: 0, spo2: 80)
        let onWrist = makeSample(100, hr: 60, spo2: 96)
        for rows in [[offWrist, onWrist], [onWrist, offWrist]] {
            let result = Recovery.spo2Summary(rows)
            XCTAssertEqual(result.pct, 96)
            XCTAssertEqual(result.readings, 1)
        }
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

final class RespirationReplayTests: XCTestCase {
    func testReplayedSecondsDoNotBreakRespirationBeatSegments() {
        let original = (0..<120).map { index in
            makeSample(1_800_000_000 + index, hr: 65, accel: 0.01,
                       rr: [index.isMultiple(of: 2) ? 900 : 920])
        }
        let baseline = Respiration.beatSegments(original)
        let replayed = Respiration.beatSegments(original + original)
        XCTAssertEqual(baseline.count, 1)
        XCTAssertEqual(replayed.count, baseline.count)
        XCTAssertEqual(replayed.first?.count, baseline.first?.count)
    }

    func testReplayedSecondsPreferMoreCompleteRRRecord() {
        let original = (0..<120).map { index in
            makeSample(1_800_000_000 + index, hr: 65, accel: 0.01,
                       rr: [900, 920])
        }
        let weaker = (0..<120).map { index in
            makeSample(1_800_000_000 + index, hr: 65, accel: 0.01,
                       rr: [900])
        }
        let segments = Respiration.beatSegments(weaker + original)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.count, 240)
    }
}

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

final class DailyMetricQualityTests: XCTestCase {
    func testIndexedArchiveSliceKeepsBothBoundariesAndReplayRows() {
        let archive = [1, 3, 3, 4, 7].map { makeSample($0, hr: 60) }
        XCTAssertEqual(DailyAnalysis.rows(in: archive, from: 3, through: 4).map(\.unix), [3, 3, 4])
        XCTAssertTrue(DailyAnalysis.rows(in: archive, from: 5, through: 6).isEmpty)
        XCTAssertTrue(DailyAnalysis.rows(in: archive, from: 8, through: 7).isEmpty)
    }

    func testNightlyHRVDoesNotDependOnCompleteSleepStages() throws {
        let day = DayMetrics(dateKey: "2026-11-13", state: "sleep", restingHR: 67,
                             lnRMSSD: log(44), hrvWindowSeconds: 300, sleepHours: 0,
                             sleepStartUnix: 100, sleepEndUnix: 10000,
                             strain: nil, steps: nil, sleepDurationReliable: false)
        XCTAssertEqual(try XCTUnwrap(DailyAnalysis.latestNightHRV(from: [day])), 44, accuracy: 1e-9)
    }

    func testEditedWindowAlsoSelectsNightlyBiometrics() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rows = stretch(0, 600, hr: 60, accel: 0.01, rr: [990, 1010])
            + stretch(600, 600, hr: 75, accel: 0.01, rr: [790, 810])
        let period = SleepPeriod(startUnix: 0, endUnix: 1199, quietFraction: 1, meanHR: 67.5, wakeEvents: 0)
        let edited = SleepSession.make(samples: rows, period: period, correctedTimes: [600, 1200])
        let day = try XCTUnwrap(DailyAnalysis.metrics(
            from: rows, sex: .male, maxHR: 180, calendar: calendar,
            analyzedSleepSessions: [edited]
        ).first)
        XCTAssertEqual(day.sleepStartUnix, 600)
        XCTAssertEqual(try XCTUnwrap(day.restingHR), 75, accuracy: 1e-9)
        XCTAssertEqual(exp(try XCTUnwrap(day.lnRMSSD)), 20, accuracy: 1e-9)
    }

    func testAwakeTrainingLoadDoesNotRequireDetectedSleepOrRR() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rows = stretch(0, 600, hr: 60, accel: 0.01)
            + stretch(600, 600, hr: 150, accel: 0.5)
        let days = DailyAnalysis.metrics(from: rows, sex: .male, maxHR: 180, calendar: calendar)
        let day = try XCTUnwrap(days.first)
        XCTAssertNil(day.restingHR, "Daytime rest is not a nightly recovery measurement")
        XCTAssertNil(day.lnRMSSD)
        XCTAssertGreaterThan(try XCTUnwrap(day.strain), 0)
    }

    func testNightlyRestingHRSurvivesMissingRRAndIncompleteStaging() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var rows = stretch(0, 600, hr: 100, accel: 0.5)
        rows += stretch(600, 1800, hr: 60, accel: 0.01)
        rows += stretch(2520, 1800, hr: 60, accel: 0.01)
        rows += stretch(4320, 600, hr: 100, accel: 0.5)
        let day = try XCTUnwrap(DailyAnalysis.metrics(
            from: rows, sex: .male, maxHR: 180, calendar: calendar
        ).first)
        XCTAssertEqual(day.state, "sleep")
        XCTAssertEqual(try XCTUnwrap(day.restingHR), 60, accuracy: 1e-9)
        XCTAssertNil(day.lnRMSSD)
        XCTAssertEqual(day.hrvWindowSeconds, 0)
        XCTAssertFalse(day.sleepDurationReliable ?? true)
        XCTAssertNil(day.strain, "Exercise load still needs its own quiet awake reference")
        XCTAssertEqual(try XCTUnwrap(day.zoneSeconds), [0, 0, 0, 0, 0],
                       "Verified overnight RHR calibrates zones; 100 BPM stays below Z1, not unknown")
    }
}


final class CaloriesCoverageTests: XCTestCase {
    func testLongGapDoesNotBillUnobservedWorkoutMinutes() {
        let inputs: [(unix: Int, bpm: Double)] = [(0, 150), (300, 150)]
        let result = Calories.activeKcalTimestamped(
            heartRates: inputs, restingHR: 55, maxHR: 190,
            weightKg: 70, heightCm: 175, age: 35, sex: .male
        )
        let thirtySeconds = Calories.activeKcalTimestamped(
            heartRates: [(0, 150), (30, 150)], restingHR: 55, maxHR: 190,
            weightKg: 70, heightCm: 175, age: 35, sex: .male
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, thirtySeconds!, accuracy: 0.001)
    }

    func testDuplicateTimestampAddsNoCalories() {
        let original: [(unix: Int, bpm: Double)] = [(0, 150), (10, 150)]
        let repeated: [(unix: Int, bpm: Double)] = original + [(unix: 0, bpm: 150), (unix: 10, bpm: 150)]
        let args = (restingHR: 55.0, maxHR: 190.0, weightKg: 70.0,
                    heightCm: 175.0, age: 35.0)
        let a = Calories.activeKcalTimestamped(
            heartRates: original, restingHR: args.restingHR, maxHR: args.maxHR,
            weightKg: args.weightKg, heightCm: args.heightCm, age: args.age, sex: .male)
        let b = Calories.activeKcalTimestamped(
            heartRates: repeated, restingHR: args.restingHR, maxHR: args.maxHR,
            weightKg: args.weightKg, heightCm: args.heightCm, age: args.age, sex: .male)
        XCTAssertEqual(a!, b!, accuracy: 0.001)
    }
}


final class HistoricalArchiveWriterTests: XCTestCase {
    func testQueuedMergesPreserveEarlierChunksAndReloadSavedHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let start = 1_790_000_000
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode([makeSample(start, hr: 60)]).write(to: url)
        let writer = HistoricalArchiveWriter(url: url)
        let first = expectation(description: "first chunk")
        let second = expectation(description: "second chunk")
        writer.merge([makeSample(start + 1, hr: 61)]) { result in
            XCTAssertTrue(Thread.isMainThread)
            switch result {
            case .success(let rows): XCTAssertEqual(rows.map(\.unix), [start, start + 1])
            case .failure(let error): XCTFail("\(error)")
            }
            first.fulfill()
        }
        // Enqueue before the first callback: a stale snapshot would lose its chunk.
        writer.merge([makeSample(start + 2, hr: 62)]) { result in
            XCTAssertTrue(Thread.isMainThread)
            switch result {
            case .success(let rows): XCTAssertEqual(rows.map(\.unix), [start, start + 1, start + 2])
            case .failure(let error): XCTFail("\(error)")
            }
            second.fulfill()
        }
        wait(for: [first, second], timeout: 20, enforceOrder: true)
        let saved = try HistoryDatabase(url: writer.databaseURL).samples(from: start, through: start + 2)
        XCTAssertEqual(saved.map(\.unix), [start, start + 1, start + 2])
    }

    func testFailedSaveDoesNotPublishOrDiscardPreviousHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.json")
        let writer = HistoricalArchiveWriter(url: url)
        let initial = expectation(description: "initial archive")
        writer.merge([makeSample(1_790_000_000, hr: 60)]) { result in
            if case .failure(let error) = result { XCTFail("\(error)") }
            initial.fulfill()
        }
        wait(for: [initial], timeout: 20)

        // Force a deterministic transaction failure without unlinking an open
        // SQLite database (which corrupts WAL state on the simulator).
        var probe: OpaquePointer?
        XCTAssertEqual(sqlite3_open(writer.databaseURL.path, &probe), SQLITE_OK)
        defer { sqlite3_close(probe) }
        let reject = "CREATE TRIGGER reject_fixture BEFORE INSERT ON history_sample WHEN NEW.unix=1790000001 BEGIN SELECT RAISE(ABORT, 'fixture write failure'); END"
        XCTAssertEqual(sqlite3_exec(probe, reject, nil, nil, nil), SQLITE_OK)
        let failed = expectation(description: "save fails")
        writer.merge([makeSample(1_790_000_001, hr: 61)]) { result in
            if case .success = result { XCTFail("Must not publish unsaved records") }
            failed.fulfill()
        }
        wait(for: [failed], timeout: 20)
        XCTAssertEqual(try HistoryDatabase(url: writer.databaseURL)
            .samples(from: 1_790_000_000, through: 1_790_000_002).map(\.unix),
                       [1_790_000_000], "Failed transaction must preserve prior durable history")

        XCTAssertEqual(sqlite3_exec(probe, "DROP TRIGGER reject_fixture", nil, nil, nil), SQLITE_OK)
        let recovered = expectation(description: "retry retains original chunk")
        writer.merge([makeSample(1_790_000_002, hr: 62)]) { result in
            switch result {
            case .success(let rows):
                XCTAssertEqual(rows.map(\.unix), [1_790_000_000, 1_790_000_001, 1_790_000_002])
            case .failure(let error): XCTFail("\(error)")
            }
            recovered.fulfill()
        }
        wait(for: [recovered], timeout: 20)
    }
}

extension HistoricalArchiveWriterTests {
    func testInvalidArchiveIsPreservedAndRebuiltFromRecoveredRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.json")
        let invalid = Data("broken archive".utf8)
        try invalid.write(to: url)
        let writer = HistoricalArchiveWriter(url: url)
        let rebuilt = expectation(description: "rebuilt from raw recovery")
        writer.merge([makeSample(1_790_000_000, hr: 60)]) { result in
            switch result {
            case .success(let rows): XCTAssertEqual(rows.count, 1)
            case .failure(let error): XCTFail("\(error)")
            }
            rebuilt.fulfill()
        }
        wait(for: [rebuilt], timeout: 20)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let backup = try XCTUnwrap(files.first { $0.lastPathComponent.contains("invalid-") })
        XCTAssertEqual(try Data(contentsOf: backup), invalid)
        let restored = try HistoryDatabase(url: writer.databaseURL).samples(from: 1_790_000_000, through: 1_790_000_000)
        XCTAssertEqual(restored.map(\.unix), [1_790_000_000])
    }
}


extension HistoricalArchiveWriterTests {
    func testEmptySyncRetriesRecordsFromFailedDrain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A file in place of the parent directory makes the first save fail.
        try Data().write(to: directory)
        let url = directory.appendingPathComponent("history.json")
        let writer = HistoricalArchiveWriter(url: url)
        let failed = expectation(description: "failed drain remains pending")
        writer.merge([makeSample(1_790_000_000, hr: 60)]) { result in
            if case .success = result { XCTFail("Expected disk failure") }
            failed.fulfill()
        }
        wait(for: [failed], timeout: 20)
        try FileManager.default.removeItem(at: directory)
        let retried = expectation(description: "empty next drain saves pending records")
        writer.merge([]) { result in
            switch result {
            case .success(let rows): XCTAssertEqual(rows.map(\.unix), [1_790_000_000])
            case .failure(let error): XCTFail("\(error)")
            }
            retried.fulfill()
        }
        wait(for: [retried], timeout: 20)
        let saved = try HistoryDatabase(url: writer.databaseURL).samples(from: 1_790_000_000, through: 1_790_000_000)
        XCTAssertEqual(saved.map(\.unix), [1_790_000_000])
    }
}


final class HealthspanCoverageBoundaryRegressionTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func day(_ offset: Int, from anchor: Date) -> Date {
        utc.date(byAdding: .day, value: offset, to: anchor)!
    }

    func testLongHistoryOverlappingWindowRetainsGuaranteedDays() {
        let asOf = Date(timeIntervalSince1970: 1_795_478_400) // stable UTC anchor
        let observation = HealthspanObservation(
            value: 55, observedDays: 35,
            firstObserved: day(-39, from: asOf),
            lastObserved: asOf
        )
        let coverage = HealthspanInputCoverage(observations: [.steps: observation], asOf: asOf)
        XCTAssertFalse(coverage.missing(.steps, minimumDays: 20, windowDays: 30, calendar: utc))
        XCTAssertTrue(coverage.missing(.steps, minimumDays: 26, windowDays: 30, calendar: utc))
    }

    func testImpossibleObservedDayCountIsNotAvailable() {
        let asOf = Date(timeIntervalSince1970: 1_795_478_400)
        let impossible = HealthspanObservation(
            value: 55, observedDays: 30,
            firstObserved: day(-1, from: asOf),
            lastObserved: asOf
        )
        let coverage = HealthspanInputCoverage(observations: [.steps: impossible], asOf: asOf)
        XCTAssertFalse(impossible.isValid)
        XCTAssertFalse(coverage.availableContributors.contains(.steps))
        XCTAssertTrue(coverage.missingContributors.contains(.steps))
        XCTAssertTrue(coverage.missing(.steps, minimumDays: 1, windowDays: 30, calendar: utc))
    }


    func testDetailedDiagnosticsMatchesProductionRRReplaySelection() {
        let clean = (0..<30).map { index in
            makeSample(90_000 + index, hr: 65, accel: 0.01, rr: [800, 810])
        }
        let paddedReplay = makeSample(90_012, hr: 65, accel: 0.01, rr: [800, 810, 0])
        let baseline = Hrv.detailedDiagnostics(samples: clean)
        let replayed = Hrv.detailedDiagnostics(samples: clean + [paddedReplay])
        XCTAssertEqual(replayed.rawRRCount, baseline.rawRRCount)
        XCTAssertEqual(replayed.acceptedNNCount, baseline.acceptedNNCount)
        XCTAssertEqual(replayed.finalRMSSD, baseline.finalRMSSD)
        XCTAssertEqual(Hrv.fromSamples(clean + [paddedReplay]).rmssdMS,
                       Hrv.fromSamples(clean).rmssdMS)
    }

    func testRecentRetransmissionPrefersValidRRNotPadding() {
        XCTAssertTrue(Hrv.preferRetransmittedRR([800, 810], over: [800, 810, 0]))
        XCTAssertFalse(Hrv.preferRetransmittedRR([800, 810, 0], over: [800, 810]))
        XCTAssertFalse(Hrv.preferRetransmittedRR([800, 810], over: [800, 810]))
    }
}

// MARK: - Observation-Only Diagnostics (Non-Production)

final class HrvObservationOnlyDiagnosticsTests: XCTestCase {
    /// Constant NN series returns nil ACF1 (zero variance)
    func testNnDiffAcf1ConstantSeriesReturnsNil() {
        XCTAssertNil(Hrv.nnDiffAcf1([800, 800, 800, 800]))
    }

    /// Fewer than 30 pairs returns nil
    func testNnDiffAcf1InsufficientPairsReturnsNil() {
        XCTAssertNil(Hrv.nnDiffAcf1((0..<15).flatMap { _ in [800.0, 810.0] })) // 30 NN intervals = 29 differences
    }

    /// Smooth tachogram with RSA-like pattern -> positive ACF1
    func testNnDiffAcf1SmoothTachogramPositiveAcf1() {
        var nn: [Double] = []
        for i in 0..<100 {
            nn.append(800 + 20 * sin(Double(i) * 0.1)) // Slow modulation
        }
        let acf1 = Hrv.nnDiffAcf1(nn)
        XCTAssertNotNil(acf1)
        XCTAssertGreaterThan(acf1!, 0.5) // Strong positive correlation
    }

    /// White noise NN intervals -> ACF1 ≈ -0.5 (below -0.35 floor)
    func testNnDiffAcf1WhiteNoiseBelowFloor() {
        var rng = SeededRandom(seed: 42)
        var nn: [Double] = []
        for _ in 0..<200 {
            nn.append(800 + Double.random(in: -50...50, using: &rng))
        }
        let acf1 = Hrv.nnDiffAcf1(nn)
        XCTAssertNotNil(acf1)
        XCTAssertLessThan(acf1!, -0.35) // Should be below OpenStrap floor
    }

    /// Alternating pattern (800, 810, 800, 810...) -> ACF1 ≈ -1
    func testNnDiffAcf1AlternatingPatternStrongNegative() {
        let nn = (0..<100).flatMap { _ in [800.0, 810.0] }
        let acf1 = Hrv.nnDiffAcf1(nn)
        XCTAssertNotNil(acf1)
        XCTAssertLessThan(acf1!, -0.9)
    }

    /// Normal RR stream: sum of RR ≈ wall-clock span
    func testRrCoverageNormalStream() {
        let rr = Array(repeating: 800.0, count: 1000)
        let timestamps = (0..<1000).map { 800 * ($0 + 1) }
        let cov = Hrv.rrCoverage(rr, timestamps: timestamps)
        XCTAssertNotNil(cov)
        XCTAssertEqual(cov!, 1.0, accuracy: 0.01)
    }

    /// Duplicate beats: more beat-time than elapsed time -> coverage > 1.10
    func testRrCoverageDuplicateBeatsOverCounted() {
        let rr = Array(repeating: 800.0, count: 2000)
        let timestamps = (0..<1000).map { 800 * ($0 + 1) } + (0..<1000).map { 800 * ($0 + 1) }
        let cov = Hrv.rrCoverage(rr, timestamps: timestamps)
        XCTAssertNotNil(cov)
        XCTAssertGreaterThan(cov!, 1.10)
    }

    /// Span < 600s returns nil
    func testRrCoverageInsufficientSpanReturnsNil() {
        let rr = Array(repeating: 800.0, count: 500)
        let timestamps = (0..<500).map { 800 * ($0 + 1) } // 400s < 600s
        XCTAssertNil(Hrv.rrCoverage(rr, timestamps: timestamps))
    }

    /// Mismatched lengths returns nil
    func testRrCoverageMismatchedLengthsReturnsNil() {
        XCTAssertNil(Hrv.rrCoverage([800, 810], timestamps: [0]))
    }

    /// Extended diagnostics includes ACF1 and RR coverage flags
    func testExtendedDiagnosticsIncludesAcf1AndCoverage() {
        var rows: [V18Sample] = []
        var rng = SeededRandom(seed: 42)
        for i in 0..<1000 {
            // RSA: 4 beats per breath cycle, plus small physiological noise
            let rrVal = 1000 + 20 * sin(Double(i) * 2 * .pi / 4) + Double.random(in: -2...2, using: &rng)
            // One ~1000ms beat per second matches measured wall-clock coverage.
            rows.append(makeSample(i, hr: 60, accel: 0.01, rr: [Int(rrVal)]))
        }
        let diag = Hrv.extendedDiagnostics(samples: rows)
        XCTAssertNotNil(diag.nnDiffAcf1)
        XCTAssertNotNil(diag.rrCoverageRatio)
        XCTAssertNotNil(diag.acf1BelowFloor)
        XCTAssertNotNil(diag.rrOverCoverage)
        guard let belowFloor = diag.acf1BelowFloor, let overCoverage = diag.rrOverCoverage else {
            XCTFail("Expected ACF1 and coverage for 1000 seconds of valid NN beats")
            return
        }
        XCTAssertFalse(belowFloor) // RSA pattern should be above floor
        XCTAssertFalse(overCoverage) // Normal coverage
    }

    /// Extended diagnostics with SWS epochs selects correct window type
    func testExtendedDiagnosticsWithSwSEpochs() {
        let rows = (0..<500).map { makeSample($0, hr: 60, accel: 0.01, rr: [800, 810]) }
        let diag = Hrv.extendedDiagnostics(samples: rows, swsEpochs: [100...400])
        XCTAssertEqual(diag.selectedCalculationWindow, "SWS_DEEP_SLEEP")
    }

    /// Median-of-5-minute-window RMSSD basic test
    func testMedianOfWindowedRmssdBasic() {
        // Alternating 800/810 -> RMSSD = 10
        let nn = (0..<50).flatMap { _ in [800.0, 810.0] }
        let timestamps = Array(0..<100)
        let rmssd = Hrv.medianOfWindowedRMSSD(nn, timestamps: timestamps, windowSeconds: 300)
        XCTAssertNotNil(rmssd)
        // Each 5-min window has 300 beats -> 299 diffs, all ±10 -> RMSSD = 10
        XCTAssertEqual(rmssd!, 10.0, accuracy: 0.1)
    }

    /// Median-of-windowed RMSSD with insufficient data returns nil
    func testMedianOfWindowedRmssdInsufficientData() {
        let nn = (0..<5).flatMap { _ in [800.0, 810.0] } // Only 10 beats
        let timestamps = Array(0..<10)
        XCTAssertNil(Hrv.medianOfWindowedRMSSD(nn, timestamps: timestamps))
    }

    /// Median-of-windowed RMSSD with mismatched lengths returns nil
    func testMedianOfWindowedRmssdMismatchedLengths() {
        XCTAssertNil(Hrv.medianOfWindowedRMSSD([800, 810], timestamps: [0]))
    }

    /// Production HRV is unchanged by observation-only diagnostics
    func testProductionHrvUnchangedByObservationOnlyDiagnostics() {
        let rows = (0..<600).map { makeSample($0, hr: 60, accel: 0.01, rr: [800, 810]) }
        let production = Hrv.fromSamples(rows)
        let extended = Hrv.extendedDiagnostics(samples: rows)
        XCTAssertEqual(extended.finalRMSSD, production.rmssdMS)
        XCTAssertEqual(extended.finalLnRMSSD, production.lnRMSSD)
        XCTAssertEqual(extended.acceptedNNCount, production.nnBeats)
        XCTAssertEqual(extended.rawRRCount, production.beats)
    }
}

// Seeded random number generator for deterministic tests
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
