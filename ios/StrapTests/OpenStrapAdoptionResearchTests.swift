import XCTest
@testable import Strap

final class OpenStrapAdoptionResearchTests: XCTestCase {
    func testIrregularHarmonicPeak() throws {
        // Synthetic irregular sampling, known 15 breaths/min signal.
        var time = 0.0
        var times: [Double] = [], rr: [Double] = []
        while time < 300 {
            let interval = 1000 + 75 * sin(2 * .pi * 0.25 * time)
            times.append(time)
            rr.append(interval)
            time += interval / 1000
        }
        let peak = try XCTUnwrap(OpenStrapAdoptionResearch.spectralPeak(times: times, rrMS: rr))
        XCTAssertEqual(peak.rpm, 15, accuracy: 0.3)
        XCTAssertGreaterThan(peak.power, 0.9)
    }

    func testFlatAndUnresolvableSignalAbstain() {
        let times = (0..<300).map(Double.init)
        XCTAssertNil(OpenStrapAdoptionResearch.spectralPeak(times: times, rrMS: Array(repeating: 1000, count: 300)))
        let slow = times.map { 1400 + 80 * sin(2 * .pi * 0.25 * $0) }
        XCTAssertNil(OpenStrapAdoptionResearch.spectralPeak(times: times, rrMS: slow))
        XCTAssertNil(OpenStrapAdoptionResearch.spectralPeak(times: Array(times.reversed()), rrMS: slow))
    }

    func testMissingWindowsCountAgainstRespiratoryConsensus() {
        let report = OpenStrapAdoptionResearch.respiratoryReport(samples: [], startUnix: 1000, endUnix: 1900)
        XCTAssertEqual(report.attemptedWindows, 3)
        XCTAssertEqual(report.agreeingWindows, 0)
        XCTAssertNil(report.candidateRPM)
        XCTAssertTrue(report.windows.allSatisfy { $0.reason != nil })
    }

    func testCalibrationRequiresIndependentConsistentRuns() throws {
        typealias Run = OpenStrapAdoptionResearch.StepCalibrationRun
        let runs = (1...3).map { Run(deviceID: "test", wearingLocation: "wrist",
            sessionID: String($0), referenceCount: 1000, rawBandCount: 800) }
        XCTAssertNil(OpenStrapAdoptionResearch.stepCalibrationFactor([runs[0], runs[0], runs[0]],
            deviceID: "test", wearingLocation: "wrist"))
        XCTAssertNil(OpenStrapAdoptionResearch.stepCalibrationFactor(runs,
            deviceID: "test", wearingLocation: "bicep"))
        XCTAssertEqual(try XCTUnwrap(OpenStrapAdoptionResearch.stepCalibrationFactor(runs,
            deviceID: "test", wearingLocation: "wrist")), 1.125, accuracy: 0.0001)
        let conflict = Run(deviceID: "test", wearingLocation: "wrist",
            sessionID: "1", referenceCount: 1000, rawBandCount: 950)
        XCTAssertNil(OpenStrapAdoptionResearch.stepCalibrationFactor(runs + [conflict],
            deviceID: "test", wearingLocation: "wrist"))
    }

    func testRegularityDoesNotTurnMissingIntoWake() throws {
        var a = Array<Bool?>(repeating: false, count: 2880)
        for i in 0..<960 { a[i] = true }
        var b = a
        b[0] = nil
        let same = try XCTUnwrap(OpenStrapAdoptionResearch.regularity(previous: a, following: b))
        XCTAssertEqual(same.observedPairs, 2879)
        XCTAssertEqual(same.index, 100)
        let inverse = a.map { $0.map { !$0 } }
        XCTAssertEqual(try XCTUnwrap(OpenStrapAdoptionResearch.regularity(previous: a, following: inverse)).index, -100)
        for i in 0..<600 { b[i] = nil }
        XCTAssertNil(OpenStrapAdoptionResearch.regularity(previous: a, following: b))
    }
}
