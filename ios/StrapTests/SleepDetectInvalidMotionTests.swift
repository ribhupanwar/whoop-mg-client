import XCTest
@testable import Strap

final class SleepDetectInvalidMotionTests: XCTestCase {

    func testDeepStillnessWithoutHeartRateDropIsNotSleep() {
        let start = Int(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 23))!.timeIntervalSince1970)
        let rows = (0..<8400).map { index -> V18Sample in
            let quiet = (600..<7800).contains(index)
            return V18Sample(
                header: BandRecordHeader(version: 18, flags: 0x80, recordIndex: UInt32(index), unix: UInt32(start + index), subsecQ15: 0),
                heartRate: quiet ? 75 : 70, rrIntervalsMS: [], dynamicAccelG: quiet ? 0.005 : 0.3,
                gravityXG: 0, gravityYG: 0, gravityZG: 1, stepCounter: nil, stepCadence: nil, activityClass: 0,
                skinTempC: nil, tempAux1C: nil, tempAux2C: nil, sleepStateByte: nil, sleepState: nil,
                cardiacFlags: nil, hrQualityFlags: nil, spo2CandidateRaw: nil, spo2CandidatePct: nil,
                spo2CandidateKind: .absent, signalQualityLogVariance: nil, psnrB: nil, psnrA: nil)
        }
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty, "Stillness without a heart-rate reduction is not sleep")
    }

    func testTwoHourDaytimeRestNeedsPositiveBandSleepEvidence() {
        let noon = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 13, minute: 9))!
        let start = Int(noon.timeIntervalSince1970)
        let rows = (0..<7800).map { index -> V18Sample in
            let unix = start + index - 600
            return V18Sample(
                header: BandRecordHeader(version: 18, flags: 0x80, recordIndex: UInt32(index), unix: UInt32(unix), subsecQ15: 0),
                heartRate: index < 600 ? 90 : 55, rrIntervalsMS: [], dynamicAccelG: index < 600 ? 0.2 : 0.01,
                gravityXG: 0, gravityYG: 0, gravityZG: 1, stepCounter: nil, stepCadence: nil, activityClass: 0,
                skinTempC: nil, tempAux1C: nil, tempAux2C: nil, sleepStateByte: nil, sleepState: nil,
                cardiacFlags: nil, hrQualityFlags: nil, spo2CandidateRaw: nil, spo2CandidatePct: nil,
                spo2CandidateKind: .absent, signalQualityLogVariance: nil, psnrB: nil, psnrA: nil)
        }
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty, "Desk rest with an HR drop is not confirmed daytime sleep")
    }

    func testMissingMotionDoesNotSupplyActiveReference() {
        let start = Int(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 23))!.timeIntervalSince1970)
        var rows: [V18Sample] = []
        for i in 0..<7800 {
            let header = BandRecordHeader(version: 18, flags: 0x80,
                recordIndex: UInt32(i), unix: UInt32(start + i), subsecQ15: 0)
            let hr: Int = i < 600 ? 100 : 55
            let motion: Double? = i < 600 ? nil : 0.01
            let state: Int = i < 600 ? 0 : 2
            rows.append(V18Sample(header: header, heartRate: hr,
                                  dynamicAccelG: motion, sleepState: state))
        }
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty)
    }

    func testSleepReplayAndMissingMotionDoNotInventDisturbances() throws {
        let start = Int(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 23))!.timeIntervalSince1970)
        var rows: [V18Sample] = []
        for i in 0..<8400 {
            let asleep = (600..<7800).contains(i)
            let missing = (3000..<3030).contains(i)
            let header = BandRecordHeader(version: 18, flags: 0x80,
                recordIndex: UInt32(i), unix: UInt32(start + i), subsecQ15: 0)
            let hr: Int = asleep ? 55 : 100
            let motion: Double? = missing ? nil : (asleep ? 0.01 : 0.3)
            let state: Int = asleep ? 2 : 3
            rows.append(V18Sample(header: header, heartRate: hr,
                                  dynamicAccelG: motion, sleepState: state))
        }
        let original = try XCTUnwrap(SleepDetect.detect(rows).first)
        let replayed = try XCTUnwrap(SleepDetect.detect(rows + rows).first)
        XCTAssertEqual(original.startUnix, replayed.startUnix)
        XCTAssertEqual(original.endUnix, replayed.endUnix)
        XCTAssertEqual(original.wakeEvents, 0)
        XCTAssertEqual(original.wakeEvents, replayed.wakeEvents)
        XCTAssertEqual(original.quietFraction, replayed.quietFraction)
    }

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
