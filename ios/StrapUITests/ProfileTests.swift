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
        app.buttons["profile.edit"].tap()
        let name = app.textFields["profile.displayName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
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
