import XCTest
@testable import Strap

/// A stored CaptureSummary from before the daytime stress fields existed must
/// still load: the app keeps the old summary instead of dropping the capture.
final class CaptureCompatibilityTests: XCTestCase {
    private func sample(_ unix: Int, rr: [Int]) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(
                version: 18, flags: 0x80, recordIndex: UInt32(unix),
                unix: UInt32(unix), subsecQ15: 0
            ),
            heartRate: 60,
            rrIntervalsMS: rr,
            dynamicAccelG: 0.01,
            gravityXG: nil,
            gravityYG: nil,
            gravityZG: nil,
            stepCounter: nil,
            stepCadence: nil,
            activityClass: 0,
            skinTempC: nil,
            tempAux1C: nil,
            tempAux2C: nil,
            sleepStateByte: nil,
            sleepState: nil,
            cardiacFlags: nil,
            hrQualityFlags: nil,
            spo2CandidateRaw: nil,
            spo2CandidatePct: nil,
            spo2CandidateKind: .absent,
            signalQualityLogVariance: nil,
            psnrB: nil,
            psnrA: nil
        )
    }

    private func summary() -> CaptureSummary {
        let samples = (0..<20).map { sample(1_700_000_000 + $0 * 30, rr: [1000, 1100]) }
        return CaptureSummary.make(samples: samples, sex: .male, maxHR: 190)
    }

    func testSummaryCarriesTimestampedMinuteHeartRate() {
        let original = summary()
        let timeline = original.heartRateTimeline ?? []
        XCTAssertEqual(timeline.count, 10)
        XCTAssertEqual(timeline.first?.unix, (1_700_000_000 / 60) * 60)
        XCTAssertEqual(timeline.first?.bpm ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(original.heartRateSeries, timeline.map(\.bpm))
    }

    func testSummaryWithoutStressFieldsStillDecodes() throws {
        let original = summary()
        let data = try JSONEncoder().encode(original)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNotNil(object["awakeStress"], "new summaries should carry the daytime split")
        XCTAssertNotNil(object["heartRateTimeline"], "new summaries should preserve HR timestamps")
        object.removeValue(forKey: "awakeStress")
        object.removeValue(forKey: "outsideWorkoutStress")
        object.removeValue(forKey: "stressSeries")
        object.removeValue(forKey: "heartRateTimeline")
        let old = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(CaptureSummary.self, from: old)
        XCTAssertEqual(decoded.sampleCount, original.sampleCount)
        XCTAssertEqual(decoded.firstUnix, original.firstUnix)
        XCTAssertEqual(decoded.lastUnix, original.lastUnix)
        if let before = original.hrv.lnRMSSD, let after = decoded.hrv.lnRMSSD {
            XCTAssertEqual(after, before, accuracy: 0.000001)
        } else {
            XCTAssertEqual(decoded.hrv.lnRMSSD, original.hrv.lnRMSSD)
        }
        XCTAssertNil(decoded.awakeStress)
        XCTAssertNil(decoded.outsideWorkoutStress)
        XCTAssertNil(decoded.stressSeries)
        XCTAssertNil(decoded.heartRateTimeline)
    }
}
