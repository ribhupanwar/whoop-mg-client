import XCTest
@testable import Strap

final class HealthMonitorTests: XCTestCase {
    private let end = 1_800_000_000
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private var session: SleepSession {
        SleepSession.make(samples: [], period: SleepPeriod(startUnix: end - 3600, endUnix: end - 1,
            quietFraction: 1, meanHR: 60, wakeEvents: 0))
    }
    private func day(_ offset: Int, rhr: Double = 60, hrv: Double = 28, temp: Double = 34) -> DayMetrics {
        let wake = end + offset * 86400
        return DayMetrics(dateKey: JournalStore.dayKey(for: Date(timeIntervalSince1970: Double(wake - 1)), calendar: calendar),
            state: "sleep", restingHR: rhr, lnRMSSD: log(hrv), hrvWindowSeconds: 300,
            sleepHours: 1, sleepStartUnix: wake - 3600, sleepEndUnix: wake - 1, strain: nil, steps: nil,
            sleepDurationReliable: true, respiratoryRate: 16, restingHRWindowSeconds: 300,
            respiratoryWindows: 1, skinTemperatureC: temp, skinTemperatureSeconds: 600,
            skinTemperatureSource: NightTemperature.source, oxygenCandidatePct: 97)
    }
    func testNoGreenChecksWithoutPriorBaseline() {
        let report = HealthMonitor.make(days: [day(0)], session: session, calendar: calendar)
        XCTAssertEqual(report[.rhr].value, 60)
        XCTAssertEqual(report[.rhr].status, .calibrating)
        XCTAssertEqual(report.withinCount, 0)
        XCTAssertEqual(report[.oxygen].status, .candidate)
        XCTAssertNil(report[.temperature].value)
        XCTAssertEqual(report[.temperature].nightlyTemperatureCandidate, 34)
        XCTAssertFalse(report[.temperature].verifiedWithinRange)
    }
    func testOnlyEarlierDistinctQualifiedNightsCountTowardRange() throws {
        let prior = (-7 ... -1).map { day($0) }
        let report = HealthMonitor.make(days: prior + [day(0), day(1, rhr: 200)], session: session, calendar: calendar)
        XCTAssertEqual(report[.rhr].baselineDays, 7)
        XCTAssertEqual(report[.rhr].status, .withinRange)
        XCTAssertEqual(try XCTUnwrap(report[.hrv].value), 28, accuracy: 1e-8)
        XCTAssertEqual(report[.hrv].status, .withinRange)
        XCTAssertEqual(report[.respiration].status, .withinRange)
        XCTAssertFalse(report[.oxygen].verifiedWithinRange)
        XCTAssertFalse(report[.temperature].verifiedWithinRange)
        let duplicates = HealthMonitor.make(days: Array(repeating: day(-1), count: 7) + [day(0)], session: session, calendar: calendar)
        XCTAssertEqual(duplicates[.rhr].baselineDays, 1)
        XCTAssertEqual(duplicates.withinCount, 0)
    }
    func testDuplicatePriorNightUsesLatestCompletedIntervalRegardlessOfInputOrder() {
        let prior = (-7 ... -1).map { day($0) }
        let original = day(-1, rhr: 85)
        // A later saved revision for the same calendar day. DayMetrics has
        // immutable fields, so create the revision using its initializer.
        let revised = DayMetrics(
            dateKey: original.dateKey, state: original.state,
            restingHR: original.restingHR, lnRMSSD: original.lnRMSSD,
            hrvWindowSeconds: original.hrvWindowSeconds,
            sleepHours: original.sleepHours,
            sleepStartUnix: original.sleepStartUnix,
            sleepEndUnix: original.sleepEndUnix.map { $0 + 60 },
            strain: original.strain, steps: original.steps,
            sleepDurationReliable: original.sleepDurationReliable,
            respiratoryRate: original.respiratoryRate,
            restingHRWindowSeconds: original.restingHRWindowSeconds,
            respiratoryWindows: original.respiratoryWindows,
            skinTemperatureC: original.skinTemperatureC,
            skinTemperatureSeconds: original.skinTemperatureSeconds,
            skinTemperatureSource: original.skinTemperatureSource,
            oxygenCandidatePct: original.oxygenCandidatePct)
        let current = day(0, rhr: 60)
        let first = HealthMonitor.make(days: prior + [revised, current],
                                       session: session, calendar: calendar)
        let second = HealthMonitor.make(days: [revised] + prior + [current],
                                        session: session, calendar: calendar)
        XCTAssertEqual(first[.rhr].baselineDays, 7)
        XCTAssertEqual(first[.rhr].reference, second[.rhr].reference)
        XCTAssertEqual(first[.rhr].reference?.upperBound, 85)
    }
    func testOutOfRangeAndInsufficientQualityAreNotNormal() {
        let prior = (-7 ... -1).map { day($0) }
        let report = HealthMonitor.make(days: prior + [day(0, rhr: 76)], session: session, calendar: calendar)
        XCTAssertEqual(report[.rhr].status, .outsideRange)
        var insufficient = day(0)
        insufficient.restingHRWindowSeconds = 0
        let weakReport = HealthMonitor.make(days: prior + [insufficient], session: session, calendar: calendar)
        XCTAssertNil(weakReport[.rhr].value)
        XCTAssertEqual(weakReport[.rhr].status, .unavailable)
    }
    func testMonitorDirectionDoesNotChangeMeasuredStatusOrRangeCount() {
        let prior = (-7 ... -1).map { day($0, rhr: 63, hrv: 49) }
        let report = HealthMonitor.make(days: prior + [day(0, rhr: 62, hrv: 57)], session: session, calendar: calendar)
        XCTAssertEqual(report[.rhr].status, .outsideRange)
        XCTAssertEqual(report[.hrv].status, .outsideRange)
        XCTAssertEqual(report[.rhr].monitorStatusText, "BELOW PERSONAL RANGE")
        XCTAssertEqual(report[.hrv].monitorStatusText, "ABOVE PERSONAL RANGE")
        XCTAssertFalse(report[.rhr].monitorShowsWarning)
        XCTAssertFalse(report[.hrv].monitorShowsWarning)
        XCTAssertFalse(report[.rhr].verifiedWithinRange)
        XCTAssertFalse(report[.hrv].verifiedWithinRange)
        XCTAssertEqual(report.withinCount, 1)
        XCTAssertEqual(report[.oxygen].monitorStatusText, "UNVERIFIED ESTIMATE")
        XCTAssertFalse(report[.oxygen].verifiedWithinRange)
        XCTAssertNil(report[.oxygen].value)
        XCTAssertEqual(report[.temperature].monitorStatusText, "UNVERIFIED ESTIMATE")
        let reverse = HealthMonitor.make(days: prior + [day(0, rhr: 76, hrv: 23)], session: session, calendar: calendar)
        XCTAssertTrue(reverse[.rhr].monitorShowsWarning)
        XCTAssertTrue(reverse[.hrv].monitorShowsWarning)
        let short = HealthMonitor.make(days: Array(prior.dropFirst()) + [day(0, rhr: 62, hrv: 57)], session: session, calendar: calendar)
        XCTAssertEqual(short[.rhr].monitorStatusText, "BUILDING BASELINE")
        XCTAssertFalse(short[.rhr].isFavourableDirection)
    }
    func testTemperatureDeviationAndEmpiricalRangeUseMatchingRecordedSource() throws {
        let prior = (-7 ... -1).map { day($0, temp: 34) }
        let report = HealthMonitor.make(days: prior + [day(0, temp: 34.6)], session: session, calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(report[.temperature].value), 0.6, accuracy: 1e-8)
        XCTAssertEqual(report[.temperature].reference, 0...0)
        XCTAssertEqual(report[.temperature].status, .candidate)
        var unknownSource = day(-7)
        unknownSource.skinTemperatureSource = "unknown sensor"
        let missing = HealthMonitor.make(days: [unknownSource] + Array(prior.dropFirst()) + [day(0, temp: 34.6)],
                                         session: session, calendar: calendar)
        XCTAssertEqual(missing[.temperature].baselineDays, 6)
        XCTAssertEqual(missing[.temperature].nightlyTemperatureCandidate, 34.6)
        XCTAssertNil(missing[.temperature].value)
    }
    func testPreviouslyCommittedVitalsRemainAvailableUntilBoundsChange() {
        let prior = (-7 ... -1).map { day($0) }
        let old = day(0)
        let changed = session.applyingSavedBounds([String(session.sourceStartUnix): [session.startUnix + 30, session.endUnix]])
        XCTAssertEqual(HealthMonitor.make(days: prior + [old], session: changed, calendar: calendar).availableCount, 0)
        let report = HealthMonitor.make(days: prior + [old], session: session, calendar: calendar)
        XCTAssertEqual(report.availableCount, 4) // Unvalidated oxygen is not a measured vital.
        XCTAssertNil(report[.oxygen].value)
        XCTAssertEqual(report[.oxygen].nightlyOxygenCandidate, 97)
        XCTAssertEqual(report[.oxygen].status, .candidate)
        XCTAssertNil(report[.oxygen].reference)
        XCTAssertFalse(report[.oxygen].verifiedWithinRange)
        XCTAssertNil(HealthMonitor.make(days: prior + [old], session: changed, calendar: calendar)[.oxygen].nightlyOxygenCandidate)
    }
    func testLegacyDayDecodesWithoutInventingTemperatureBaseline() throws {
        let original = day(0)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        for key in ["skinTemperatureC", "skinTemperatureSeconds", "skinTemperatureSource", "restingHRWindowSeconds", "respiratoryWindows"] {
            json.removeValue(forKey: key)
        }
        let decoded = try JSONDecoder().decode(DayMetrics.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.restingHR, original.restingHR)
        XCTAssertEqual(decoded.lnRMSSD, original.lnRMSSD)
        XCTAssertNil(decoded.skinTemperatureC)
    }
}
