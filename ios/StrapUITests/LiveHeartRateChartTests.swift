import XCTest

final class LiveHeartRateChartTests: XCTestCase {
    func testLargeBPMAndHorizontalIndicatorShareTheSameReading() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--preview-health-monitor", "--preview-live-bpm=150"]
        app.launch()
        let value = app.staticTexts["health.live.bpm"]
        XCTAssertTrue(value.waitForExistence(timeout: 15))
        XCTAssertEqual(value.label, "150")
        let indicator = app.otherElements["health.live.indicator"]
        XCTAssertTrue(indicator.exists)
        XCTAssertEqual(indicator.value as? String, "live")
        XCTAssertLessThan(indicator.frame.maxX, app.frame.maxX + 1)
    }
    func testStaleStateHasNeitherBPMNorLiveIndicator() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--preview-health-monitor", "--preview-hr-stale"]
        app.launch()
        let value = app.staticTexts["health.live.bpm"]
        XCTAssertTrue(value.waitForExistence(timeout: 15))
        XCTAssertEqual(value.label, "—")
        XCTAssertEqual(app.otherElements["health.live.indicator"].value as? String, "unavailable")
    }
}
