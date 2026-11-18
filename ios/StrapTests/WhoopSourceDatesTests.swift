import XCTest
@testable import Strap

final class WhoopSourceDatesTests: XCTestCase {
    private let cycle = WhoopCSVImport.SupplementalRecord(
        source: "physiological_cycles",
        fields: ["Cycle start time": "2026-10-01 23:00:00",
                 "Cycle timezone": "UTC+05:30",
                 "Wake onset": "2026-10-02 07:00:00"])

    private func journal(zone: String = "UTC+05:30") -> WhoopCSVImport.SupplementalRecord {
        .init(source: "journal_entries",
              fields: ["Cycle start time": "2026-10-01 23:00:00",
                       "Cycle timezone": zone, "Notes": "Original"])
    }

    func testWakeDayLinkedOnlyForUnambiguousMatchingCycle() {
        let unique = WhoopSourceDates(sources: ["physiological_cycles": [cycle]])
        XCTAssertEqual(unique.dateKey(for: journal()), "2026-10-02")
        XCTAssertEqual(unique.dateKey(for: journal(zone: "UTC-04:00")), "2026-10-01")
        var changed = cycle.fields
        changed["Wake onset"] = "2026-10-03 07:00:00"
        let ambiguous = WhoopSourceDates(sources: [
            "physiological_cycles": [cycle, .init(source: cycle.source, fields: changed)]])
        XCTAssertEqual(ambiguous.dateKey(for: journal()), "2026-10-01")
    }

    func testInvalidDayAndLegacyFormat() {
        let dates = WhoopSourceDates(sources: [:])
        let invalid = WhoopCSVImport.SupplementalRecord(
            source: "sleeps", fields: ["Wake onset": "2026-02-30 07:00:00"])
        XCTAssertNil(dates.dateKey(for: invalid))
        XCTAssertFalse(dates.includes(invalid, from: "2026-02-01", through: nil))
        XCTAssertTrue(dates.includes(invalid, from: nil, through: nil))
        let legacy = WhoopCSVImport.SupplementalRecord(
            source: "physiological_cycles", fields: ["Date": "10/02/2026"])
        XCTAssertEqual(dates.dateKey(for: legacy), "2026-10-02")
    }
}
