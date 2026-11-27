import XCTest
@testable import Strap

final class WristAngleInactivityExperimentTests: XCTestCase {
    private func sample(_ second: Int, z: Double?, state: Int = 2,
                        hr: Int = 60, motion: Double = 0.008) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(version: 18, flags: 0x80,
                                     recordIndex: UInt32(second), unix: UInt32(second),
                                     subsecQ15: 0),
            heartRate: hr, rrIntervalsMS: [], dynamicAccelG: motion,
            gravityXG: z == nil ? nil : sqrt(max(0, 1 - z! * z!)),
            gravityYG: z == nil ? nil : 0, gravityZG: z,
            stepCounter: nil, stepCadence: nil, activityClass: 0,
            skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: state << 4, sleepState: state,
            cardiacFlags: nil, hrQualityFlags: nil,
            spo2CandidateRaw: nil, spo2CandidatePct: nil,
            spo2CandidateKind: .absent,
            signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
        )
    }

    func testStableWristAngleIsInactivityEvidence() throws {
        let rows = (1000..<1300).map { sample($0, z: 0.9) }
        let result = try XCTUnwrap(WristAngleInactivityExperiment.evaluate(rows, startUnix: 1000))
        XCTAssertTrue(result.inactive)
        XCTAssertEqual(result.validSamples, 300)
    }

    func testChangingWristAngleIsNotInactive() throws {
        let rows = (1000..<1300).map { sample($0, z: $0 < 1150 ? 0.9 : 0.5) }
        let result = try XCTUnwrap(WristAngleInactivityExperiment.evaluate(rows, startUnix: 1000))
        XCTAssertFalse(result.inactive)
    }

    func testMissingGravityAbstains() {
        let rows = (1000..<1300).map { sample($0, z: nil) }
        XCTAssertNil(WristAngleInactivityExperiment.evaluate(rows, startUnix: 1000))
    }

    func testSparseCaptureAbstains() {
        let rows = stride(from: 1000, to: 1300, by: 3).map { sample($0, z: 0.9) }
        XCTAssertNil(WristAngleInactivityExperiment.evaluate(rows, startUnix: 1000))
    }

    func testBathroomBreakWithExplicitSleepResumption() {
        let rows = (1000..<1180).map { sample($0, z: 0.8, state: 3, hr: 80, motion: 0.2) }
            + (1180..<1540).map { sample($0, z: 0.9, state: 2) }
        XCTAssertEqual(SleepEndResumptionExperiment.evaluate(rows, wakeStartUnix: 1000),
                       .resumedSleep(endUnix: 1539))
    }

    func testQuietPersistentUpDoesNotProveWakeOrSleep() {
        let rows = (1000..<1600).map { sample($0, z: 0.9, state: 3) }
        XCTAssertEqual(SleepEndResumptionExperiment.evaluate(rows, wakeStartUnix: 1000),
                       .insufficientEvidence)
    }
}
