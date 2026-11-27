import XCTest
@testable import Strap

final class StressWindowsTests: XCTestCase {
    private func sample(_ unix: Int, rr: [Int]) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(
                version: 18, flags: 0x80, recordIndex: UInt32(unix),
                unix: UInt32(unix), subsecQ15: 0
            ),
            heartRate: 60,
            rrIntervalsMS: rr,
            dynamicAccelG: 0.01,
            gravityXG: nil,
            gravityYG: nil,
            gravityZG: nil,
            stepCounter: nil,
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

    /// Realistic one-second density, with 100 ms successive RR differences.
    private func window(_ start: Int) -> [V18Sample] {
        (0..<300).map { sample(start + $0, rr: [$0.isMultiple(of: 2) ? 800 : 900]) }
    }

    private func baseline(mean: Double, days: Int = 7) -> Baseline {
        Baseline(lnRMSSDMean: mean, lnRMSSDSD: 0.5, rhrMean: 60, rhrSD: 3, days: days)
    }

    func testStressDiagnosticsRetainsRawDeviationBeforeClamping() {
        let high = Recovery.stressIndex(lnRMSSD: 1, baseline: baseline(mean: 6))
        XCTAssertEqual(high.index, 3)
        XCTAssertEqual(high.diagnostics?.unclampedScore, 10)
        XCTAssertEqual(high.diagnostics?.finalScore, 3)
        XCTAssertNil(high.diagnostics?.rejectedRRWindows)

        let low = Recovery.stressIndex(lnRMSSD: 6, baseline: baseline(mean: 4))
        XCTAssertEqual(low.index, 0)
        XCTAssertEqual(low.diagnostics?.unclampedScore, -4)
        XCTAssertEqual(low.diagnostics?.finalScore, 0)
        XCTAssertNil(Recovery.stressIndex(lnRMSSD: nil, baseline: nil).index)
    }

