import Foundation
import SQLite3
import XCTest
@testable import Strap

final class PortableBackupInspectionTests: XCTestCase {
    func testReadOnlySchemaAndOriginalBytes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE hrSample(ts INTEGER,bpm INTEGER); CREATE TABLE rrInterval(ts INTEGER,rrMs INTEGER); CREATE TABLE skinTempSample(ts INTEGER);", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_close(db), SQLITE_OK)
        let before = try Data(contentsOf: url)
        let report = try PortableBackupInspection.inspect(url)
        XCTAssertEqual(report.channels, ["hrSample", "rrInterval"])
        XCTAssertTrue(report.missing.contains("skinTempSample"))
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
}
