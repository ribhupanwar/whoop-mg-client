import XCTest
import ZIPFoundation
@testable import Strap

/// Synthetic records match the four uploaded CSV schemas/counts. No user's
/// health values, dates, notes or original ZIP are committed to the repository.
final class WhoopImportBatchTests: XCTestCase {
    private func fixture() -> [(String, Data)] {
        func data(_ header: String, _ count: Int, _ make: (Int) -> String) -> Data {
            Data(([header] + (1...count).map(make)).joined(separator: "\n").utf8)
        }
        let cycles = data("Cycle start time,Cycle end time,Cycle timezone,Recovery score %,Resting heart rate (bpm),Heart rate variability (ms),Day Strain,Energy burned (cal),Sleep onset,Wake onset,Sleep performance %,Asleep duration (min),Sleep need (min)", 18) { i in
            let day = String(format: "2026-10-%02d", i)
            return "\(day) 00:00:00,,UTC+05:30,70,60,\(i <= 16 ? "40" : ""),12.5,2100,\(day) 00:30:00,\(day) 07:30:00,85,420,480"
        }
        let sleeps = data("Cycle start time,Cycle timezone,Sleep onset,Wake onset,Asleep duration (min),Sleep performance %,Deep (SWS) duration (min),REM duration (min),Nap", 16) { i in
            let day = String(format: "2026-10-%02d", i)
            return "\(day) 00:00:00,UTC+05:30,\(day) 00:30:00,\(day) 07:30:00,420,85,80,90,false"
        }
        let workouts = data("Cycle start time,Cycle timezone,Workout start time,Workout end time,Activity name,Activity Strain,GPS enabled", 11) { i in
            let day = String(format: "2026-10-%02d", i)
            return "\(day) 00:00:00,UTC+05:30,\(day) 12:00:00,\(day) 12:30:00,Fixture run,6,false"
        }
        let journal = data("Cycle start time,Cycle timezone,Question text,Answered yes,Notes", 68) { i in
            "2026-10-01 00:00:00,UTC+05:30,Synthetic question \(i),true,Fixture only"
        }
        return [("physiological_cycles", cycles), ("sleeps", sleeps), ("workouts", workouts), ("journal_entries", journal)]
    }
    func testWholeZipImportsAllFourCategoriesAndRepeatShowsAlreadySaved() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let zip = root.appendingPathComponent("whoop.zip")
        do {
            let archive = try Archive(url: zip, accessMode: .create)
            for (category, data) in fixture() {
                let file = category + ".csv"
                try data.write(to: root.appendingPathComponent(file))
                try archive.addEntry(with: file, relativeTo: root)
            }
        }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WhoopBatch-" + UUID().uuidString))
        defer { defaults.removeObject(forKey: WhoopCSVImport.bundleKey) }
        let plan = try WhoopImportBatch.prepare(zip, defaults: defaults)
        XCTAssertEqual(plan.csvFiles, 4)
        XCTAssertEqual(plan.found, 113)
        XCTAssertEqual(plan.added, 113)
        XCTAssertEqual(plan.biometricRows.count, 16)
        XCTAssertEqual(plan.categories.map(\.found), [18, 16, 11, 68])
        try plan.commit(defaults: defaults)
        let repeatPlan = try WhoopImportBatch.prepare(zip, defaults: defaults)
        XCTAssertEqual(repeatPlan.found, 113)
        XCTAssertEqual(repeatPlan.added, 0)
        XCTAssertEqual(repeatPlan.existing, 113)
        XCTAssertEqual(repeatPlan.outsideRange, 0)
        XCTAssertTrue(repeatPlan.summary(updatedDays: 0).contains("Already imported"))
        XCTAssertEqual(try WhoopCSVImport.loadSources(defaults: defaults).values.reduce(0) { $0 + $1.count }, 113)
    }
    func testMalformedLastFileCannotPartiallyPersistEarlierFiles() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WhoopBatchFailure-" + UUID().uuidString))
        let previous = Data("[]".utf8)
        defaults.set(previous, forKey: "strap.whoop.import.sleeps.v1")
        defer { defaults.removeObject(forKey: "strap.whoop.import.sleeps.v1") }
        var inputs = fixture()
        inputs[3] = ("journal_entries", Data("Question text\n\"unterminated".utf8))
        XCTAssertThrowsError(try WhoopImportBatch.prepare(inputs, existing: WhoopCSVImport.loadSources(defaults: defaults)))
        XCTAssertNil(defaults.data(forKey: WhoopCSVImport.bundleKey))
        XCTAssertEqual(defaults.data(forKey: "strap.whoop.import.sleeps.v1"), previous)
    }
    func testRepeatedRowsAreDuplicatesNotOutsideDateRangeAndCRLFWorks() throws {
        let csv = Data("Cycle start time,HRV,RHR\r\n2026-10-01,40,60\r\n2026-10-01,40,60\r\n".utf8)
        let plan = try WhoopImportBatch.prepare([("physiological_cycles", csv)], existing: [:])
        XCTAssertEqual(plan.found, 2)
        XCTAssertEqual(plan.added, 1)
        XCTAssertEqual(plan.existing, 1)
        XCTAssertEqual(plan.outsideRange, 0)
        XCTAssertEqual(plan.biometricRows.count, 1)
    }
    func testDateFilterReportsExcludedRowsAndCommitKeepsConcurrentSourceArrival() throws {
        let plan = try WhoopImportBatch.prepare(fixture(), existing: [:], fromDate: "2026-10-02", throughDate: "2026-10-03")
        XCTAssertEqual(plan.sources["sleeps"]?.count, 2)
        XCTAssertEqual(plan.biometricRows.count, 2)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WhoopConcurrent-" + UUID().uuidString))
        defer { defaults.removeObject(forKey: WhoopCSVImport.bundleKey) }
        let other = WhoopCSVImport.SupplementalRecord(source: "journal_entries", fields: ["Question text": "Other import"])
        try WhoopCSVImport.saveSources(["journal_entries": [other]], defaults: defaults)
        try plan.commit(defaults: defaults)
        XCTAssertTrue(try WhoopCSVImport.loadSources(defaults: defaults)["journal_entries"]?.contains(other) == true)
    }
}

