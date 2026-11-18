import XCTest
@testable import Strap

final class SleepStageDisplayTests: XCTestCase {
    func testIndependentHalfMinuteRoundingDoesNotCreateExtraDisplayedMinute() {
        let stages: [SleepStage: Double] = [
            .wake: 37.5, .light: 167.0, .deep: 55.0, .rem: 140.0
        ]
        let display = SleepStageDisplay.rounded(stageMinutes: stages, windowMinutes: 399.5)
        XCTAssertEqual(display.stages.values.reduce(0, +) + display.unclassified, display.window)
        XCTAssertEqual(display.restorative, (display.stages[.deep] ?? 0) + (display.stages[.rem] ?? 0))
    }

    func testWholeMinuteStagesAndMissingCoverageRemainVisible() {
        let stages: [SleepStage: Double] = [
            .wake: 15, .light: 120, .deep: 60, .rem: 75
        ]
        let display = SleepStageDisplay.rounded(stageMinutes: stages, windowMinutes: 300)
        XCTAssertEqual(display.window, 300)
        XCTAssertEqual(display.unclassified, 30)
        XCTAssertEqual(display.stages[.wake], 15)
        XCTAssertEqual(display.restorative, 135)
        XCTAssertEqual(display.duration(display.window), "5:00")
        XCTAssertEqual(display.duration(display.restorative), "2:15")
    }

    func testNoDataDoesNotInventSleepStages() {
        let display = SleepStageDisplay.rounded(stageMinutes: [:], windowMinutes: 0)
        XCTAssertEqual(display.window, 0)
        XCTAssertEqual(display.restorative, 0)
        XCTAssertTrue(display.stages.values.allSatisfy { $0 == 0 })
    }
}
