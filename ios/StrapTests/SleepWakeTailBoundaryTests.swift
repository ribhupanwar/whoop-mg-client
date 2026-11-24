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

    func testConfirmedEveningSleepBacktracksThroughQuietLowHRPrelude() throws {
        let base = Int(Calendar.current.date(from: DateComponents(
            year: 2026, month: 11, day: 18, hour: 21, minute: 45))!.timeIntervalSince1970)
        var rows = (0..<600).map { row(base + $0, hr: 85, accel: 0.3, state: 0) }
        let quietStart = base + 600
        rows += (quietStart..<(quietStart + 900)).map {
            row($0, hr: $0 < quietStart + 300 ? 74 : 62,
                accel: 0.008, state: 1)
        }
        let confirmedStart = quietStart + 900
        rows += (confirmedStart..<(confirmedStart + 7200)).map {
            row($0, hr: 61, accel: 0.008, state: 2)
        }
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertEqual(night.startUnix, quietStart + 300)
    }

    func testMovingPreludeDoesNotBacktrackConfirmedEveningSleep() throws {
        let base = Int(Calendar.current.date(from: DateComponents(
            year: 2026, month: 11, day: 18, hour: 21, minute: 45))!.timeIntervalSince1970)
        var rows = (0..<600).map { row(base + $0, hr: 85, accel: 0.3, state: 0) }
        rows += ((base + 600)..<(base + 1500)).map {
            row($0, hr: 62, accel: 0.07, state: 1)
        }
        let confirmedStart = base + 1500
        rows += (confirmedStart..<(confirmedStart + 7200)).map {
            row($0, hr: 61, accel: 0.008, state: 2)
        }
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertEqual(night.startUnix, confirmedStart)
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

    func testFiveMinuteMidNightUpIntervalDoesNotEndTheNight() throws {
        let day = Calendar.current.date(from: DateComponents(
            year: 2026, month: 11, day: 18, hour: 2, minute: 0
        ))!
        let base = Int(day.timeIntervalSince1970)
        let sleepStart = base + 600
        let upStart = sleepStart + 1800
        let sleepEnd = sleepStart + 7200
        var rows = (0..<600).map { row(base + $0, hr: 90, accel: 0.3, state: 0) }
        rows += (sleepStart..<sleepEnd).map { unix in
            row(unix, hr: 55, accel: 0.01,
                state: (upStart..<(upStart + 300)).contains(unix) ? 3 : 2)
        }
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertEqual(night.startUnix, sleepStart)
        XCTAssertEqual(night.endUnix, sleepEnd - 1,
                       "A sustained mid-night up interval is wake time, not the final wake boundary")
    }

    func testBriefBathroomAwakeningFollowedBySleepDoesNotTrimNight() throws {
        let (baseRows, tailStart, end) = capture(upSeconds: 180)
        let resumed = (1...900).map { row(end + $0, hr: 55, accel: 0.01, state: 2) }
        let night = try XCTUnwrap(SleepDetect.detect(baseRows + resumed).first)
        XCTAssertEqual(night.endUnix, end + 900,
                       "A short mid-night up interval is not the final wake-up")
        XCTAssertLessThan(tailStart, night.endUnix)
    }


    func testTerminalUpWithSustainedHRAndMotionTrimsWakePrelude() throws {
        let base = Int(Calendar.current.date(from: DateComponents(
            year: 2026, month: 11, day: 19, hour: 2, minute: 0))!.timeIntervalSince1970)
        let sleepStart = base + 600
        let wakeStart = sleepStart + 7200
        let end = wakeStart + 360
        var rows = (0..<600).map { row(base + $0, hr: 90, accel: 0.3, state: 0) }
        rows += (sleepStart..<wakeStart).map { row($0, hr: 55, accel: 0.008, state: 2) }
        rows += (wakeStart..<end).map {
            row($0, hr: 70, accel: 0.025, state: $0 >= end - 20 ? 3 : 1)
        }
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertLessThanOrEqual(abs(night.endUnix - (wakeStart - 1)), 1,
                                 "Minute-window wake detection may differ by one sampled second, not minutes")
    }

    func testTerminalUpWithoutMotionDoesNotTrimQuietTail() throws {
        let base = Int(Calendar.current.date(from: DateComponents(
            year: 2026, month: 11, day: 19, hour: 2, minute: 0))!.timeIntervalSince1970)
        let sleepStart = base + 600
        let wakeStart = sleepStart + 7200
        let end = wakeStart + 360
        var rows = (0..<600).map { row(base + $0, hr: 90, accel: 0.3, state: 0) }
        rows += (sleepStart..<wakeStart).map { row($0, hr: 55, accel: 0.008, state: 2) }
        rows += (wakeStart..<end).map {
            row($0, hr: 70, accel: 0.008, state: $0 >= end - 20 ? 3 : 1)
        }
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertEqual(night.endUnix, end - 1,
                       "HR rise without measured movement must not imply wake onset")
    }

    func testConfirmedEveningSleepBacktracksThroughPositionAdjustmentRustle() throws {
        let base = Int(Calendar.current.date(from: DateComponents(
            year: 2026, month: 11, day: 18, hour: 21, minute: 45))!.timeIntervalSince1970)
        var rows = (0..<600).map { row(base + $0, hr: 85, accel: 0.3, state: 0) }
        let bedtime = base + 600
        // Prelude has settling HR (62-64) but includes a 4-second position shift rustle (accel 0.25, HR 70)
        rows += (bedtime..<(bedtime + 960)).map { offset in
            let isRustle = (bedtime + 300..<(bedtime + 305)).contains(offset)
            return row(offset, hr: isRustle ? 70 : (offset < bedtime + 300 ? 74 : 62), accel: isRustle ? 0.25 : 0.008, state: 1)
        }
        let confirmedStart = bedtime + 960
        rows += (confirmedStart..<(confirmedStart + 7200)).map {
            row($0, hr: 61, accel: 0.008, state: 2)
        }
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        // Backtracking should successfully traverse the momentary rustle back to bedtime settling
        XCTAssertEqual(night.startUnix, bedtime + 300,
                       "Backtrack through brief rustle to the verified low-HR settling prelude")
    }

    /// Alarm-like wake with band state remaining 2: regression fixture.
    /// A sustained waking HR/motion tail must not be mistaken for a short
    /// bathroom visit; a return to sleep must still preserve the night.
    func testAlarmLikeTerminalWakeWithBandStillReportingSleep() throws {
        let base = Int(Calendar.current.date(from: DateComponents(
            year: 2026, month: 11, day: 19, hour: 23, minute: 0
        ))!.timeIntervalSince1970)
        let sleepStart = base + 600
        let wakeStart = sleepStart + 6 * 3600
        let end = wakeStart + 5 * 60
        var rows = (0..<600).map { row(base + $0, hr: 90, accel: 0.3, state: 0) }
        rows += (sleepStart..<wakeStart).map { row($0, hr: 60, accel: 0.008, state: 2) }
        rows += (wakeStart..<end).map {
            row($0, hr: 78, accel: $0 % 20 < 10 ? 0.09 : 0.02, state: 2)
        }
        let night = try XCTUnwrap(SleepDetect.detect(rows).first)
        XCTAssertLessThanOrEqual(night.endUnix, wakeStart + 60,
            "Sustained terminal wake evidence should not require a band-up state")
    }

    /// User-observed morning bathroom interruption: the band reports up for
    /// six minutes, then records a quiet return to sleep for twelve minutes.
    /// A terminal-wake trim must not discard the resumed sleep.
    func testSixMinuteMorningBathroomUpThenTwelveMinuteResumedSleep() throws {
        let base = Int(Calendar.current.date(from: DateComponents(
            year: 2026, month: 11, day: 24, hour: 0, minute: 0
        ))!.timeIntervalSince1970)
        let sleepStart = base + 60
        let bathroomStart = sleepStart + 6 * 3600
        let bathroomEnd = bathroomStart + 6 * 60
        let resumedEnd = bathroomEnd + 12 * 60
        var rows = (0..<60).map { row(base + $0, hr: 85, accel: 0.2, state: 0) }
        rows += (sleepStart..<bathroomStart).map { row($0, hr: 58, accel: 0.008, state: 2) }
        rows += (bathroomStart..<bathroomEnd).map { row($0, hr: 82, accel: 0.15, state: 3) }
        rows += (bathroomEnd..<resumedEnd).map { row($0, hr: 59, accel: 0.008, state: 2) }
        let detected = SleepDetect.detect(rows)
        XCTAssertEqual(detected.count, 1, "Bathroom trip followed by resumed sleep must remain one night")
        XCTAssertEqual(detected.first?.endUnix, resumedEnd - 1,
                       "Do not end sleep at the bathroom start when sleep resumes")
    }

}
