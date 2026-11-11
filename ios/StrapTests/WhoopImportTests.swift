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