extension WhoopImportBatchTests {
    func testQuotedCRLFNotesArePreservedExactly() throws {
        let bytes = Data("Cycle start time,Question text,Notes\r\n2026-10-01,Fixture question,\"first\r\nsecond\"\r\n".utf8)
        let rows = try WhoopCSVImport.parseSupplemental(bytes, source: "journal_entries")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].fields["Notes"], "first\r\nsecond")
    }
}

extension WhoopImportBatchTests {
    func testCompactExportRoundTripsWithEmptyCategoriesAndQuotedJournal() throws {
        let day = DayMetrics(dateKey: "2026-10-01", state: "awake",
                             restingHR: 60, lnRMSSD: log(40), hrvWindowSeconds: 300,
                             sleepHours: 0, sleepStartUnix: nil, sleepEndUnix: nil,
                             strain: 2, steps: nil, restingHRWindowSeconds: 300)
        let entry = JournalEntry(dateKey: day.dateKey, answers: ["Fixture, question": true],
                                 notes: "Line 1\nLine 2: \"quoted\"")
        let files = StrapFourCSVExport.files(days: [day], detected: [], live: [], manual: [], journal: [entry])
        let url = try StrapFourCSVExport.write(files)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let archive = try Archive(url: url, accessMode: .read)
        XCTAssertEqual(Set(archive.map(\.path)), Set(WhoopCSVImport.sourceCategories.map { $0 + ".csv" }))
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "StrapCompact-" + UUID().uuidString))
        defer { defaults.removeObject(forKey: WhoopCSVImport.bundleKey) }
        let plan = try WhoopImportBatch.prepare(url, defaults: defaults)
        XCTAssertEqual(plan.csvFiles, 4)
        XCTAssertEqual(plan.biometricRows.count, 1)
        XCTAssertEqual(plan.biometricRows.first?.dateKey, day.dateKey)
        XCTAssertEqual(plan.sources["journal_entries"]?.first?.fields["Notes"], entry.notes)
        XCTAssertEqual(plan.sources["sleeps"]?.count, 0)
        XCTAssertEqual(plan.sources["workouts"]?.count, 0)
        try plan.commit(defaults: defaults)
        XCTAssertEqual(try WhoopImportBatch.prepare(url, defaults: defaults).added, 0)
    }

    func testCompactExportDoesNotLabelImportedBiometricsAsMeasured() throws {
        let imported = DayMetrics(dateKey: "2026-10-01", state: "imported",
                                  restingHR: 60, lnRMSSD: log(40), hrvWindowSeconds: 0,
                                  sleepHours: 0, sleepStartUnix: nil, sleepEndUnix: nil,
                                  strain: nil, steps: nil)
        let files = StrapFourCSVExport.files(days: [imported], detected: [], live: [], manual: [], journal: [])
        let inputs = files.map { (String($0.0.dropLast(4)), $0.1) }
        let plan = try WhoopImportBatch.prepare(inputs, existing: [:])
        XCTAssertEqual(plan.found, 0)
        XCTAssertTrue(plan.biometricRows.isEmpty)
    }
}
