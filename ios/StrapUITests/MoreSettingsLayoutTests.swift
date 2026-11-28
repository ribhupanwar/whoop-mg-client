import XCTest

final class MoreSettingsLayoutTests: XCTestCase {
    func testFirmwareLabNavigationFromMore() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview"]
        app.launch()

        let more = app.buttons["tab.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()
        let device = app.buttons["more.deviceSettings"]
        XCTAssertTrue(device.waitForExistence(timeout: 10))
        for _ in 0..<3 where !device.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(device.isHittable)
        device.tap()

        let advanced = app.buttons["ADVANCED"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 10))
        advanced.tap()

        let firmware = app.buttons["deviceSettings.firmwareLab"]
        for _ in 0..<5 where !firmware.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(firmware.exists)
        XCTAssertTrue(firmware.isHittable)
        XCTAssertGreaterThanOrEqual(firmware.frame.height, 44)
        let settings = XCTAttachment(screenshot: app.screenshot())
        settings.name = "Device advanced settings and Firmware Lab navigation"
        settings.lifetime = .keepAlways
        add(settings)
        firmware.tap()

        XCTAssertTrue(app.navigationBars["FIRMWARE LAB"].waitForExistence(timeout: 10))
        let choose = app.buttons["firmwareLab.chooseImage"]
        for _ in 0..<3 where !choose.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(choose.isHittable)
        XCTAssertGreaterThanOrEqual(choose.frame.height, 44)
        // No install action: the disabled hardware section is informational.
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "INSTALL FIRMWARE")).firstMatch.exists)
        let lab = XCTAttachment(screenshot: app.screenshot())
        lab.name = "Firmware Lab read-only inspection layout"
        lab.lifetime = .keepAlways
        add(lab)
    }
}
