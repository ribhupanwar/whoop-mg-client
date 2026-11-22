import Foundation
import XCTest
@testable import Strap

/// Additional synthetic acceptance cases for the received-history diagnostic.
/// These tests do not assert hardware behavior or persisted ACK progress.
final class HistoryCoverageBatchRegressionTests: XCTestCase {
    private func sample(_ second: Int, hr: Int = 60, rr: [Int] = [900],
                        motion: Double? = 0.01) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(version: 18, flags: 0, recordIndex: UInt32(second),
                                     unix: UInt32(second), subsecQ15: 0),
            heartRate: hr, rrIntervalsMS: rr, dynamicAccelG: motion,
            gravityXG: 0, gravityYG: 0, gravityZG: 1,
            stepCounter: 0, stepCadence: nil, activityClass: 0,
            skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: nil, sleepState: 2, cardiacFlags: nil, hrQualityFlags: nil,
            spo2CandidateRaw: nil, spo2CandidatePct: nil, spo2CandidateKind: .absent,
            signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
        )
    }

    func testComplementaryReplayedChannelsAreUnionedWithoutInflatingCoverage() {
        let received = [
            sample(100, hr: 0, rr: [900], motion: nil),
            sample(100, hr: 61, rr: [], motion: 0.02),
            sample(101, hr: 0, rr: [], motion: nil),
            sample(101, hr: 0, rr: [810], motion: nil)
        ]
        let coverage = HistoryCoverage(received)
        XCTAssertEqual(coverage.observedSeconds, 2)
        XCTAssertEqual(coverage.heartRateSeconds, 1)
        XCTAssertEqual(coverage.rrSeconds, 2)
        XCTAssertEqual(coverage.motionSeconds, 1)
        XCTAssertEqual(coverage.missingSeconds, 0)
        XCTAssertEqual(coverage.repeatedSecondRecords, 2)
        XCTAssertEqual(coverage.backwardsTransitions, 0)
    }

    func testInterruptedTransferWithOutOfOrderReplayPreservesGapAccounting() {
        let received = [sample(200), sample(204), sample(200), sample(202), sample(204)]
        let coverage = HistoryCoverage(received)
        XCTAssertEqual(coverage.observedSeconds, 3)
        XCTAssertEqual(coverage.missingSeconds, 2)
        XCTAssertEqual(coverage.repeatedSecondRecords, 2)
        XCTAssertEqual(coverage.backwardsTransitions, 2)
        XCTAssertEqual(coverage.rrSeconds, 3)
    }

    func testInvalidHeartRateAndMotionDoNotCountAsValidChannels() {
        let received = [
            sample(300, hr: 34, rr: [], motion: -.infinity),
            sample(301, hr: 221, rr: [], motion: .nan),
            sample(302, hr: 60, rr: [], motion: -0.01),
            sample(303, hr: 70, rr: [800], motion: 0)
        ]
        let coverage = HistoryCoverage(received)
        XCTAssertEqual(coverage.observedSeconds, 4)
        XCTAssertEqual(coverage.heartRateSeconds, 2)
        XCTAssertEqual(coverage.rrSeconds, 1)
        XCTAssertEqual(coverage.motionSeconds, 1)
        XCTAssertEqual(coverage.missingSeconds, 0)
    }
}
