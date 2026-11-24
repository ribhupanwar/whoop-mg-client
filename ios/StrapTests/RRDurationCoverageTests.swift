import XCTest
@testable import Strap

final class RRDurationCoverageTests: XCTestCase {
    func testNormalDurationCoverage() {
        XCTAssertEqual(Hrv.rrDurationCoverage([800, 800, 800, 800, 800], observedSeconds: 4), 1.0, accuracy: 0.00001)
    }

    func testDuplicateDurationFlagsExcessWithoutChangingHRV() {
        let coverage = Hrv.rrDurationCoverage(Array(repeating: 800, count: 10), observedSeconds: 4)
        XCTAssertNotNil(coverage)
        XCTAssertGreaterThan(coverage!, 1.0)
    }

    func testPaddingAndInvalidIntervalsAreExcluded() {
        XCTAssertEqual(Hrv.rrDurationCoverage([800, 0, 800], observedSeconds: 2), 0.8, accuracy: 0.00001)
    }

    func testUnknownDurationOrNoValidRRAbstains() {
        XCTAssertNil(Hrv.rrDurationCoverage([800], observedSeconds: 0))
        XCTAssertNil(Hrv.rrDurationCoverage([0, 0], observedSeconds: 5))
    }
}
