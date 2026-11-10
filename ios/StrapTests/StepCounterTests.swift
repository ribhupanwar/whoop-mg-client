import XCTest
@testable import Strap

final class StepCounterTests: XCTestCase {
    private func sample(_ unix: Int, steps: Int?) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(
                version: 18, flags: 0x80, recordIndex: UInt32(unix),
                unix: UInt32(unix), subsecQ15: 0
            ),
            heartRate: 70,
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
            signalQualityLogVariance: nil
        )
    }

    func testTotalSumsDeltasNotEndpoints() {
        // A counter that restarts in the middle: 100 → 130, then a new epoch
        // 0 → 20. The honest total is 50, not 0xFFFF & (20 - 100).
        let samples = [
            sample(0, steps: 100), sample(1, steps: 130),
            sample(2, steps: 0), sample(3, steps: 20)
        ]
        XCTAssertEqual(StepCounter.total(samples), 50)
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
}
