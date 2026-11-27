import Foundation
import XCTest
@testable import Strap

final class SleepSelectionAndStageEvidenceTests: XCTestCase {
    private func session(hour: Int, hours: Int, confirmed: Bool = true) throws -> SleepSession {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 3, day: 2, hour: hour)))
        let start = Int(date.timeIntervalSince1970)
        return SleepSession(version: SleepSession.algorithmVersion, sourceStartUnix: start,
            startUnix: start, endUnix: start + hours * 3600, staging: .unavailable,
            heartRate: [], movementBouts: 0, isEdited: false, bandSleepConfirmed: confirmed,
            timezoneIdentifier: "GMT")
    }

    func testPrimaryNightDoesNotSwitchToLongerNapOrMissingRRReplacement() throws {
        let night = try session(hour: 2, hours: 2)
        let nap = try session(hour: 12, hours: 3)
        XCTAssertEqual(DailyAnalysis.primaryNight([nap, night]), night)
        XCTAssertEqual(DailyAnalysis.primaryNight([night, nap]), night)
        XCTAssertEqual(DailyAnalysis.primaryNight([nap]), nap)
        XCTAssertNil(DailyAnalysis.primaryNight([]))
        let start = nap.startUnix
        let rows = (0..<600).map { row(start + $0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = try XCTUnwrap(DailyAnalysis.metrics(from: rows, sex: .male, maxHR: 180,
            calendar: calendar, analyzedSleepSessions: [night, nap]).first)
        XCTAssertEqual(day.sleepStartUnix, night.startUnix)
        XCTAssertNil(day.lnRMSSD)
        XCTAssertNil(day.restingHR)
    }

    private func row(_ unix: Int) -> V18Sample {
        V18Sample(header: BandRecordHeader(version: 18, flags: 0x80,
            recordIndex: UInt32(unix), unix: UInt32(unix), subsecQ15: 0),
            heartRate: 60, rrIntervalsMS: [unix % 2 == 0 ? 990 : 1010], dynamicAccelG: 0.01,
            gravityXG: 0, gravityYG: 0, gravityZG: 1,
            stepCounter: nil, stepCadence: nil, activityClass: nil,
            skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: nil, sleepState: 2, cardiacFlags: nil,
            hrQualityFlags: nil, spo2CandidateRaw: nil, spo2CandidatePct: nil,
            spo2CandidateKind: .absent, signalQualityLogVariance: nil, psnrB: nil, psnrA: nil)
    }

    func testStageTraceDoesNotChangeLabelsOrInventMissingEpochs() {
        let start = 1800000000
        let samples = (0..<600).filter { !(300..<330).contains($0) }.map { row(start + $0) }
        let period = SleepPeriod(startUnix: start, endUnix: start + 599,
            quietFraction: 1, meanHR: 60, wakeEvents: 0)
        var trace: [SleepStager.StageDecisionEvidence] = []
        let withTrace = SleepStager.stage(samples: samples, period: period, decisionSink: { trace = $0 })
        XCTAssertEqual(withTrace, SleepStager.stage(samples: samples, period: period))
        XCTAssertEqual(trace.count, 19)
        XCTAssertFalse(trace.contains { $0.startUnix == start + 300 })
        for item in trace {
            XCTAssertEqual(withTrace.segments.first {
                $0.startUnix <= item.startUnix && item.startUnix < $0.endUnix
            }?.stage, item.finalStage)
        }
    }
}
