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
        let editProfile = app.buttons["profile.edit"]
        XCTAssertTrue(editProfile.waitForExistence(timeout: 15))
        editProfile.tap()
        // Navigation transitions can take longer on shared CI simulators.
        // Wait for the destination, not just the originating edit button.
        let name = app.textFields["profile.displayName"]
        XCTAssertTrue(name.waitForExistence(timeout: 15),
                      "Edit Profile must expose the display-name field after navigation")
        name.tap()
        if let savedName = name.value as? String, savedName != "Display name" {
            name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: savedName.count))
        }
        name.typeText("Morgan")
        app.buttons["Save"].tap()

        let moreTab = app.buttons["tab.more"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 5))
        moreTab.tap()
        let profile = app.buttons["more.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()
        app.buttons["profile.edit"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Morgan")
    }
}
