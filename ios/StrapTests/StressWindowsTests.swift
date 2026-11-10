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
            signalQualityLogVariance: nil
        )
    }

    /// Ten samples inside one 5-minute bucket. Alternating 1000/1100 ms R-R
    /// gives RMSSD 100 ms, i.e. lnRMSSD ≈ 4.605.
    private func window(_ start: Int, rr: [Int] = [1000, 1100]) -> [V18Sample] {
        (0..<10).map { sample(start + $0 * 30, rr: rr) }
    }

    private func baseline(mean: Double, days: Int = 7) -> Baseline {
        Baseline(lnRMSSDMean: mean, lnRMSSDSD: 0.5, rhrMean: 60, rhrSD: 3, days: days)
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

    func testScoredSecondsUsesFiveMinuteWindows() {
        let split = StressWindows.share(samples: window(0) + window(300), baseline: baseline(mean: 4.605))
        XCTAssertEqual(split.windows, 2)
        XCTAssertEqual(StressWindows.scoredSeconds(split), 600)
    }

    func testWindowsWithoutBeatsAreSkipped() {
        let samples = window(0) + [sample(400, rr: [])]
        let split = StressWindows.share(samples: samples, baseline: baseline(mean: 4.605))
        XCTAssertEqual(split.windows, 1)
    }
}
