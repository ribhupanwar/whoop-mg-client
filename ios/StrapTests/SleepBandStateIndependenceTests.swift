import Foundation
import XCTest
@testable import Strap

/// Band state is a coarse device hint, not a physiological REM/deep label.
/// Changing only that hint must never rewrite the stage classifier's result.
final class SleepBandStateIndependenceTests: XCTestCase {
    func testBandUpHintAloneDoesNotForceREM() {
        let start = 1_720_000_020
        let period = SleepPeriod(
            startUnix: start, endUnix: start + 600 - 1,
            quietFraction: 0.95, meanHR: 60, wakeEvents: 0
        )
        func samples(state: Int) -> [V18Sample] {
            (0..<600).map { second in
                V18Sample(
                    header: BandRecordHeader(
                        version: 18, flags: 0x80, recordIndex: UInt32(second),
                        unix: UInt32(start + second), subsecQ15: 0
                    ),
                    heartRate: 60, rrIntervalsMS: [1000], dynamicAccelG: 0.01,
                    gravityXG: 0, gravityYG: 0, gravityZG: 1,
                    stepCounter: nil, stepCadence: nil, activityClass: nil,
                    skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
                    sleepStateByte: nil, sleepState: state,
                    cardiacFlags: nil, hrQualityFlags: nil,
                    spo2CandidateRaw: nil, spo2CandidatePct: nil,
                    spo2CandidateKind: .absent,
                    signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
                )
            }
        }
        let sleepHint = SleepStager.stage(samples: samples(state: 2), period: period)
        let upHint = SleepStager.stage(samples: samples(state: 3), period: period)
        XCTAssertEqual(upHint, sleepHint,
                       "Band-up state alone must not be interpreted as REM")
    }
}
