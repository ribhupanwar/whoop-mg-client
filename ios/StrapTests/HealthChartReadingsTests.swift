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

    func testTimedSegmentsRetainDropoutsAndDiscardOldSamples() {
        let samples = [(1, 78), (100, 79), (101, 80), (102, 0), (103, 82), (110, 86), (111, 85)]
            .map { LiveSample(unix: $0.0, heartRate: $0.1, rrIntervalsMS: []) }

        let runs = HealthChartReadings.segments(samples)
        XCTAssertEqual(runs.map { $0.map(\.unix) }, [[100, 101], [103], [110, 111]])
        XCTAssertEqual(runs.last?.last?.heartRate, 85)
    }
}

final class HomeHistoryRefreshTests: XCTestCase {
    func testRefreshFollowsTransferThroughSavingAndAnalysis() {
        XCTAssertTrue(HomeHistoryRefresh.isActive(status: .draining, saving: false, analyzing: false, failed: false))
        XCTAssertTrue(HomeHistoryRefresh.isActive(status: .ready, saving: true, analyzing: false, failed: false))
        XCTAssertTrue(HomeHistoryRefresh.isActive(status: .ready, saving: false, analyzing: true, failed: false))
        XCTAssertFalse(HomeHistoryRefresh.isActive(status: .ready, saving: false, analyzing: false, failed: false))
    }

    func testFailureStopsLoadingAndAllowsRetryWhenLinkIsReady() {
        XCTAssertFalse(HomeHistoryRefresh.isActive(status: .disconnected("Out of range"),
                                                   saving: true, analyzing: false, failed: true))
        XCTAssertTrue(HomeHistoryRefresh.canRequest(status: .ready, saving: false, analyzing: false))
        XCTAssertFalse(HomeHistoryRefresh.canRequest(status: .draining, saving: false, analyzing: false))
        XCTAssertFalse(HomeHistoryRefresh.canRequest(status: .ready, saving: true, analyzing: false))
        XCTAssertFalse(HomeHistoryRefresh.canRequest(status: .reconnecting(attempt: 1), saving: false, analyzing: false))
    }
}
