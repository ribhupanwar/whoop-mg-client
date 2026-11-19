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
        func samples(upSeconds: Int, activeUp: Bool = false) -> [V18Sample] {
            (0..<600).map { second in
                let state = (300..<(300 + upSeconds)).contains(second) ? 3 : 2
                return V18Sample(
                    header: BandRecordHeader(
                        version: 18, flags: 0x80, recordIndex: UInt32(second),
                        unix: UInt32(start + second), subsecQ15: 0
                    ),
                    heartRate: 60, rrIntervalsMS: [1000], dynamicAccelG: activeUp && (300..<(300 + upSeconds)).contains(second) ? 0.20 : 0.01,
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
        let baseline = SleepStager.stage(samples: samples(upSeconds: 0), period: period)
        let shortUp = SleepStager.stage(samples: samples(upSeconds: 240), period: period)
        XCTAssertEqual(shortUp, baseline,
                       "A four-minute bathroom/movement interval must not force wake or end the night")
        let sustainedUp = SleepStager.stage(samples: samples(upSeconds: 300), period: period)
        XCTAssertEqual(sustainedUp, baseline,
                       "A quiet five-minute latched up hint alone must not manufacture wake")
        let activeUp = SleepStager.stage(samples: samples(upSeconds: 300, activeUp: true), period: period)
        XCTAssertGreaterThanOrEqual(activeUp.wakeMinutes, 5,
                       "Five minutes of measured movement corroborating band-up should be awake")
    }
}
