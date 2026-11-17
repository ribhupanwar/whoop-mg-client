import XCTest
@testable import Strap

final class WhoopImportTests: XCTestCase {
    func testQuotedHeaderAndSevenDayBaselineInputs() throws {
        let csv = """
        "Cycle start","Heart Rate Variability (RMSSD)","Resting Heart Rate (bpm)"
        2026-11-01T04:00:00Z,58,54
        2026-11-02T04:00:00Z,61,55
        2026-11-03T04:00:00Z,57,56
        2026-11-04T04:00:00Z,63,53
        2026-11-05T04:00:00Z,59,55
        2026-11-06T04:00:00Z,62,54
        2026-11-07T04:00:00Z,60,56
        """
        let rows = try WhoopCSVImport.parse(Data(csv.utf8))
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows.first?.dateKey, "2026-11-01")
        XCTAssertEqual(rows.last?.hrvMS, 60)
        let baseline = Baseline.fromDaily(
            lnRMSSD: rows.map { log($0.hrvMS) },
            rhr: rows.map { $0.restingHR }
        )
        XCTAssertEqual(baseline?.days, 7)
    }

    func testWhoopCycleStartTimeColumn() throws {
        let csv = """
        Cycle start time,Heart rate variability (ms),Resting heart rate (bpm)
        2026-11-01T04:00:00Z,64,52
        """
        let rows = try WhoopCSVImport.parse(Data(csv.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].dateKey, "2026-11-01")
        XCTAssertEqual(rows[0].hrvMS, 64)
    }

    func testRejectsInvalidOrMissingMetrics() throws {
        let csv = """
        Date,HRV,RHR
        2026-11-01,70,55
        2026-11-02,0,55
        2026-11-03,65,300
        """
        let rows = try WhoopCSVImport.parse(Data(csv.utf8))
        XCTAssertEqual(rows.count, 1)
    }

    func testMissingColumnsFailsInsteadOfInventingValues() {
        XCTAssertThrowsError(try WhoopCSVImport.parse(Data("Date,Recovery\n2026-11-01,80".utf8)))
    }
}

extension WhoopImportTests {
    func testSupplementalImportsAreAdditiveIdempotentAndKeepSourceRevisions() throws {
        let first = WhoopCSVImport.SupplementalRecord(source: "sleeps", fields: ["Sleep onset": "2026-11-16 23:28:00", "Nap": "false", "REM duration (min)": "113"])
        let second = WhoopCSVImport.SupplementalRecord(source: "sleeps", fields: ["Sleep onset": "2026-11-17 23:28:00", "Nap": "false"])
        let initial = try WhoopCSVImport.mergeSupplemental([first], existing: nil)
        let repeated = try WhoopCSVImport.mergeSupplemental([first, second], existing: initial.data)
        XCTAssertEqual(repeated.count, 1)
        let records = try JSONDecoder().decode([WhoopCSVImport.SupplementalRecord].self, from: repeated.data)
        XCTAssertEqual(records, [first, second])
        XCTAssertEqual(try WhoopCSVImport.mergeSupplemental([second, first], existing: repeated.data).count, 0)
        XCTAssertThrowsError(try WhoopCSVImport.mergeSupplemental([first], existing: Data("incompatible original".utf8)))
    }

    func testSupplementalDateRangeKeepsExactSourceTimestamp() throws {
        let row = WhoopCSVImport.SupplementalRecord(source: "sleeps", fields: ["Sleep onset": "2026-11-16 23:28:00", "Cycle timezone": "UTC+05:30"])
        XCTAssertEqual(try WhoopCSVImport.mergeSupplemental([row], existing: nil, fromDate: "2026-11-17").count, 0)
        let accepted = try WhoopCSVImport.mergeSupplemental([row], existing: nil, fromDate: "2026-11-16", throughDate: "2026-11-16")
        XCTAssertEqual(accepted.count, 1)
        XCTAssertEqual(try JSONDecoder().decode([WhoopCSVImport.SupplementalRecord].self, from: accepted.data).first, row)
    }
}

extension WhoopImportTests {
    func testCycleUsesWakeDateWhenExportProvidesItAndRejectsUnterminatedQuotes() throws {
        let csv = "Cycle start time,Wake onset,Heart rate variability (ms),Resting heart rate (bpm)\n2026-11-16 23:28:00,2026-11-17 07:32:00,28,76"
        XCTAssertEqual(try WhoopCSVImport.parse(Data(csv.utf8)).first?.dateKey, "2026-11-17")
        XCTAssertThrowsError(try WhoopCSVImport.parse(Data("Date,HRV,RHR\n\"2026-11-17,28,76".utf8)))
    }
}
