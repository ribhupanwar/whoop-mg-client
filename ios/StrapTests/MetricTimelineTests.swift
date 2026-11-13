import XCTest
@testable import Strap

final class MetricTimelineTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }
    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: 12))!
    }
    private func day(_ number: Int, steps: Int? = 0, zones: [Int]? = nil) -> DayMetrics {
        DayMetrics(dateKey: JournalStore.dayKey(for: date(number), calendar: calendar), state: "sleep",
                   restingHR: 60, lnRMSSD: log(44), hrvWindowSeconds: 300, sleepHours: 8,
                   sleepStartUnix: nil, sleepEndUnix: nil, strain: 4.7, steps: steps,
                   sleepDurationReliable: true, zoneSeconds: zones)
    }
    private func timeline(_ days: [DayMetrics], live: [LiveActivityRecord] = [], count: Int = 7) -> [MetricDay] {
        MetricTimeline.make(days: days, live: live, manual: [], caloriesByDay: [:], ending: date(10),
                            count: count, sleepNeedHours: 8, calendar: calendar)
    }
    func testSevenCalendarSlotsSurviveDSTAndMissingDays() throws {
        let points = timeline([day(4), day(10)])
        XCTAssertEqual(points.count, 7)
        XCTAssertEqual(points.map(\.key), (4...10).map { JournalStore.dayKey(for: date($0), calendar: calendar) })
        XCTAssertEqual(points[0].value(.steps), 0)
        XCTAssertNil(points[1].value(.steps))
        XCTAssertEqual(points.last?.value(.strain), 4.7)
        XCTAssertEqual(points[5].date.timeIntervalSince(points[4].date), 23 * 3600)
    }
    func testDuplicateDaysCannotCreateARecoveryBaseline() {
        let prior = (4...9).map { day($0) }
        XCTAssertNil(timeline(prior + [day(9), day(9), day(10)]).last?.recovery)
    }
    func testAwakeStressBaselineCannotUseOvernightValues() {
        var days = (1...7).map { day($0) }
        XCTAssertNil(DailyAnalysis.awakeBaseline(from: days))
        for index in days.indices {
            days[index].awakeLnRMSSD = log(30 + Double(index))
            days[index].awakeRestingHR = 65 + Double(index)
        }
        XCTAssertEqual(DailyAnalysis.awakeBaseline(from: days)?.days, 7)
    }
    func testCurrentAndFutureDaysCannotSupplyRecoveryBaseline() {
        let sixPrior = (4...9).map { day($0) }
        XCTAssertNil(timeline(sixPrior + [day(10), day(11)]).last?.recovery)
        XCTAssertNotNil(timeline([day(3)] + sixPrior + [day(10)]).last?.recovery)
        XCTAssertEqual(timeline([day(3)] + sixPrior + [day(10)]).last?.recovery,
                       timeline([day(3)] + sixPrior + [day(10), day(11)]).last?.recovery)
    }
    func testRawZoneCoverageIsNotAddedToOverlappingLiveCoverage() {
        let source = day(10, zones: [60, 120, 0, 0, 0])
        let record = LiveActivityRecord(dateKey: source.dateKey, startedUnix: 100, endedUnix: 300,
                                       meanHR: 100, maxHR: 120, beats: 200, hrv: .empty,
                                       zoneSeconds: [200, 0, 0, 0, 0])
        XCTAssertEqual(timeline([source], live: [record]).last?.value(.zonesLow), 3)
        XCTAssertEqual(timeline([], live: [record]).last?.value(.zonesLow), 200.0 / 60)
        XCTAssertNil(timeline([]).last?.value(.zonesLow))
    }
    func testZeroAndUnknownZonesAreDistinct() {
        XCTAssertEqual(timeline([day(10, zones: [0, 0, 0, 0, 0])]).last?.value(.zonesHigh), 0)
        XCTAssertNil(timeline([day(10)]).last?.value(.zonesHigh))
    }
    func testLegacyDayHasNoInventedRespirationOrPerformance() throws {
        let encoded = try JSONEncoder().encode(day(10))
        let decoded = try JSONDecoder().decode(DayMetrics.self, from: encoded)
        XCTAssertNil(decoded.respiratoryRate)
        XCTAssertNil(decoded.sleepPerformancePct)
        XCTAssertNil(decoded.zoneSeconds)
        XCTAssertNil(timeline([decoded]).last?.value(.respiration))
        XCTAssertNil(timeline([decoded]).last?.value(.sleepPerformance))
    }
    func testComparisonExcludesTheCurrentObservation() {
        var prior = day(9)
        prior = DayMetrics(dateKey: prior.dateKey, state: "sleep", restingHR: 60, lnRMSSD: log(44),
                           hrvWindowSeconds: 300, sleepHours: 8, sleepStartUnix: nil, sleepEndUnix: nil,
                           strain: 2, steps: 0)
        let points = timeline([prior, day(10)])
        XCTAssertEqual(MetricTimeline.comparison(.strain, before: day(10).dateKey, in: points), 2)
    }
}
