import XCTest
@testable import Strap

final class SleepDetectInvalidMotionTests: XCTestCase {
    func testInvalidAccelerationCannotBecomeQuietSleepEvidence() {
        let start = 1_800_000_000
        func make(_ second: Int, accel: Double) -> V18Sample {
            let unix = start + second
            return V18Sample(
                header: BandRecordHeader(version: 18, flags: 0x80,
                                         recordIndex: UInt32(second), unix: UInt32(unix),
                                         subsecQ15: 0),
                heartRate: second < 600 ? 90 : 55,
                rrIntervalsMS: [], dynamicAccelG: accel,
                gravityXG: 0, gravityYG: 0, gravityZG: 1,
                stepCounter: nil, stepCadence: nil, activityClass: 0,
                skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
                sleepStateByte: nil, sleepState: nil,
                cardiacFlags: nil, hrQualityFlags: nil,
                spo2CandidateRaw: nil, spo2CandidatePct: nil,
                spo2CandidateKind: .absent,
                signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
            )
        }
        // Valid active reference followed by an invalid motion stream.
        // Negative dynamic acceleration is not physiological quiet evidence.
        let rows = (0..<4200).map {
            make($0, accel: $0 < 600 ? 0.20 : -0.01)
        }
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty)
    }
}
