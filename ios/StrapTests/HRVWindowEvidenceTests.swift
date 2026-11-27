import Foundation
import XCTest
@testable import Strap

final class HRVWindowEvidenceTests: XCTestCase {
    private func row(_ unix: Int, rr: [Int], state: Int = 2) -> V18Sample {
        V18Sample(header: BandRecordHeader(version: 18, flags: 0x80,
            recordIndex: UInt32(unix), unix: UInt32(unix), subsecQ15: 0),
            heartRate: 60, rrIntervalsMS: rr, dynamicAccelG: 0.01,
            gravityXG: 0, gravityYG: 0, gravityZG: 1,
            stepCounter: nil, stepCadence: nil, activityClass: nil,
            skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: nil, sleepState: state, cardiacFlags: nil,
            hrQualityFlags: nil, spo2CandidateRaw: nil, spo2CandidatePct: nil,
            spo2CandidateKind: .absent, signalQualityLogVariance: nil, psnrB: nil, psnrA: nil)
    }

    func testExactRRDurationLimitDoesNotReportExcess() throws {
        let start = 1800000000
        let rows = (0..<300).map { row(start + $0, rr: [$0 % 2 == 0 ? 1040 : 1060]) }
        let session = SleepSession(version: SleepSession.algorithmVersion,
            sourceStartUnix: start, startUnix: start, endUnix: start + 300,
            staging: .unavailable, heartRate: [], movementBouts: 0, isEdited: false)
        let evidence = try XCTUnwrap(RecoveryDiagnostics.hrvWindowEvidence(samples: rows, session: session).first)
        XCTAssertEqual(evidence.rrDurationSeconds, 315)
        XCTAssertEqual(evidence.productionBucketGate, "qualifies_primary_bucket")
        XCTAssertEqual(evidence.bandState2Seconds, 300)
    }

    func testWindowEvidencePreservesGapsAndReportsExcessBeatDuration() throws {
        let start = 1800000000
        let valid = (0..<300).map { row(start + $0, rr: [$0 % 2 == 0 ? 990 : 1010]) }
        let excess = (300..<600).map { row(start + $0, rr: [990, 1010], state: 3) }
        let sparse = (600..<630).map { row(start + $0, rr: [1000]) }
        let session = SleepSession(version: SleepSession.algorithmVersion,
            sourceStartUnix: start, startUnix: start, endUnix: start + 900,
            staging: .unavailable, heartRate: [], movementBouts: 0, isEdited: false)
        let windows = RecoveryDiagnostics.hrvWindowEvidence(
            samples: valid + excess + sparse + [valid[0], row(start + 900, rr: [1000])],
            session: session)
        XCTAssertEqual(windows.count, 3)
        XCTAssertEqual(windows.map(\.observedSeconds), [300, 300, 30])
        XCTAssertEqual(windows.map(\.productionBucketGate),
            ["qualifies_primary_bucket", "excess_rr_duration", "insufficient_quiet_coverage"])
        XCTAssertEqual(try XCTUnwrap(windows.first?.candidateRMSSD), 20, accuracy: 0.001)
        XCTAssertEqual(windows[1].bandState3Seconds, 300)
        XCTAssertEqual(try XCTUnwrap(windows[1].rrDurationCoverage), 2, accuracy: 0.001)
    }
}
