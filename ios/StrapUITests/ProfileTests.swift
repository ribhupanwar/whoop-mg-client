import XCTest

final class ProfileTests: XCTestCase {
    func testHomeProfileNameAppearsInMore() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview"]
        app.launch()

        let openProfile = app.buttons["Profile"]
        XCTAssertTrue(openProfile.waitForExistence(timeout: 15))
        openProfile.tap()
        let edit = app.buttons["profile.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        // ProfileEditor uses separate FIRST NAME and LAST NAME fields.
        // The old profile.displayName identifier no longer exists.
        let firstName = app.textFields["FIRST NAME"]
        XCTAssertTrue(firstName.waitForExistence(timeout: 10))
        firstName.tap()
        if let current = firstName.value as? String,
           current != "FIRST NAME", !current.isEmpty {
            firstName.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        firstName.typeText("Morgan")

        let save = app.buttons["profile.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable, "Save must remain reachable while the name field is being edited")
        save.tap()
        // Verify the save has completed before leaving the current stack.
        let savedName = app.staticTexts["profile.displayName"]
        XCTAssertTrue(savedName.waitForExistence(timeout: 15))
        XCTAssertTrue(savedName.label.contains("Morgan"))
        XCTAssertTrue(app.buttons["profile.edit"].waitForExistence(timeout: 5))

        let moreTab = app.buttons["tab.more"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 5))
        moreTab.tap()
        let selected = NSPredicate(format: "value == %@", "Selected")
        expectation(for: selected, evaluatedWith: moreTab)
        waitForExpectations(timeout: 10)
        let profile = app.buttons["more.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()

        let reopenedName = app.staticTexts["profile.displayName"]
        XCTAssertTrue(reopenedName.waitForExistence(timeout: 15))
        XCTAssertTrue(reopenedName.label.contains("Morgan"))
        let editAgain = app.buttons["profile.edit"]
        XCTAssertTrue(editAgain.waitForExistence(timeout: 5))
        editAgain.tap()
        XCTAssertTrue(firstName.waitForExistence(timeout: 10))
        XCTAssertEqual(firstName.value as? String, "Morgan")
    }
}
