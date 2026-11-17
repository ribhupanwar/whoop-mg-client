import XCTest

/// Reviewable native screenshots, not an assertion of pixel parity with an
/// unavailable WHOOP reference. Uses only labelled synthetic preview data.
final class ScreenCaptureTests: XCTestCase {
    func testCaptureAllFiveTabsWithVisibleSyntheticProvenance() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview"]
        app.launch()
        for tab in ["home", "health", "train", "plan", "more"] {
            let button = app.buttons["tab." + tab]
            XCTAssertTrue(button.waitForExistence(timeout: 15))
            button.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: button)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
            XCTAssertTrue(app.staticTexts["Design preview — sample data"].firstMatch.waitForExistence(timeout: 5),
                          "Synthetic values must retain visible provenance on every tab")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "STRAP-preview-" + tab
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}
