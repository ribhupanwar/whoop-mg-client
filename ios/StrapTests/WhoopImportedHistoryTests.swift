import XCTest
@testable import Strap

final class WhoopImportedHistoryTests: XCTestCase {
    private var source: WhoopCSVImport.SupplementalRecord {
        .init(source: "physiological_cycles", fields: ["Cycle start time": "2026-10-01 23:00:00",
            "Cycle timezone": "UTC+05:30", "Wake onset": "2026-10-02 07:30:00", "Sleep onset": "2026-10-01 23:30:00",
            "Recovery score %": "79", "Day Strain": "12.3", "Asleep duration (min)": "420", "Sleep performance %": "88",
            "Heart rate variability (ms)": "40", "Resting heart rate (bpm)": "60", "Deep (SWS) duration (min)": "90"])
    }
    func testOfficialValuesAppearOnWakeDateWithoutBaselineOrInventedStages() throws {
        let imported = WhoopImportedHistory.make(["physiological_cycles": [source]])
        let day = try XCTUnwrap(imported["2026-10-02"])
        XCTAssertNil(imported["2026-10-01"])
        XCTAssertEqual(day.recovery, 79)
        XCTAssertEqual(day.strain, 12.3)
        XCTAssertEqual(day.sleepHours, 7)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(WhoopImportedHistory.timestamp("2026-10-02 07:30:00", timezone: "UTC+05:30"))
        XCTAssertEqual(utc.component(.hour, from: Date(timeIntervalSince1970: Double(date))), 2)
        let points = MetricTimeline.make(days: [], live: [], manual: [], caloriesByDay: [:],
            ending: Date(timeIntervalSince1970: Double(date)), count: 2, sleepNeedHours: 8, imported: imported, calendar: utc)
        XCTAssertNil(points.first?.value(.recovery))
        XCTAssertEqual(points.last?.value(.recovery), 79)
        XCTAssertEqual(points.last?.value(.strain), 12.3)
        XCTAssertEqual(points.last?.value(.sleepPerformance), 88)
        XCTAssertTrue(points.last?.usesWHOOP(.recovery) == true)
    }
    func testLocalNightAndManualWindowAreNotReplacedByImportedTotals() throws {
        let imported = try XCTUnwrap(WhoopImportedHistory.make(["physiological_cycles": [source]])["2026-10-02"])
        let local = DayMetrics(dateKey: "2026-10-02", state: "sleep", restingHR: 58, lnRMSSD: log(50), hrvWindowSeconds: 600,
            sleepHours: 6, sleepStartUnix: 100, sleepEndUnix: 200, strain: 9, steps: 1000,
            sleepDurationReliable: true, sleepPerformancePct: 75)
        let display = imported.fillingDisplayGaps(in: local)
        XCTAssertEqual(display.sleepHours, 6)
        XCTAssertEqual(display.sleepStartUnix, 100)
        XCTAssertEqual(display.sleepPerformancePct, 75)
        XCTAssertEqual(display.strain, 9)
        XCTAssertEqual(display.restingHR, 58)
        let point = MetricDay(date: Date(), key: local.dateKey, recorded: local, recovery: 65, zones: nil, calories: nil, strength: nil, imported: imported)
        XCTAssertEqual(point.value(.recovery), 65)
        XCTAssertFalse(point.usesWHOOP(.recovery))
        XCTAssertEqual(point.value(.sleepPerformance), 75)
        XCTAssertEqual(local.sleepHours, 6)
    }
    func testNapDoesNotReplaceMainSleepAndMissingValuesStayMissing() {
        let nap = WhoopCSVImport.SupplementalRecord(source: "sleeps", fields: ["Wake onset": "2026-10-02 15:00:00", "Nap": "true", "Asleep duration (min)": "60"])
        XCTAssertTrue(WhoopImportedHistory.make(["sleeps": [nap]]).isEmpty)
        let partial = WhoopCSVImport.SupplementalRecord(source: "physiological_cycles", fields: ["Cycle start time": "2026-10-03 00:00:00", "Day Strain": "5"])
        let day = WhoopImportedHistory.make(["physiological_cycles": [partial]])["2026-10-03"]
        XCTAssertEqual(day?.strain, 5)
        XCTAssertNil(day?.recovery)
        XCTAssertNil(day?.sleepHours)
        XCTAssertNil(day?.onsetUnix)
    }
}

extension WhoopImportedHistoryTests {
    func testNormalizedAliasesAndMalformedWakeUseValidCycleDate() throws {
        let row = WhoopCSVImport.SupplementalRecord(source: "physiological_cycles", fields: [
            "wake_onset": "invalid", "cycle_start_time": "2026-10-02 23:00:00",
            "heart_rate_variability_rmssd_ms": "48", "resting_heart_rate_bpm": "61",
            "recovery_score_pct": "73", "day_strain": "8.1"])
        let day = try XCTUnwrap(WhoopImportedHistory.make(["physiological_cycles": [row]])["2026-10-02"])
        XCTAssertEqual(day.hrvMS, 48)
        XCTAssertEqual(day.restingHR, 61)
        XCTAssertEqual(day.recovery, 73)
        XCTAssertEqual(day.strain, 8.1)
    }

    func testNormalizedCollisionPrefersNonemptySourceValue() throws {
        let row = WhoopCSVImport.SupplementalRecord(source: "physiological_cycles", fields: [
            "Cycle start time": "2026-10-03", "Day Strain": "", "day_strain": "7"])
        let day = try XCTUnwrap(WhoopImportedHistory.make(["physiological_cycles": [row]])["2026-10-03"])
        XCTAssertEqual(day.strain, 7)
    }
}
