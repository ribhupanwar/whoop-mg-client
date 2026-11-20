import XCTest
@testable import Strap

final class WhoopDerivedStrainTests: XCTestCase {
    private func sample(_ second: Int, hr: Int, wearing: Bool = true) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(version: 18, flags: wearing ? 0x80 : 0,
                recordIndex: UInt32(second), unix: UInt32(second), subsecQ15: 0),
            heartRate: wearing ? hr : 0, rrIntervalsMS: [], dynamicAccelG: 0.2,
            gravityXG: nil, gravityYG: nil, gravityZG: nil,
            stepCounter: nil, stepCadence: nil, activityClass: nil,
            skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: nil, sleepState: nil, cardiacFlags: nil,
            hrQualityFlags: nil, spo2CandidateRaw: nil,
            spo2CandidatePct: nil, spo2CandidateKind: .absent,
            signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
        )
    }

    func testLookupIsCompleteAndOrdered() {
        XCTAssertEqual(WhoopDerivedStrain.lookup.count, 211)
        XCTAssertEqual(WhoopDerivedStrain.display(raw: 0), 0)
        XCTAssertEqual(WhoopDerivedStrain.display(raw: 0.00364918), 10)
        XCTAssertEqual(WhoopDerivedStrain.display(raw: 0.02997906), 20)
        XCTAssertEqual(WhoopDerivedStrain.display(raw: 0.70195765), 21)
    }

    func testMidpointBoundary() {
        let left = 0.00364918, right = 0.00372606
        let middle = (left + right) / 2
        XCTAssertEqual(WhoopDerivedStrain.display(raw: middle - 1e-9), 10)
        XCTAssertEqual(WhoopDerivedStrain.display(raw: middle + 1e-9), 10.1)
    }

    func testReserveThresholdAndInvalidInputs() {
        XCTAssertEqual(WhoopDerivedStrain.intensity(hr: 60, restingHR: 60, maxHR: 180), 0)
        XCTAssertEqual(WhoopDerivedStrain.intensity(hr: 90, restingHR: 60, maxHR: 180), 0)
        XCTAssertGreaterThan(WhoopDerivedStrain.intensity(hr: 150, restingHR: 60, maxHR: 180)!, 0)
        XCTAssertNil(WhoopDerivedStrain.intensity(hr: 150, restingHR: 180, maxHR: 180))
        XCTAssertNil(WhoopDerivedStrain.display(raw: .nan))
    }

    func testThreeSecondCapAndDuplicates() throws {
        let dense = [sample(100, hr: 150), sample(103, hr: 150)]
        let sparse = [sample(100, hr: 150), sample(130, hr: 150)]
        let duplicate = [sample(100, hr: 150), sample(100, hr: 150), sample(103, hr: 150)]
        let expected = try XCTUnwrap(WhoopDerivedStrain.raw(dense, restingHR: 60, maxHR: 180))
        XCTAssertEqual(try XCTUnwrap(WhoopDerivedStrain.raw(sparse, restingHR: 60, maxHR: 180)), expected, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(WhoopDerivedStrain.raw(duplicate, restingHR: 60, maxHR: 180)), expected, accuracy: 1e-12)
    }

    func testInvalidAndOffWristBreakContinuity() {
        let invalid = [sample(100, hr: 150), sample(101, hr: 250), sample(102, hr: 150)]
        let offWrist = [sample(100, hr: 150), sample(101, hr: 150, wearing: false)]
        XCTAssertEqual(WhoopDerivedStrain.raw(invalid, restingHR: 60, maxHR: 180), 0)
        XCTAssertEqual(WhoopDerivedStrain.raw(offWrist, restingHR: 60, maxHR: 180), 0)
    }

    func testRawForScoreRoundtrip() {
        for score in [0.0, 1.0, 5.5, 10.0, 14.2, 18.0, 20.5, 21.0] {
            guard let raw = WhoopDerivedStrain.raw(forScore: score) else {
                XCTFail("Missing raw for score \(score)")
                continue
            }
            guard let recovered = WhoopDerivedStrain.display(raw: raw) else {
                XCTFail("Missing display for raw \(raw)")
                continue
            }
            XCTAssertEqual(recovered, score, accuracy: 0.05)
        }
    }

    func testLiveAccumulateStepBehavior() {
        let resting = 60.0
        let maxHR = 180.0
        
        // Sedentary HR (65 bpm) produces 0 weight and does not increase raw strain
        let baseRaw = 0.001
        let sedentary = WhoopDerivedStrain.accumulateStep(
            currentRaw: baseRaw, hr: 65, deltaSeconds: 1.0, restingHR: resting, maxHR: maxHR
        )
        XCTAssertEqual(sedentary, baseRaw)
        
        // Exercise HR (150 bpm) produces positive weight and increases raw strain
        let exercise = WhoopDerivedStrain.accumulateStep(
            currentRaw: baseRaw, hr: 150, deltaSeconds: 1.0, restingHR: resting, maxHR: maxHR
        )
        XCTAssertGreaterThan(exercise, baseRaw)
        
        // Gap capping: a 60-second jump contributes no more than a 3-second jump
        let capped3s = WhoopDerivedStrain.accumulateStep(
            currentRaw: baseRaw, hr: 150, deltaSeconds: 3.0, restingHR: resting, maxHR: maxHR
        )
        let largeGap = WhoopDerivedStrain.accumulateStep(
            currentRaw: baseRaw, hr: 150, deltaSeconds: 60.0, restingHR: resting, maxHR: maxHR
        )
        XCTAssertEqual(largeGap, capped3s, accuracy: 1e-12)
    }
}
