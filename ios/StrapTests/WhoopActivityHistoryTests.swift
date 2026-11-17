import XCTest
@testable import Strap

final class WhoopActivityHistoryTests: XCTestCase {
    private var fields: [String: String] {
        ["Workout start time": "2026-10-02 07:30:00", "Workout end time": "2026-10-02 08:00:00",
         "Cycle timezone": "UTC+05:30", "Activity name": "Walk", "Activity Strain": "6.2", "Energy burned (cal)": "123"]
    }
    func testOfficialSourceProjectionRetainsIdentityAndOriginalClock() throws {
        let record = WhoopCSVImport.SupplementalRecord(source: "workouts", fields: fields)
        let workout = try XCTUnwrap(WhoopActivityHistory.make([record]).first)
        XCTAssertEqual(workout.original, record); XCTAssertEqual(workout.dateKey, "2026-10-02")
        XCTAssertEqual(workout.name, "Walk"); XCTAssertEqual(workout.strain, 6.2); XCTAssertEqual(workout.energyKcal, 123)
        XCTAssertEqual(try XCTUnwrap(workout.endUnix) - XCTUnwrap(workout.startUnix), 1800)
        XCTAssertEqual(WhoopActivityHistory.make([record]).first?.id, workout.id)
        var revision = fields; revision["Activity Strain"] = "7.1"
        XCTAssertNotEqual(WhoopActivityHistory.make([.init(source: "workouts", fields: revision)]).first?.id, workout.id)
    }
    func testMissingTimezoneOrInvalidMetricsNeverBecomeInventedMeasurements() throws {
        var row = fields; row.removeValue(forKey: "Cycle timezone")
        row["Activity Strain"] = "NaN"; row["Energy burned (cal)"] = "-3"
        let workout = try XCTUnwrap(WhoopActivityHistory.make([.init(source: "workouts", fields: row)]).first)
        XCTAssertNil(workout.startUnix); XCTAssertNil(workout.endUnix)
        XCTAssertNil(workout.strain); XCTAssertNil(workout.energyKcal)
        XCTAssertEqual(workout.original.fields, row)
        row["Workout start time"] = "missing"
        XCTAssertTrue(WhoopActivityHistory.make([.init(source: "workouts", fields: row)]).isEmpty)
    }
    func testReversedEndIsRetainedAsRawButNotAValidSessionInterval() throws {
        var row = fields; row["Workout end time"] = "2026-10-02 06:00:00"
        let workout = try XCTUnwrap(WhoopActivityHistory.make([.init(source: "workouts", fields: row)]).first)
        XCTAssertNil(workout.endUnix)
        XCTAssertEqual(workout.original.fields["Workout end time"], row["Workout end time"])
    }
}
