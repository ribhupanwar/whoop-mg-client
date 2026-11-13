import XCTest
@testable import Strap

/// Regression tests for the OpenStrap Gen5 v18 layout and durable archive serialization.
final class HistoricalArchiveTests: XCTestCase {
    func testV18SampleRoundTripPreservesRRAndTimestamp() throws {
        let header = BandRecordHeader(version: 18, flags: 0, recordIndex: 42,
                                      unix: 1_762_800_000, subsecQ15: 0)
        let original = V18Sample(
            header: header, heartRate: 63, rrIntervalsMS: [943, 951],
            dynamicAccelG: 0.02, gravityXG: nil, gravityYG: nil,
            gravityZG: nil, stepCounter: 12, stepCadence: nil,
            activityClass: nil, skinTempC: nil, tempAux1C: nil,
            tempAux2C: nil, sleepStateByte: nil, sleepState: nil,
            cardiacFlags: nil, hrQualityFlags: nil, spo2CandidateRaw: nil,
            spo2CandidatePct: nil, spo2CandidateKind: .absent,
            signalQualityLogVariance: nil, psnrB: nil, psnrA: nil)
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([V18Sample].self, from: data)
        XCTAssertEqual(decoded, [original])
        XCTAssertEqual(decoded.first?.rrIntervalsMS, [943, 951])
        XCTAssertEqual(decoded.first?.unix, 1_762_800_000)
    }

    func testArchiveSelectionKeepsUsableHROverRicherDuplicate() {
        func sample(index: UInt32, hr: Int, rr: [Int], motion: Double?) -> V18Sample {
            V18Sample(
                header: BandRecordHeader(version: 18, flags: 0, recordIndex: index,
                                         unix: 1_762_800_000, subsecQ15: 0),
                heartRate: hr, rrIntervalsMS: rr, dynamicAccelG: motion,
                gravityXG: nil, gravityYG: nil, gravityZG: nil,
                stepCounter: nil, stepCadence: nil, activityClass: nil,
                skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
                sleepStateByte: nil, sleepState: nil, cardiacFlags: nil,
                hrQualityFlags: nil, spo2CandidateRaw: nil, spo2CandidatePct: nil,
                spo2CandidateKind: .absent, signalQualityLogVariance: nil,
                psnrB: nil, psnrA: nil)
        }

        let validHR = sample(index: 2, hr: 68, rr: [], motion: nil)
        let richerOffWrist = sample(index: 1, hr: 0, rr: [800, 810, 805, 815], motion: 0.02)
        XCTAssertTrue(HistoricalRecordSelection.prefers(validHR, over: richerOffWrist))
        XCTAssertFalse(HistoricalRecordSelection.prefers(richerOffWrist, over: validHR))
    }

    func testArchiveSelectionUsesAuxiliaryRichnessWhenBothHaveValidHR() {
        func sample(index: UInt32, rr: [Int], motion: Double?) -> V18Sample {
            V18Sample(
                header: BandRecordHeader(version: 18, flags: 0, recordIndex: index,
                                         unix: 1_762_800_000, subsecQ15: 0),
                heartRate: 68, rrIntervalsMS: rr, dynamicAccelG: motion,
                gravityXG: nil, gravityYG: nil, gravityZG: nil,
                stepCounter: nil, stepCadence: nil, activityClass: nil,
                skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
                sleepStateByte: nil, sleepState: nil, cardiacFlags: nil,
                hrQualityFlags: nil, spo2CandidateRaw: nil, spo2CandidatePct: nil,
                spo2CandidateKind: .absent, signalQualityLogVariance: nil,
                psnrB: nil, psnrA: nil)
        }

        let richer = sample(index: 2, rr: [800, 810], motion: 0.02)
        let leaner = sample(index: 1, rr: [], motion: nil)
        XCTAssertTrue(HistoricalRecordSelection.prefers(richer, over: leaner))
    }

    func testV18DecoderDoesNotMistakeV26ForV18() {
        var frame = [UInt8](repeating: 0, count: 109)
        frame[0] = 0x2F
        frame[1] = 26
        XCTAssertNil(V18Decoder.decode(frame))
    }
}