    func testLastMeasuredDisplayDoesNotPromoteStaleStressToLive() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let stamp = 1_700_000_000
        let point = StressPoint(unix: stamp, index: 1.6)
        let diagnostics = StressDiagnostics(
            baselineMean: 4, baselineSD: 1, baselineDays: 7, eligibleRRWindows: 1,
            rejectedRRWindows: nil, unclampedScore: nil, finalScore: nil,
            lastUpdateUnix: stamp, unavailableReason: "stale"
        )
        let result = StressResult(index: nil, reason: "stale", diagnostics: diagnostics)
        func date(_ offset: Int) -> Date {
            Date(timeIntervalSince1970: Double(stamp + offset))
        }
        XCTAssertEqual(result.lastMeasuredPoint(in: [point], now: date(601), calendar: calendar), point)
        XCTAssertNil(result.index)
        XCTAssertNil(result.lastMeasuredPoint(in: [point], now: date(600), calendar: calendar))
        XCTAssertNil(result.lastMeasuredPoint(in: [point], now: date(-1), calendar: calendar))
        XCTAssertNil(result.lastMeasuredPoint(in: [point], now: date(86_400), calendar: calendar))
        XCTAssertNil(result.lastMeasuredPoint(in: [StressPoint(unix: stamp, index: 4)], now: date(601), calendar: calendar))
        XCTAssertNil(StressResult(index: nil, reason: "no baseline", diagnostics: nil)
            .lastMeasuredPoint(in: [point], now: date(601), calendar: calendar))
    }

    func testNeedsAwakeBaseline() {
        let split = StressWindows.share(samples: window(0), baseline: nil)
        XCTAssertNil(split.lowPct)
        XCTAssertEqual(split.windows, 0)
        XCTAssertEqual(split.reason, "needs at least 7 awake-baseline days")
    }

    func testRejectsShortBaseline() {
        let split = StressWindows.share(samples: window(0), baseline: baseline(mean: 4.605, days: 3))
        XCTAssertNil(split.highPct)
        XCTAssertEqual(split.windows, 0)
    }

    func testAtTheNormScoresLow() {
        let split = StressWindows.share(samples: window(0), baseline: baseline(mean: 4.605))
        XCTAssertEqual(split.windows, 1)
        XCTAssertEqual(split.lowPct, 100)
        XCTAssertEqual(split.mediumPct, 0)
        XCTAssertEqual(split.highPct, 0)
        XCTAssertNil(split.reason)
    }

    func testTwoSDsBelowTheNormScoresHigh() {
        let split = StressWindows.share(samples: window(0), baseline: baseline(mean: 5.7))
        XCTAssertEqual(split.windows, 1)
        XCTAssertEqual(split.highPct, 100)
        XCTAssertEqual(split.lowPct, 0)
    }

    func testOneSDBelowTheNormScoresMedium() {
        let split = StressWindows.share(samples: window(0), baseline: baseline(mean: 5.2))
        XCTAssertEqual(split.mediumPct, 100)
    }

    func testExcludedWindowsAreDropped() {
        let samples = window(0) + window(300)
        let split = StressWindows.share(
            samples: samples,
            baseline: baseline(mean: 4.605),
            excluded: [(start: 0, end: 299)]
        )
        XCTAssertEqual(split.windows, 1)
        XCTAssertEqual(split.lowPct, 100)
    }

    func testAllWindowsExcludedHasNoShare() {
        let split = StressWindows.share(
            samples: window(0),
            baseline: baseline(mean: 4.605),
            excluded: [(start: 0, end: 299)]
        )
        XCTAssertNil(split.lowPct)
        XCTAssertEqual(split.reason, "no R-R beats in awake windows")
    }

    func testSparseScoredWindowsDoNotInventElapsedDuration() {
        let sparse = (0..<10).map { sample($0 * 30, rr: [800, 900]) }
        let split = StressWindows.share(samples: sparse, baseline: baseline(mean: 4.605))
        XCTAssertEqual(split.windows, 0)
        XCTAssertNil(StressWindows.scoredSeconds(split))
        XCTAssertTrue(StressWindows.series(samples: sparse, baseline: baseline(mean: 4.605)).isEmpty)
    }

    func testCompleteScoredWindowsExposeElapsedDuration() {
        let rows = (0..<600).map { sample($0, rr: [$0 % 2 == 0 ? 800 : 900]) }
        let split = StressWindows.share(samples: rows, baseline: baseline(mean: 4.605))
        XCTAssertEqual(split.windows, 2)
        XCTAssertEqual(StressWindows.scoredSeconds(split), 600)
        let replayed = StressWindows.share(samples: rows + rows, baseline: baseline(mean: 4.605))
        XCTAssertEqual(StressWindows.scoredSeconds(replayed), 600)
    }

    func testPartialExcludedWindowCannotClaimFullDuration() {
        let rows = window(0)
        let split = StressWindows.share(samples: rows, baseline: baseline(mean: 4.605),
                                        excluded: [(start: 0, end: 59)])
        XCTAssertNil(StressWindows.scoredSeconds(split))
    }

    func testWindowsWithoutBeatsAreSkipped() {
        let samples = window(0) + [sample(400, rr: [])]
        let split = StressWindows.share(samples: samples, baseline: baseline(mean: 4.605))
        XCTAssertEqual(split.windows, 1)
    }

    func testSeriesEmptyWithoutBaseline() {
        XCTAssertTrue(StressWindows.series(samples: window(0), baseline: nil).isEmpty)
    }

    func testSeriesOnePointPerScoredWindowInOrder() {
        let points = StressWindows.series(samples: window(0) + window(300), baseline: baseline(mean: 4.605))
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.map(\.unix), [0, 300])
        for point in points {
            XCTAssertEqual(point.index, 0.0, accuracy: 0.01, "at the norm the index is 0")
        }
    }

    func testSeriesReflectsHighStressWindow() {
        let points = StressWindows.series(samples: window(0), baseline: baseline(mean: 5.7))
        XCTAssertEqual(points.count, 1)
        // Stress is measured in baseline SDs, not snapped to the high-band threshold.
        // The synthetic alternating RR sequence is filtered before lnRMSSD is scored.
        let lnRMSSD = Hrv.fromSamples(window(0), rrRange: 300...2000).lnRMSSD
        let expected = Recovery.stressIndex(lnRMSSD: lnRMSSD, baseline: baseline(mean: 5.7)).index
        XCTAssertNotNil(expected)
        XCTAssertEqual(points.first?.index, expected)
    }

    func testSeriesPreservesRawDeviationAndLegacyPointsRemainReadable() throws {
        let samples = window(0)
        let lnRMSSD = try XCTUnwrap(Hrv.fromSamples(samples, rrRange: 300...2000).lnRMSSD)
        for deviation in [-4.0, 10.0] {
            let points = StressWindows.series(samples: samples, baseline: baseline(mean: lnRMSSD + deviation * 0.5))
            let point = try XCTUnwrap(points.first)
            XCTAssertEqual(try XCTUnwrap(point.unclampedScore), deviation, accuracy: 0.0001)
            XCTAssertEqual(point.index, deviation < 0 ? 0.0 : 3.0)
            XCTAssertEqual(try JSONDecoder().decode(StressPoint.self, from: JSONEncoder().encode(point)), point)
        }
        let legacy = try JSONDecoder().decode(StressPoint.self, from: Data(#"{"unix":0,"index":3}"#.utf8))
        XCTAssertNil(legacy.unclampedScore)
        XCTAssertEqual(legacy.index, 3)
    }

    func testSeriesRespectsExclusions() {
        let points = StressWindows.series(
            samples: window(0) + window(300),
            baseline: baseline(mean: 4.605),
            excluded: [(start: 0, end: 299)]
        )
        XCTAssertEqual(points.map(\.unix), [300])
    }

    func testHighMotionSamplesExcludedFromRestingStress() {
        let moving = (0..<10).map { i -> V18Sample in
            let s = sample(i * 30, rr: [1000, 1100])
            return V18Sample(
                header: s.header, heartRate: 110, rrIntervalsMS: s.rrIntervalsMS,
                dynamicAccelG: 0.65, gravityXG: nil, gravityYG: nil, gravityZG: nil,
                stepCounter: nil, stepCadence: nil, activityClass: 0,
                skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
                sleepStateByte: nil, sleepState: nil, cardiacFlags: nil,
                hrQualityFlags: nil, spo2CandidateRaw: nil, spo2CandidatePct: nil,
                spo2CandidateKind: .absent, signalQualityLogVariance: nil,
                psnrB: nil, psnrA: nil
            )
        }
        let split = StressWindows.share(samples: moving, baseline: baseline(mean: 4.605))
        XCTAssertEqual(split.windows, 0)
        XCTAssertTrue(StressWindows.series(samples: moving, baseline: baseline(mean: 4.605)).isEmpty)
    }

    func testStressSeriesDoesNotJoinRRThroughMissingSeconds() throws {
        let first = (0..<100).map { sample($0, rr: [$0.isMultiple(of: 2) ? 800 : 810]) }
        let second = (200..<300).map { sample($0, rr: [$0.isMultiple(of: 2) ? 1000 : 1010]) }
        let rows = first + second
        let hrv = try XCTUnwrap(Hrv.fromSamples(rows, rrRange: 300...2000).lnRMSSD)
        let norm = baseline(mean: hrv + 0.5)
        let point = try XCTUnwrap(StressWindows.series(samples: rows, baseline: norm).first)
        XCTAssertEqual(point.index, 1, accuracy: 0.01)
        XCTAssertEqual(StressWindows.share(samples: rows, baseline: norm).mediumPct, 100)
    }

    func testOvercountedBucketRejectedFromStressWindows() {
        let overCounted = (0..<300).map { sample($0, rr: [800, 900, 800]) }
        let split = StressWindows.share(samples: overCounted, baseline: baseline(mean: 4.605))
        XCTAssertEqual(split.windows, 0)
        XCTAssertTrue(StressWindows.series(samples: overCounted, baseline: baseline(mean: 4.605)).isEmpty)
    }
}
