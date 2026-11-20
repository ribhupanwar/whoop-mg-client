import XCTest

final class HomeScoreRingTests: XCTestCase {
    func testHomeKeepsScoresVisibleWhenHeroScrollsOffscreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 15))

        let compactSleep = app.descendants(matching: .any)["home.compact.sleep"].firstMatch
        XCTAssertFalse(compactSleep.exists)
        capture("Home expanded scores", in: app)

        let scrollingContent = app.scrollViews.firstMatch
        XCTAssertTrue(scrollingContent.exists)
        for _ in 0..<3 where !compactSleep.exists { scrollingContent.swipeUp() }
        XCTAssertTrue(compactSleep.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Profile"].waitForNonExistence(timeout: 5))
        capture("Home compact scores", in: app)

        for _ in 0..<4 where compactSleep.exists { scrollingContent.swipeDown() }
        XCTAssertTrue(compactSleep.waitForNonExistence(timeout: 5))
    }

    func testTonightSleepOpensPlannerWithWeeklySchedule() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 15))

        let editAlarm = app.buttons["home.sleepPlanner"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<3 where !editAlarm.isHittable { scroll.swipeUp() }
        XCTAssertTrue(editAlarm.isHittable)
        editAlarm.tap()
        XCTAssertTrue(app.navigationBars["Sleep Planner"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["alarm.wakeTime"].exists)
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
