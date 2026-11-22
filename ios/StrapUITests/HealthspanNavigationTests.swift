import XCTest

final class HealthspanNavigationTests: XCTestCase {
    func testHealthspanOpensAndCanReturnFromPreviousWeek() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview"]
        app.launch()

        let health = app.buttons["tab.health"]
        XCTAssertTrue(health.waitForExistence(timeout: 15))
        health.tap()
        let open = app.buttons["healthspan.open"]
        if !open.isHittable { app.swipeUp() }
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let previous = app.buttons["Previous week"]
        let next = app.buttons["Next week"]
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled)
        previous.tap()
        XCTAssertTrue(next.isEnabled)
        next.tap()
        XCTAssertFalse(next.isEnabled)
        app.buttons["About Healthspan"].tap()
        XCTAssertTrue(app.alerts["About Healthspan"].waitForExistence(timeout: 5))
    }
}
