import XCTest
@testable import Strap

final class WhoopSourceDatesTests: XCTestCase {
    private let cycle = WhoopCSVImport.SupplementalRecord(source: "physiological_cycles", fields: [
        "Cycle start time": "2026-10-01 23:00:00", "Cycle timezone": "UTC+05:30", "Wake onset": "2026-10-02 07:00:00"])
    private func journal(zone: String = "UTC+05:30") -> WhoopCSVImport.SupplementalRecord {
        .init(source: "journal_entries", fields: ["Cycle start time": "2026-10-01 23:00:00", "Cycle timezone": zone, "Notes": "Original"])
    }
    func testWholeBatchRangeUsesWakeForCycleSleepJournalAndOwnStartForWorkout() throws {
        let inputs: [(String, Data)] = [
            ("journal_entries", Data("Cycle start time,Cycle timezone,Notes\n2026-10-01 23:00:00,UTC+05:30,Original".utf8)),
            ("sleeps", Data("Cycle start time,Cycle timezone,Sleep onset,Asleep duration (min),Nap\n2026-10-01 23:00:00,UTC+05:30,2026-10-01 23:30:00,420,false".utf8)),
            ("workouts", Data("Workout start time,Activity name\n2026-10-01 23:30:00,Original workout".utf8)),
            ("physiological_cycles", Data("Cycle start time,Cycle timezone,Wake onset,Heart rate variability (ms),Resting heart rate (bpm)\n2026-10-01 23:00:00,UTC+05:30,2026-10-02 07:00:00,40,60".utf8))]
        let plan = try WhoopImportBatch.prepare(inputs, existing: [:], fromDate: "2026-10-02", throughDate: "2026-10-02")
        XCTAssertEqual(plan.found, 4); XCTAssertEqual(plan.added, 3); XCTAssertEqual(plan.outsideRange, 1)
        XCTAssertEqual(plan.biometricRows.first?.dateKey, "2026-10-02")
        XCTAssertEqual(plan.sources["journal_entries"]?.first, journal())
        XCTAssertEqual(plan.sources["sleeps"]?.first?.fields["Sleep onset"], "2026-10-01 23:30:00")
        let projected = WhoopImportedHistory.make(plan.sources)
        XCTAssertNil(projected["2026-10-01"]); XCTAssertEqual(projected["2026-10-02"]?.sleepHours, 7)
        let exported = WhoopSourceExport.select(plan.sources, from: "2026-10-02", through: "2026-10-02")
        XCTAssertEqual(exported.records.count, 3)
    }
    func testJournalOnlyIncrementUsesExistingCycleAndNeverChangesIt() throws {
        let existing = ["physiological_cycles": [cycle]]
        let csv = Data("Cycle start time,Cycle timezone,Notes\n2026-10-01 23:00:00,UTC+05:30,Original".utf8)
        let plan = try WhoopImportBatch.prepare([("journal_entries", csv)], existing: existing, fromDate: "2026-10-02", throughDate: "2026-10-02")
        XCTAssertEqual(plan.added, 1); XCTAssertEqual(plan.sources["physiological_cycles"], [cycle])
        XCTAssertEqual(plan.sources["journal_entries"], [journal()])
    }
    func testAmbiguousCycleRevisionsAndDifferentTimezoneNeverGuessJournalWake() {
        var changed = cycle.fields; changed["Wake onset"] = "2026-10-03 07:00:00"
        let dates = WhoopSourceDates(sources: ["physiological_cycles": [cycle, .init(source: cycle.source, fields: changed)]])
        XCTAssertEqual(dates.dateKey(for: journal()), "2026-10-01")
        let unique = WhoopSourceDates(sources: ["physiological_cycles": [cycle]])
        XCTAssertEqual(unique.dateKey(for: journal(zone: "UTC-04:00")), "2026-10-01")
        XCTAssertEqual(unique.dateKey(for: journal()), "2026-10-02")
    }
    func testUndatedAndInvalidDaysExcludedOnlyWhenFilteredAndLegacyDateFormatsKept() {
        let dates = WhoopSourceDates(sources: [:])
        let missing = WhoopCSVImport.SupplementalRecord(source: "sleeps", fields: ["Wake onset": "2026-02-30 07:00:00"])
        XCTAssertNil(dates.dateKey(for: missing))
        XCTAssertFalse(dates.includes(missing, from: "2026-02-01", through: nil))
        XCTAssertTrue(dates.includes(missing, from: nil, through: nil))
        let legacy = WhoopCSVImport.SupplementalRecord(source: "physiological_cycles", fields: ["Date": "10/02/2026"])
        XCTAssertEqual(dates.dateKey(for: legacy), "2026-10-02")
        XCTAssertTrue(WhoopCSVImport.inRange(legacy, fromDate: "2026-10-02", throughDate: "2026-10-02"))
    }
}
