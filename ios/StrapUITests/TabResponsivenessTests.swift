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
        let homeButton = app.buttons["tab.home"]
        if !homeButton.waitForExistence(timeout: 15) {
            // Preserve the accessibility tree on CI failures so a missing
            // identifier can be distinguished from a hidden or delayed tab bar.
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Tab navigation accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Tab navigation at launch"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            XCTFail("Home tab button unavailable; inspect attached hierarchy and screenshot")
            return
        }
        var durations: [Double] = []
        for _ in 0..<3 {
            for tab in ["health", "humans", "more", "home"] {
                let button = app.buttons["tab." + tab]
                let start = Date()
                button.tap()
                // UI test snapshots can lag while the stress-sync fixture updates
                // the accessibility tree. Wait for the actual selected state without
                // incorrectly treating an XCTest predicate snapshot as permanent.
                let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: button)
                let result = XCTWaiter.wait(for: [selected], timeout: 10)
                if result != .completed {
                    let hierarchy = XCTAttachment(string: app.debugDescription)
                    hierarchy.name = "Tab \(tab) selection timeout hierarchy"
                    hierarchy.lifetime = .keepAlways
                    add(hierarchy)
                    let screenshot = XCTAttachment(screenshot: app.screenshot())
                    screenshot.name = "Tab \(tab) selection timeout"
                    screenshot.lifetime = .keepAlways
                    add(screenshot)
                }
                XCTAssertEqual(result, .completed,
                               "Tab \(tab) must respond while sync notifications continue")
                durations.append(Date().timeIntervalSince(start))
            }
        }
        let attachment = XCTAttachment(string: "Tab switch durations including XCTest input overhead: \(durations)")
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
