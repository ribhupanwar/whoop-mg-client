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
        // SwiftUI may retain off-screen buttons in the accessibility tree.
        // What matters is that the scrolled-away Profile control cannot be
        // tapped while compact scores are displayed.
        let profile = app.buttons["Profile"]
        let profileNotHittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == false"),
            object: profile
        )
        XCTAssertEqual(XCTWaiter.wait(for: [profileNotHittable], timeout: 5), .completed,
                       "Profile control must be off-screen when compact scores are visible")
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
        let homeBedtime = app.staticTexts["home.bedtime"]
        XCTAssertTrue(homeBedtime.exists)
        let bedtime = homeBedtime.label
        editAlarm.tap()
        XCTAssertTrue(app.navigationBars["Sleep Planner"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["alarm.wakeTime"].exists)
        XCTAssertEqual(app.staticTexts["planner.bedtime"].label, bedtime)
    }

    func testActivitiesCanScrollClearOfFloatingNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview"]
        app.launch()

        let home = app.buttons["tab.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        let run = app.staticTexts["RUN"].firstMatch
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<6 where !run.isHittable || run.frame.maxY >= home.frame.minY {
            scroll.swipeUp()
        }
        XCTAssertTrue(run.isHittable)
        XCTAssertLessThan(run.frame.maxY, home.frame.minY)
        capture("Home activities above floating navigation", in: app)
    }

    func testDeviceSettingsShowsStatusAndBroadcastControl() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview"]
        app.launch()

        let device = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "device settings")).firstMatch
        XCTAssertTrue(device.waitForExistence(timeout: 15))
        device.tap()
        XCTAssertTrue(app.staticTexts["DEVICE SETTINGS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["STATUS"].exists)
        capture("Device settings status", in: app)
    }

    func testRefreshIndicatorIsHiddenAtRestAndAfterPullRelease() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview"]
        app.launch()

        XCTAssertTrue(app.staticTexts["home.today"].waitForExistence(timeout: 15))
        let indicator = app.descendants(matching: .any)["home.history.refresh"].firstMatch
        XCTAssertFalse(indicator.exists)

        let scroll = app.scrollViews.firstMatch
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertFalse(indicator.exists)
    }

    func testRefreshStaysBelowTodayAndCompactScoreHeader() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--preview-home-refresh"]
        app.launch()

        let today = app.staticTexts["home.today"]
        let refresh = app.descendants(matching: .any)["home.history.refresh"].firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 15))
        XCTAssertTrue(refresh.exists)
        XCTAssertGreaterThan(refresh.frame.minY, today.frame.maxY)

        let compact = app.descendants(matching: .any)["home.compact.sleep"].firstMatch
        for _ in 0..<3 where !compact.exists { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(compact.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(refresh.frame.minY, compact.frame.maxY)
        capture("Home compact header with refresh below scores", in: app)
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
