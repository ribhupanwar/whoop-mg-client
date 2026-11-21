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
    func testLiveSegmentCannotReconnectToPriorConnectionOrMismatchedBPM() {
        let samples = [(100, 78), (102, 80), (104, 225)]
            .map { LiveSample(unix: $0.0, heartRate: $0.1, rrIntervalsMS: []) }
        let connection = Date(timeIntervalSince1970: 101.5)
        XCTAssertEqual(HealthChartReadings.liveSegments(samples, connection: connection, currentBPM: 225)
            .flatMap { $0 }.map(\.unix), [102, 104])
        XCTAssertTrue(HealthChartReadings.liveSegments(samples, connection: connection, currentBPM: 80).isEmpty)
    }
    func testBackwardClockAdjustmentKeepsFreshEndpointAndDropsOldTimeline() {
        let samples = [(200, 80), (190, 150), (191, 151)]
            .map { LiveSample(unix: $0.0, heartRate: $0.1, rrIntervalsMS: []) }
        let connection = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(HealthChartReadings.liveSegments(samples, connection: connection, currentBPM: 151)
            .flatMap { $0 }.map(\.unix), [190, 191])
    }

    func testFreshConnectionCanPlotAfterWallClockMovesBeforeHandshakeTime() {
        let fresh = LiveSample(unix: 98, heartRate: 150, rrIntervalsMS: [])
        let connection = Date(timeIntervalSince1970: 100.5)
        XCTAssertEqual(HealthChartReadings.liveSegments([fresh], connection: connection, currentBPM: 150), [[fresh]])
    }

}

final class HomeHistoryRefreshTests: XCTestCase {
    func testRefreshFollowsTransferThroughSavingAndAnalysis() {
        XCTAssertTrue(HomeHistoryRefresh.isActive(status: .authenticating, saving: false, analyzing: false, failed: false))
        XCTAssertTrue(HomeHistoryRefresh.isActive(status: .draining, saving: false, analyzing: false, failed: false))
        XCTAssertTrue(HomeHistoryRefresh.isActive(status: .ready, saving: true, analyzing: false, failed: false))
        XCTAssertTrue(HomeHistoryRefresh.isActive(status: .ready, saving: false, analyzing: true, failed: false))
        XCTAssertFalse(HomeHistoryRefresh.isActive(status: .ready, saving: false, analyzing: false, failed: false))
    }

    func testFailureStopsLoadingAndAllowsRetryWhenLinkIsReady() {
        XCTAssertFalse(HomeHistoryRefresh.isActive(status: .disconnected("Out of range"),
                                                   saving: true, analyzing: false, failed: true))
        XCTAssertFalse(HomeHistoryRefresh.isActive(status: .draining, saving: true, analyzing: true, failed: true))
        XCTAssertTrue(HomeHistoryRefresh.canRequest(status: .ready, saving: false, analyzing: false))
        XCTAssertFalse(HomeHistoryRefresh.canRequest(status: .draining, saving: false, analyzing: false))
        XCTAssertFalse(HomeHistoryRefresh.canRequest(status: .authenticating, saving: false, analyzing: false))
        XCTAssertFalse(HomeHistoryRefresh.canRequest(status: .scanning, saving: false, analyzing: false))
        XCTAssertFalse(HomeHistoryRefresh.canRequest(status: .connecting, saving: false, analyzing: false))
        XCTAssertFalse(HomeHistoryRefresh.canRequest(status: .ready, saving: true, analyzing: false))
        XCTAssertFalse(HomeHistoryRefresh.canRequest(status: .ready, saving: false, analyzing: true))
        XCTAssertFalse(HomeHistoryRefresh.canRequest(status: .reconnecting(attempt: 1), saving: false, analyzing: false))
    }
}
