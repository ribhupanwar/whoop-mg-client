import XCTest
@testable import Strap

final class HealthChartReadingsTests: XCTestCase {
    func testInvalidReadingsCannotBecomePlottedHeartRate() {
        let values: [Double] = [Double.nan, -1, 0, 34, 35, 82, 220, 221, Double.infinity]
        XCTAssertEqual(HealthChartReadings.valid(values), [35, 82, 220])
    }

    func testUnavailableReadingsDoNotFabricateFlatTrace() {
        XCTAssertTrue(HealthChartReadings.valid([]).isEmpty)
        XCTAssertTrue(HealthChartReadings.valid([Double.nan, 0, 400]).isEmpty)
        XCTAssertEqual(HealthChartReadings.valid([77, 81, 79]), [77, 81, 79])
    }
}
