import XCTest
@testable import Strap

final class HealthspanInsightsTests: XCTestCase {
    func testLeanMassIncludesWholeSeventhCalendarDayAndExcludesFutureAndOlderDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        func date(_ day: Int, _ hour: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour)))
        }
        let now = try date(22, 10)
        let seventhDay = ProfileBodyMeasurement(kilograms: 48, date: try date(16, 9), source: "Test")
        XCTAssertEqual(HealthspanInsights.recentLeanMass(seventhDay, endingOn: calendar.startOfDay(for: now), now: now, calendar: calendar), seventhDay)
        let previousDay = ProfileBodyMeasurement(kilograms: 48, date: try date(15, 23), source: "Test")
        XCTAssertNil(HealthspanInsights.recentLeanMass(previousDay, endingOn: calendar.startOfDay(for: now), now: now, calendar: calendar))
        let today = ProfileBodyMeasurement(kilograms: 48, date: try date(22, 9), source: "Test")
        XCTAssertEqual(HealthspanInsights.recentLeanMass(today, endingOn: calendar.startOfDay(for: now),
                                                        now: now, calendar: calendar), today)
        let future = ProfileBodyMeasurement(kilograms: 48, date: try date(22, 12), source: "Test")
        XCTAssertNil(HealthspanInsights.recentLeanMass(future, endingOn: calendar.startOfDay(for: now), now: now, calendar: calendar))
    }

    func testHistoricalWindowIncludesLateSamplesOnDaylightSavingDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        func date(_ day: Int, _ hour: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour)))
        }
        let end = try date(1, 0)
        let now = try date(2, 12)
        let last = ProfileBodyMeasurement(kilograms: 48, date: try date(1, 23), source: "Test")
        let next = ProfileBodyMeasurement(kilograms: 48, date: try date(2, 0), source: "Test")
        XCTAssertEqual(HealthspanInsights.recentLeanMass(last, endingOn: end, now: now, calendar: calendar), last)
        XCTAssertNil(HealthspanInsights.recentLeanMass(next, endingOn: end, now: now, calendar: calendar))
    }

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
