import XCTest

final class ManualActivityRecoveryTests: XCTestCase {
    func testUserCanCreateSwipeDeleteAndRestoreTheSameManualIdentity() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview", "--preview-train"]
        app.launch()
        let history = app.buttons["Edit or merge manual activities"]
        XCTAssertTrue(history.waitForExistence(timeout: 15)); history.tap()
        app.buttons["manual.history.add"].tap()
        let name = app.textFields["manual.name"]
        for _ in 0..<3 where !name.isHittable { app.swipeUp() }
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap()
        let label = "Synthetic UI entry " + String(UUID().uuidString.prefix(8))
        name.typeText(label)
        app.buttons["Save"].tap()
        let row = app.switches.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for _ in 0..<3 where !row.isHittable { app.swipeUp() }
        let originalID = row.identifier
        row.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: 5), .completed)
        let recover = app.buttons["Recover deleted manual entries"]
        for _ in 0..<3 where !recover.isHittable { app.swipeDown() }
        recover.tap()
        let revision = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Revision '")).firstMatch
        XCTAssertTrue(revision.waitForExistence(timeout: 10)); revision.tap()
        let restore = app.buttons["Restore missing entry"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 10)); restore.tap()
        XCTAssertTrue(app.staticTexts["Missing entry restored; current entries preserved."].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(row.identifier, originalID)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "STRAP-restored-synthetic-manual-entry"
        shot.lifetime = .keepAlways; add(shot)
    }
}
