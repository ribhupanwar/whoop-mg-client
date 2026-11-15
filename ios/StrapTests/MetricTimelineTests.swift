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
    func testDayWithoutStrengthActivityDoesNotInventZeroStrengthMinutes() {
        let points = timeline([day(10)])
        XCTAssertNil(points.last?.value(.strength),
                     "No logged strength activity is missing data, not a measured zero")
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
    func testComparisonUsesLastThirtyValidObservationsNotCalendarSlots() {
        let points = (0..<35).map { index in
            MetricDay(date: date(10), key: String(format: "%03d", index), recorded: nil,
                      recovery: nil, zones: nil, calories: index == 0 ? 250 : nil, strength: nil)
        }
        XCTAssertEqual(MetricTimeline.comparison(.calories, before: "035", in: points), 250,
                       "Missing recent days must not hide an older measured observation")
    }

    func testComparisonIsIndependentOfInputOrder() {
        let points = (0..<31).map { index in
            MetricDay(date: date(10), key: String(format: "%03d", index), recorded: nil,
                      recovery: nil, zones: nil, calories: index == 0 ? 1000 : 100, strength: nil)
        }
        XCTAssertEqual(MetricTimeline.comparison(.calories, before: "031", in: points), 100)
        XCTAssertEqual(MetricTimeline.comparison(.calories, before: "031", in: points.reversed()), 100,
                       "The most recent 30 valid days must not depend on caller ordering")
    }

    func testWeeklyDurationSumsObservedMinutesWithoutExtrapolatingMissingDays() {
        XCTAssertEqual(MetricTimeline.averageWeeklyDuration([60], calendarDayCount: 7), 60)
        XCTAssertEqual(MetricTimeline.averageWeeklyDuration([60, 30], calendarDayCount: 7), 90)
        XCTAssertEqual(MetricTimeline.averageWeeklyDuration([60], calendarDayCount: 30)!, 14, accuracy: 0.01)
        XCTAssertNil(MetricTimeline.averageWeeklyDuration([60], calendarDayCount: 0))
    }

    func testIsolatedLineReadingsRemainVisibleAcrossMissingDataGaps() {
        XCTAssertEqual(MetricTimeline.isolatedLineIndices([nil, 45, nil]), [1])
        XCTAssertEqual(MetricTimeline.isolatedLineIndices([nil, 45, 47, nil]), [])
        XCTAssertEqual(MetricTimeline.isolatedLineIndices([43, nil, 45]), [0, 2])
    }

    func testInvalidHeartRateInputsDoNotProduceFiniteLookingStrainOrVO2() {
        XCTAssertNil(Hrv.hrReserveRatio(.nan, resting: 60, maximum: 190))
        XCTAssertNil(Hrv.hrReserveRatio(120, resting: 60, maximum: .infinity))
        XCTAssertNil(Hrv.hrReserveRatio(120, resting: .nan, maximum: 190))
        XCTAssertNil(Hrv.strainScore(.infinity))
        XCTAssertNil(Hrv.strainScore(.nan))
        XCTAssertNil(Hrv.vo2Max(maxHR: .infinity, restingHR: 60))
        XCTAssertNil(Hrv.vo2Max(maxHR: 190, restingHR: .nan))
        XCTAssertNotNil(Hrv.hrReserveRatio(120, resting: 60, maximum: 190))
        XCTAssertNotNil(Hrv.strainScore(50))
        XCTAssertNotNil(Hrv.vo2Max(maxHR: 190, restingHR: 60))
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

extension MetricTimelineTests {
    func testDurationBucketsRetainMissingAndZeroWeeks() throws {
        let points = timeline([day(10, zones: [0, 0, 0, 0, 0])], count: 14)
        let buckets = MetricTimeline.durationBuckets(points, metric: .zonesLow)
        XCTAssertEqual(buckets.count, 2)
        XCTAssertNil(buckets[0].minutes)
        XCTAssertNil(buckets[0].zoneSeconds)
        XCTAssertEqual(buckets[1].minutes, 0)
        XCTAssertEqual(buckets[1].recordedDays, 1)
    }
    func testDurationBucketsAggregateZonesWithoutLosingPartialWeek() throws {
        let points = timeline([day(3, zones: [60, 0, 0, 0, 0]), day(10, zones: [60, 120, 180, 240, 300])], count: 8)
        let buckets = MetricTimeline.durationBuckets(points, metric: .zonesLow)
        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].minutes, 1)
        XCTAssertEqual(buckets[1].minutes, 6)
        XCTAssertEqual(buckets[1].zoneSeconds, [60, 120, 180, 240, 300])
        XCTAssertEqual(MetricTimeline.durationBuckets(points, metric: .zonesHigh).last?.minutes, 9)
        XCTAssertTrue(MetricTimeline.durationBuckets(points, metric: .hrv).isEmpty)
    }
}
