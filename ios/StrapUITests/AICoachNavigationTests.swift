import XCTest

final class AICoachNavigationTests: XCTestCase {
    func testCoachOpensAnswersAndShowsProviderSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview"]
        app.launch()

        let open = app.buttons["nav.aiCoach"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        let question = app.descendants(matching: .any)["coach.question"].firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        question.tap()
        question.typeText("What is VO2 max?")
        app.buttons["coach.send"].tap()

        let answer = app.staticTexts["coach.answer"].firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 8))
        XCTAssertTrue(answer.label.contains("mL/kg/min"))
        app.buttons["coach.settings"].tap()
        XCTAssertTrue(app.navigationBars["Coach AI"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["AI model"].exists)
    }
}
