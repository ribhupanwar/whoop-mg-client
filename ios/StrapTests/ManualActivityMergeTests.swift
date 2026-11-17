import XCTest
@testable import Strap

final class ManualActivityMergeTests: XCTestCase {
    private func entry(_ name: String, minutes: Int = 10, day: String = "2026-10-02", kind: ActivityKind = .walk) -> ManualActivity {
        ManualActivity(dateKey: day, kind: kind, name: name, minutes: minutes, notes: "Original " + name)
    }
    func testExplicitMergePreservesOriginalsUnselectedRowsAndEncodedPreMergeCollection() throws {
        let suite = "Merge-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ActivityStore(defaults: defaults)
        let first = entry("One"), second = entry("Two", minutes: 20), untouched = entry("Other day", day: "2026-10-03")
        for row in [first, second, untouched] { store.save(row) }
        let before = try XCTUnwrap(defaults.data(forKey: "strap.activities.v1"))
        let merged = try store.mergeManual(ids: [first.id, second.id], name: "Combined", archiveDirectory: folder)
        XCTAssertEqual(merged.minutes, 30); XCTAssertEqual(merged.mergedFrom, [first, second])
        XCTAssertEqual(Set(store.manualActivities().map(\.id)), Set([untouched.id, merged.id]))
        let archive = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: archive), before)
        XCTAssertEqual(store.manualActivities().first(where: { $0.id == untouched.id }), untouched)
        try store.undoManualMerge(id: merged.id, archiveDirectory: folder)
        XCTAssertEqual(Set(store.manualActivities().map(\.id)), Set([first.id, second.id, untouched.id]))
        XCTAssertEqual(store.manualActivities().first(where: { $0.id == first.id }), first)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 2)
    }
    func testCrossTypeDateMissingIdentityAndFailedArchiveLeaveOriginalBytesIntact() throws {
        let suite = "MergeReject-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ActivityStore(defaults: defaults)
        let first = entry("One"), second = entry("Two"), other = entry("Run", kind: .run), later = entry("Later", day: "2026-10-03")
        for row in [first, second, other, later] { store.save(row) }
        let before = defaults.data(forKey: "strap.activities.v1")
        for ids in [Set([first.id]), Set([first.id, UUID()]), Set([first.id, other.id]), Set([first.id, later.id])] {
            XCTAssertThrowsError(try store.mergeManual(ids: ids, name: "Invalid", archiveDirectory: folder))
            XCTAssertEqual(defaults.data(forKey: "strap.activities.v1"), before)
        }
        try Data("not a directory".utf8).write(to: folder)
        XCTAssertThrowsError(try store.mergeManual(ids: [first.id, second.id], name: "Cannot archive", archiveDirectory: folder))
        XCTAssertEqual(defaults.data(forKey: "strap.activities.v1"), before)
    }
}
