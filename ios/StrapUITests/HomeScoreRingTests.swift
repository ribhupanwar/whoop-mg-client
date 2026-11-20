import XCTest

final class HomeScoreRingTests: XCTestCase {
    func testHomeKeepsScoresVisibleWhenHeroScrollsOffscreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 15))

        let compactSleep = app.buttons["home.compact.sleep"]
        XCTAssertFalse(compactSleep.exists)
        capture("Home expanded scores", in: app)

        let scrollingContent = app.scrollViews.firstMatch
        XCTAssertTrue(scrollingContent.exists)
        scrollingContent.swipeUp()
        XCTAssertTrue(compactSleep.waitForExistence(timeout: 5))
        capture("Home compact scores", in: app)

        for _ in 0..<4 where compactSleep.exists { scrollingContent.swipeDown() }
        XCTAssertFalse(compactSleep.exists)
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
