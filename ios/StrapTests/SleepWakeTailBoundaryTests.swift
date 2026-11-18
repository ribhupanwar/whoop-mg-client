import XCTest
@testable import Strap

/// Regression coverage for terminal band-up wake detection. Synthetic records only:
/// no assumptions about WHOOP stage semantics or real sensor accuracy.
final class SleepWakeTailBoundaryTests: XCTestCase {
    private func row(_ unix: Int, hr: Int, accel: Double, state: Int?) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(version: 18, flags: 0x80,
                                     recordIndex: UInt32(unix), unix: UInt32(unix),
                                     subsecQ15: 0),
            heartRate: hr, rrIntervalsMS: [], dynamicAccelG: accel,
            gravityXG: 0, gravityYG: 0, gravityZG: 1,
            stepCounter: nil, stepCadence: nil, activityClass: 0,
            skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: state.map { $0 << 4 }, sleepState: state,
            cardiacFlags: nil, hrQualityFlags: nil,
            spo2CandidateRaw: nil, spo2CandidatePct: nil,
            spo2CandidateKind: .absent,
            signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
        )
    }

    private func capture(upSeconds: Int, sampleStride: Int = 1) -> ([V18Sample], Int, Int) {
        let day = Calendar.current.date(from: DateComponents(
            year: 2026, month: 11, day: 18, hour: 2, minute: 0
        ))!
        let base = Int(day.timeIntervalSince1970)
        let sleepStart = base + 600
        let tailStart = sleepStart + 4200
        let end = tailStart + upSeconds - 1
        var rows = (0..<600).map {
            row(base + $0, hr: 90, accel: 0.3, state: 0)
        }
        rows += stride(from: sleepStart, through: end, by: sampleStride).map { unix in
            row(unix, hr: 55, accel: 0.01, state: unix >= tailStart ? 3 : 2)
        }
        return (rows, tailStart, end)
    }

    func testFourMinuteTerminalUpDoesNotEndSleepEarly() throws {
        let (rows, _, end) = capture(upSeconds: 299)
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertEqual(night.endUnix, end)
    }

    func testFiveMinuteTerminalUpTrimsAtFirstUpObservation() throws {
        let (rows, tailStart, _) = capture(upSeconds: 300)
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertEqual(night.endUnix, tailStart - 1)
    }

    func testShortTerminalUnknownStateDoesNotHideConfirmedWake() throws {
        let (baseRows, tailStart, end) = capture(upSeconds: 300)
        let unknown = (1...60).map { row(end + $0, hr: 55, accel: 0.01, state: 0) }
        let night = try XCTUnwrap(SleepDetect.detect(baseRows + unknown).first)
        XCTAssertEqual(night.endUnix, tailStart - 1,
                       "A short state=0 suffix must not undo sustained state=3 wake")
    }

    func testBriefBathroomAwakeningFollowedBySleepDoesNotTrimNight() throws {
        let (baseRows, tailStart, end) = capture(upSeconds: 180)
        let resumed = (1...900).map { row(end + $0, hr: 55, accel: 0.01, state: 2) }
        let night = try XCTUnwrap(SleepDetect.detect(baseRows + resumed).first)
        XCTAssertEqual(night.endUnix, end + 900,
                       "A short mid-night up interval is not the final wake-up")
        XCTAssertLessThan(tailStart, night.endUnix)
    }

}
