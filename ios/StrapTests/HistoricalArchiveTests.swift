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

    func testArchiveKeepsSubsecondRecordsAndPrefersValidHRForExactDuplicate() {
        let base = UInt32(1_762_800_000)
        func sample(_ index: UInt32, _ subsec: Int, _ hr: Int) -> V18Sample {
            V18Sample(
                header: BandRecordHeader(version: 18, flags: 0, recordIndex: index, unix: base, subsecQ15: subsec),
                heartRate: hr, rrIntervalsMS: [], dynamicAccelG: nil, gravityXG: nil, gravityYG: nil,
                gravityZG: nil, stepCounter: nil, stepCadence: nil, activityClass: nil,
                skinTempC: nil, tempAux1C: nil, tempAux2C: nil, sleepStateByte: nil, sleepState: nil,
                cardiacFlags: nil, hrQualityFlags: nil, spo2CandidateRaw: nil, spo2CandidatePct: nil,
                spo2CandidateKind: .absent, signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
            )
        }
        let samples = HistoricalArchive.deduplicated([sample(7, 0, 0), sample(7, 0, 63), sample(7, 16_384, 64)])
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples.map(\.heartRate), [63, 64])
        XCTAssertEqual(samples.map { $0.header.subsecQ15 }, [0, 16_384])
    }

    func testV18DecoderDoesNotMistakeV26ForV18() {
        var frame = [UInt8](repeating: 0, count: 109)
        frame[0] = 0x2F
        frame[1] = 26
        XCTAssertNil(V18Decoder.decode(frame))
    }
    func testArchiveRetainsDifferentTimestampsWhenRecordIndexIsReused() {
        func sample(_ index: UInt32, _ unix: UInt32, _ hr: Int) -> V18Sample {
            V18Sample(
                header: BandRecordHeader(version: 18, flags: 0, recordIndex: index, unix: unix, subsecQ15: 0),
                heartRate: hr, rrIntervalsMS: [900], dynamicAccelG: 0.02, gravityXG: nil, gravityYG: nil,
                gravityZG: nil, stepCounter: nil, stepCadence: nil, activityClass: nil,
                skinTempC: nil, tempAux1C: nil, tempAux2C: nil, sleepStateByte: nil, sleepState: nil,
                cardiacFlags: nil, hrQualityFlags: nil, spo2CandidateRaw: nil, spo2CandidatePct: nil,
                spo2CandidateKind: .absent, signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
            )
        }

        let samples = HistoricalArchive.deduplicated([
            sample(42, 1_762_800_000, 63),
            sample(42, 1_762_800_001, 64),
            sample(42, 1_762_800_001, 0)
        ])

        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples.map { $0.unix }, [1_762_800_000, 1_762_800_001])
        XCTAssertEqual(samples.map { $0.heartRate }, [63, 64])
    }

}
