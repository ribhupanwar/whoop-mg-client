import XCTest
@testable import Strap

final class SensorCalibrationResearchTests: XCTestCase {
    func testOpticalRatioIsNotOxygenPercentage() throws {
        let red = (0..<300).map { 1000.0 + 20.0 * sin(Double($0)*0.3) }
        let ir = (0..<300).map { 2000.0 + 20.0 * sin(Double($0)*0.3) }
        func window(mapping: String = "synthetic", gap: Bool = false,
                    motion: Double? = 0.01, infrared: [Double]? = nil) -> SensorCalibrationResearch.OpticalWindow {
            .init(deviceID: "synthetic", firmware: "synthetic", startUnix: 1000,
                  sampleRateHz: 25, redADC: red, infraredADC: infrared ?? ir,
                  mappingEvidenceID: mapping, railOrGapObserved: gap, motionG: motion)
        }
        let ratio = try XCTUnwrap(SensorCalibrationResearch.opticalRatio(window()))
        XCTAssertEqual(ratio.ratioOfRatios, 2, accuracy: 0.02)
        XCTAssertNil(SensorCalibrationResearch.opticalRatio(window(mapping: "")))
        XCTAssertNil(SensorCalibrationResearch.opticalRatio(window(gap: true)))
        XCTAssertNil(SensorCalibrationResearch.opticalRatio(window(motion: nil)))
        XCTAssertNil(SensorCalibrationResearch.opticalRatio(window(infrared: Array(repeating: 2000, count: 300))))
    }

    func testRelativeTemperatureRequiresMatchedPriorNights() throws {
        typealias Night = SensorCalibrationResearch.TemperatureNight
        let current = Night(dayID: "2026-11-28", deviceID: "a", firmware: "x",
                            fieldSource: "65", decodedMedian: 34, observedSeconds: 600)
        let prior = (1...7).map { day in
            Night(dayID: String(format: "2026-11-%02d", day), deviceID: "a",
                  firmware: "x", fieldSource: "65", decodedMedian: 33.5, observedSeconds: 600)
        }
        XCTAssertEqual(try XCTUnwrap(SensorCalibrationResearch.temperatureDeviation(current: current, prior: prior)), 0.5, accuracy: 0.001)
        XCTAssertNil(SensorCalibrationResearch.temperatureDeviation(current: current, prior: Array(repeating: prior[0], count: 7)))
        let wrong = prior.map { Night(dayID: $0.dayID, deviceID: "a", firmware: "y", fieldSource: "65", decodedMedian: 33.5, observedSeconds: 600) }
        XCTAssertNil(SensorCalibrationResearch.temperatureDeviation(current: current, prior: wrong))
    }

    func testEmptyCaptureDoesNotInventHealthValues() {
        let result = SensorCalibrationResearch.nightEvidence(samples: [], startUnix: 1, endUnix: 300)
        XCTAssertEqual(result.observedQuietSeconds, 0)
        XCTAssertTrue(result.oxygenRawByteCounts.isEmpty)
        XCTAssertEqual(result.temperatureChannels.count, 3)
        XCTAssertTrue(result.temperatureChannels.allSatisfy { $0.decodedMedian == nil })
    }
}
