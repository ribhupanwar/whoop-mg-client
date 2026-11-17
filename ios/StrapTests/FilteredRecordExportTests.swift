import Foundation
import SQLite3
import XCTest
@testable import Strap

final class FilteredRecordExportTests: XCTestCase {
    func testStreamingBothSQLiteSourcesAndDayOnlyRecordsPreservesOriginalJSONAndBoundaries() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = folder.appendingPathComponent("history.sqlite")
        var db: OpaquePointer?; XCTAssertEqual(sqlite3_open(database.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = "CREATE TABLE history_sample(unix INTEGER PRIMARY KEY,payload BLOB); CREATE TABLE live_rr_record(source_id TEXT PRIMARY KEY,unix INTEGER,payload BLOB); INSERT INTO history_sample VALUES(100,'{\"futureField\":18446744073709551615}'); INSERT INTO history_sample VALUES(200,'{\"outside\":true}'); INSERT INTO live_rr_record VALUES('original-rr',150,'{\"original\":\"RR\"}');"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        let before = try Data(contentsOf: database)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let local = try FilteredRecordExport.Record.make(["notes": "हां, \"yes\"\r\nline"], source: "local_journal", id: "day", dateKey: "1970-01-01")
        let undated = try FilteredRecordExport.Record.make(["original": "unknown date"], source: "local", id: "undated")
        for asCSV in [false, true] {
            let result = try FilteredRecordExport.write([local, undated], database: database,
                from: Date(timeIntervalSince1970: 100), until: Date(timeIntervalSince1970: 200), calendar: calendar, asCSV: asCSV, destination: folder)
            XCTAssertEqual(result.count, 3); XCTAssertEqual(result.undated, 1)
            let bytes = try Data(contentsOf: result.url)
            let string = try XCTUnwrap(String(data: bytes, encoding: .utf8))
            XCTAssertTrue(string.contains("18446744073709551615"), "Original numeric representation must not be rewritten")
            if !asCSV {
                let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                let records = try XCTUnwrap(root["records"] as? [[String: Any]])
                XCTAssertEqual(records.count, 3)
                XCTAssertEqual(Set(records.compactMap { $0["source"] as? String }), Set(["local_journal", "history_sample", "live_rr_record"]))
            } else {
                let records = try WhoopCSVImport.parseSupplemental(bytes, source: "journal_entries")
                XCTAssertEqual(records.count, 3)
                XCTAssertEqual(records.first?.fields["original_json"], String(data: local.original, encoding: .utf8))
            }
        }
        XCTAssertEqual(try Data(contentsOf: database), before, "Read-only export must not modify the source database")
    }
    func testInvalidPayloadLeavesNoPartialReportAndNeverChangesOriginal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let invalid = FilteredRecordExport.Record(source: "original", id: "bad", unix: 150, dateKey: nil, original: Data("broken".utf8))
        XCTAssertThrowsError(try FilteredRecordExport.write([invalid], database: nil,
            from: Date(timeIntervalSince1970: 100), until: Date(timeIntervalSince1970: 200), calendar: .current, asCSV: false, destination: folder))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
}
