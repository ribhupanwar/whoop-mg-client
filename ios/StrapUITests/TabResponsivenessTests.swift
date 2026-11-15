import XCTest

final class TabResponsivenessTests: XCTestCase {
    func testEveryTabRemainsSelectableDuringContinuousSyncUpdates() {
        continueAfterFailure = false
        executionTimeAllowance = 120
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--stress-tab-switching"]
        addUIInterruptionMonitor(withDescription: "System permissions") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            return false
        }
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 15))
        var durations: [Double] = []
        for _ in 0..<3 {
            for tab in ["health", "train", "plan", "more", "home"] {
                let button = app.buttons["tab." + tab]
                let start = Date()
                button.tap()
                let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: button)
                XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                               "Tab \(tab) must respond while sync notifications continue")
                durations.append(Date().timeIntervalSince(start))
            }
        }
        let attachment = XCTAttachment(string: "Tab switch durations including XCTest input overhead: \(durations)")
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
