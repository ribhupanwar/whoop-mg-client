import XCTest
@testable import Strap

/// Regression for the verified 22:00 cutoff: a delayed coarse band sleep hint
/// must not erase physiological overnight onset, while daytime rest still
/// requires independently confirmed band sleep evidence.
final class SleepOvernightOnsetBoundaryTests: XCTestCase {
    private func row(_ unix: Int, seconds: Int, sleeping: Bool, sleepState: Int?) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(version: 18, flags: 0x80,
                recordIndex: UInt32(seconds), unix: UInt32(unix), subsecQ15: 0),
            heartRate: sleeping ? 56 : 91, rrIntervalsMS: [],
            dynamicAccelG: sleeping ? 0.012 : 0.23,
            gravityXG: 0, gravityYG: 0, gravityZG: 1,
            stepCounter: nil, stepCadence: nil, activityClass: 0,
            skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: sleepState.map { $0 << 4 }, sleepState: sleepState,
            cardiacFlags: nil, hrQualityFlags: nil,
            spo2CandidateRaw: nil, spo2CandidatePct: nil,
            spo2CandidateKind: .absent,
            signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
        )
    }

    private func capture(startHour: Int, startMinute: Int,
                         sleepStateDelay: Int = 14 * 60,
                         evidence: Bool = true) -> ([V18Sample], Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = Int(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 18,
            hour: startHour, minute: startMinute
        ))!.timeIntervalSince1970)
        var records: [V18Sample] = []
        for second in 0..<900 {
            records.append(row(start - 900 + second, seconds: second,
                               sleeping: false, sleepState: 0))
        }
        for second in 0..<(75 * 60) {
            let state: Int? = second >= sleepStateDelay && evidence ? 2 : 1
            records.append(row(start + second, seconds: second + 900,
                               sleeping: true, sleepState: state))
        }
        return (records, start)
    }

    func testNightAt2351RetainsFourteenMinutesBeforeDelayedBandStateTwo() throws {
        let (rows, start) = capture(startHour: 23, startMinute: 51)
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertEqual(night.startUnix, start,
                       "The coarse state=2 hint may lag recorded nighttime onset")
        XCTAssertEqual(night.endUnix, start + 75 * 60 - 1)
    }

    func testLateEveningBefore2200StillTrimsUnconfirmedRest() throws {
        let (rows, start) = capture(startHour: 21, startMinute: 45)
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertEqual(night.startUnix, start + 14 * 60,
                       "Pre-22:00 lying-still evidence must not bypass the safety gate")
    }

    func testDaytimeStillnessWithoutBandSleepEvidenceIsNotSleep() {
        let (rows, _) = capture(startHour: 13, startMinute: 0, evidence: false)
        XCTAssertTrue(SleepDetect.detect(rows).isEmpty)
    }

    func testSleepStateHintDoesNotFabricateMissingMotionRecords() {
        let (rows, _) = capture(startHour: 23, startMinute: 51)
        let invalid = rows.map { sample -> V18Sample in
            V18Sample(header: sample.header, heartRate: sample.heartRate,
                rrIntervalsMS: sample.rrIntervalsMS, dynamicAccelG: nil,
                gravityXG: sample.gravityXG, gravityYG: sample.gravityYG,
                gravityZG: sample.gravityZG,
                stepCounter: sample.stepCounter, stepCadence: sample.stepCadence,
                activityClass: sample.activityClass,
                skinTempC: sample.skinTempC, tempAux1C: sample.tempAux1C,
                tempAux2C: sample.tempAux2C, sleepStateByte: sample.sleepStateByte,
                sleepState: sample.sleepState,
                cardiacFlags: sample.cardiacFlags, hrQualityFlags: sample.hrQualityFlags,
                spo2CandidateRaw: sample.spo2CandidateRaw,
                spo2CandidatePct: sample.spo2CandidatePct,
                spo2CandidateKind: sample.spo2CandidateKind,
                signalQualityLogVariance: sample.signalQualityLogVariance,
                psnrB: sample.psnrB, psnrA: sample.psnrA)
        }
        XCTAssertTrue(SleepDetect.detect(invalid).isEmpty)
    }
}
