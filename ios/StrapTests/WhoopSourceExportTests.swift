import XCTest
@testable import Strap

final class WhoopSourceExportTests: XCTestCase {
    func testWakeDateJournalLinkAndWorkoutStartStayDistinct() {
        let cycle = WhoopCSVImport.SupplementalRecord(source: "physiological_cycles", fields: ["Cycle start time": "2026-10-01 23:00:00", "Cycle timezone": "UTC+05:30", "Wake onset": "2026-10-02 07:00:00"])
        let journal = WhoopCSVImport.SupplementalRecord(source: "journal_entries", fields: ["Cycle start time": "2026-10-01 23:00:00", "Cycle timezone": "UTC+05:30", "Question text": "Original question"])
        let workout = WhoopCSVImport.SupplementalRecord(source: "workouts", fields: ["Workout start time": "2026-10-01 22:00:00"])
        let sources = ["physiological_cycles": [cycle], "journal_entries": [journal], "workouts": [workout]]
        XCTAssertEqual(WhoopSourceExport.select(sources, from: "2026-10-02", through: "2026-10-02").records, [journal, cycle])
        XCTAssertEqual(WhoopSourceExport.select(sources, from: "2026-10-01", through: "2026-10-01").records, [workout])
    }
    func testUndatedRetainedOnlyInUnfilteredExportAndJSONPreservesOriginalFields() throws {
        let row = WhoopCSVImport.SupplementalRecord(source: "journal_entries", fields: ["Notes": "No date, original"])
        let sources = ["journal_entries": [row]]
        let filtered = WhoopSourceExport.select(sources, from: "2026-10-01", through: nil)
        XCTAssertEqual(filtered.undated, 1); XCTAssertTrue(filtered.records.isEmpty)
        let all = WhoopSourceExport.select(sources, from: nil, through: nil)
        XCTAssertEqual(try JSONDecoder().decode([WhoopCSVImport.SupplementalRecord].self, from: WhoopSourceExport.json(all.records)), [row])
    }
    func testCSVQuotesUnicodeCommasQuotesAndEmbeddedCRLF() throws {
        let row = WhoopCSVImport.SupplementalRecord(source: "journal_entries", fields: ["Notes": "हां, \"yes\"\r\nnext", "source": "original"])
        let csv = try XCTUnwrap(String(data: WhoopSourceExport.csv([row]), encoding: .utf8))
        let parsed = try WhoopCSVImport.parseSupplemental(Data(csv.utf8), source: "journal_entries")
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.fields["Notes"], row.fields["Notes"])
        XCTAssertEqual(parsed.first?.fields["source"], "original")
        XCTAssertEqual(parsed.first?.fields["STRAP export source category"], "journal_entries")
    }
}
