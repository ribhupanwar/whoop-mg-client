import XCTest
@testable import Strap

final class HealthspanInsightsTests: XCTestCase {
    func testScreenshotAgeReplayUsesOnlySupportedImpacts() throws {
        let activity = try XCTUnwrap(FitnessAgeModel.activityIndex(activeDays: 2, averageMinutes: 23, highIntensityFraction: 0))
        let impact = try XCTUnwrap(FitnessAgeModel.impact(age: 38, sex: .male, restingHR: 65, activityIndex: activity))
        XCTAssertEqual(impact.restingHeartRate, 0)
        XCTAssertEqual(impact.activity, 3.527432432432432, accuracy: 0.00001)
        XCTAssertEqual(FitnessAgeModel.calculate(age: 38, sex: .male, restingHR: 65, activityIndex: activity) ?? 0,
                       41.52743243243243, accuracy: 0.00001)
    }

    func testObservedWeeklyTotalsLeaveMissingMetricsUnscored() {
        let first = MetricDay(date: Date(timeIntervalSince1970: 10), key: "prior", recorded: nil,
            recovery: nil, zones: [60, 0, 0, 0, 0], calories: nil, strength: 30)
        let recent = MetricDay(date: Date(timeIntervalSince1970: 20), key: "recent", recorded: nil,
            recovery: nil, zones: [60, 120, 0, 60, 0], calories: nil, strength: nil)
        let gap = MetricDay(date: Date(timeIntervalSince1970: 30), key: "gap", recorded: nil,
            recovery: nil, zones: nil, calories: nil, strength: nil)
        let insights = HealthspanInsights(days: [first, recent] + Array(repeating: gap, count: 6))
        XCTAssertEqual(insights.activity[0].value, 3)
        XCTAssertEqual(insights.activity[0].prior, 1)
        XCTAssertEqual(insights.activity[0].observed, 1)
        XCTAssertNil(insights.activity[2].value)
        XCTAssertEqual(insights.activity[2].prior, 30)
        XCTAssertNil(insights.sleep[1].value)
        XCTAssertNil(insights.fitness.last?.value)
    }
}
