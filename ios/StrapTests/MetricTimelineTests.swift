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
    func testLiveZonesOutsideKnownRawCoverageRemainVisible() {
        var source = day(10, zones: [60, 0, 0, 0, 0])
        source.zoneCoverageStartUnix = 100
        source.zoneCoverageEndUnix = 200
        func record(_ start: Int, _ end: Int) -> LiveActivityRecord {
            LiveActivityRecord(dateKey: source.dateKey, startedUnix: start, endedUnix: end,
                meanHR: 140, maxHR: 160, beats: 200, hrv: .empty, zoneSeconds: [0, 120, 0, 0, 0])
        }
        XCTAssertEqual(timeline([source], live: [record(300, 420)]).last?.value(.zonesLow), 3)
        XCTAssertEqual(timeline([source], live: [record(150, 270)]).last?.value(.zonesLow), 1)
        XCTAssertEqual(timeline([source], live: [record(100, 200)]).last?.value(.zonesLow), 1)
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

extension MetricTimelineTests {
    func testVO2HistoryRequiresMaxHRAndRecordedOvernightRestingHR() throws {
        let record = day(10)
        XCTAssertNil(timeline([record]).last?.value(.vo2))
        let points = MetricTimeline.make(days: [record], live: [], manual: [], caloriesByDay: [:],
            ending: date(10), count: 7, sleepNeedHours: 8, maxHR: 180, calendar: calendar)
        XCTAssertNil(points[0].value(.vo2))
        XCTAssertEqual(try XCTUnwrap(points.last?.value(.vo2)), 15.3 * 180 / 60, accuracy: 0.001)
    }
}

extension MetricTimelineTests {
    func testLongRangeBaselineMatchesChronologicalReferenceWithUnsortedInput() throws {
        let days = (1...10).map { day($0) }
        let points = MetricTimeline.make(days: Array(days.reversed()), live: [], manual: [], caloriesByDay: [:],
            ending: date(10), count: 180, sleepNeedHours: 8, calendar: calendar)
        XCTAssertEqual(points.count, 180)
        for point in points {
            let prior = days.filter { $0.dateKey < point.key }.sorted { $0.dateKey < $1.dateKey }
            let record = days.first { $0.dateKey == point.key }
            let expected = Recovery.score(lnRMSSD: record?.lnRMSSD, rhr: record?.restingHR,
                sleepHours: record?.reliableSleepHours, sleepNeedHours: 8,
                baseline: DailyAnalysis.baseline(from: Array(prior.suffix(DailyAnalysis.rollingBaselineDays)))).score
            XCTAssertEqual(point.recovery, expected)
        }
    }

    func testRollingBaselineDaysIsCanonical28Days() {
        // Verified from WHOOP GetRestingHeartRateBaselineRequest (0x1099623a0)
        XCTAssertEqual(DailyAnalysis.rollingBaselineDays, 28)
    }
}

extension MetricTimelineTests {
    func testRecoveryUsesLatest28EligibleUniquePriorDays() throws {
        let target = date(40)
        let samples = (1...39).map { index -> DayMetrics in
            if index.isMultiple(of: 4) {
                return DayMetrics(dateKey: day(index).dateKey, state: "awake",
                                  restingHR: nil, lnRMSSD: nil, hrvWindowSeconds: 0, sleepHours: 0,
                                  sleepStartUnix: nil, sleepEndUnix: nil, strain: nil, steps: nil)
            }
            return day(index)
        }
        let history = Array(samples.reversed()) + [day(39), day(40), day(41)]
        let result = DatedRecovery.evaluate(day: day(40), priorDays: history, date: target,
                                             sleepNeedHours: 8, calendar: calendar)
        let legacy = DatedRecovery.replayLegacyHome(day: day(40), priorDays: samples,
            dateKey: day(40).dateKey, sleepNeedHours: 8)
        XCTAssertLessThan(legacy.baselineDays.count, result.baselineDays.count)
        let expected = samples.filter { $0.restingHR != nil }.suffix(28).map(\.dateKey)
        XCTAssertEqual(result.baselineDays.map(\.dateKey), expected)
        let timeline = MetricTimeline.make(days: history, live: [], manual: [], caloriesByDay: [:],
                                           ending: target, count: 1, sleepNeedHours: 8, calendar: calendar)
        XCTAssertEqual(timeline.first?.recovery, result.result.score)
    }

    func testSameNightMeasurementsRespondToBaselineAndSleepChanges() throws {
        let history = (1...7).map { day($0) }
        let changed = history.enumerated().map { index, row in
            DayMetrics(dateKey: row.dateKey, state: "sleep", restingHR: 64 + Double(index),
                       lnRMSSD: log(33 + Double(index)), hrvWindowSeconds: 300, sleepHours: 8,
                       sleepStartUnix: nil, sleepEndUnix: nil, strain: nil, steps: nil)
        }
        let night = day(10)
        func evaluate(_ target: DayMetrics, _ days: [DayMetrics]) -> DatedRecovery {
            DatedRecovery.evaluate(day: target, priorDays: days, date: date(10),
                                  sleepNeedHours: 8, calendar: calendar)
        }
        let a = evaluate(night, history)
        let b = evaluate(night, changed)
        XCTAssertNotEqual(a.result.score, b.result.score)
        let breakdown = try XCTUnwrap(RecoveryDiagnostics.Breakdown(assessment: b))
        XCTAssertEqual(Stats.rounded(breakdown.unroundedScore, 1), b.result.score)
        let revised = DayMetrics(dateKey: night.dateKey, state: night.state, restingHR: night.restingHR,
                                 lnRMSSD: night.lnRMSSD, hrvWindowSeconds: night.hrvWindowSeconds, sleepHours: 6,
                                 sleepStartUnix: nil, sleepEndUnix: nil, strain: nil, steps: nil,
                                 sleepDurationReliable: true)
        let reloaded = try JSONDecoder().decode(DayMetrics.self, from: JSONEncoder().encode(revised))
        XCTAssertNotEqual(evaluate(reloaded, changed).result.score, b.result.score)
        XCTAssertNil(evaluate(night, Array(changed.prefix(6))).result.score)
    }
}
