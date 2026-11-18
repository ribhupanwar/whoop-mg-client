import XCTest
@testable import Strap

final class ManualActivityPreservationTests: XCTestCase {
    private func entry(_ name: String, id: UUID = UUID()) -> ManualActivity {
        ManualActivity(id: id, dateKey: "2026-10-02", kind: .walk, name: name, minutes: 20, notes: "Original self-report")
    }

    func testEditDeleteAndMissingOnlyRecoveryRetainEveryOriginalAndCurrentEdit() throws {
        let suite = "ManualPreserve-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ActivityStore(defaults: defaults, revisionDirectory: folder)
        let original = entry("Before")
        XCTAssertTrue(store.save(original))
        let originalBytes = try XCTUnwrap(defaults.data(forKey: "strap.activities.v1"))
        let edited = entry("After", id: original.id)
        XCTAssertTrue(store.save(edited))
        let editedBytes = try XCTUnwrap(defaults.data(forKey: "strap.activities.v1"))
        XCTAssertFalse(try store.restoreMissingManual(original), "Current edit must never be overwritten by an old revision")
        XCTAssertEqual(defaults.data(forKey: "strap.activities.v1"), editedBytes)
        XCTAssertTrue(store.deleteManual(id: original.id))
        XCTAssertTrue(store.manualActivities().isEmpty)
        let archived = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).map { try Data(contentsOf: $0) }
        XCTAssertTrue(archived.contains(originalBytes)); XCTAssertTrue(archived.contains(editedBytes))
        XCTAssertTrue(try store.restoreMissingManual(original)); XCTAssertEqual(store.manualActivities(), [original])
        let restored = defaults.data(forKey: "strap.activities.v1")
        XCTAssertFalse(try store.restoreMissingManual(edited)); XCTAssertEqual(defaults.data(forKey: "strap.activities.v1"), restored)
    }

    func testUndecodableAndWrongTypePreferencesAreEvidenceNotEmptyHistory() throws {
        let suite = "ManualBad-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ActivityStore(defaults: defaults)
        let bad = Data("unreadable retained bytes".utf8)
        defaults.set(bad, forKey: "strap.activities.v1")
        let row = entry("New")
        XCTAssertFalse(store.save(row)); XCTAssertFalse(store.deleteManual(id: row.id))
        XCTAssertThrowsError(try store.restoreMissingManual(row))
        XCTAssertEqual(defaults.data(forKey: "strap.activities.v1"), bad)
        defaults.set("original wrong type", forKey: "strap.activities.v1")
        XCTAssertFalse(store.save(row)); XCTAssertFalse(store.deleteManual(id: row.id))
        XCTAssertEqual(defaults.string(forKey: "strap.activities.v1"), "original wrong type")
    }

    func testFailedRevisionArchiveBlocksEditAndDeleteWithoutChangingHistory() throws {
        let suite = "ManualArchiveFail-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let blocked = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: blocked) }
        let original = entry("Keep")
        let bytes = try JSONEncoder().encode([original]); defaults.set(bytes, forKey: "strap.activities.v1")
        try Data("not a directory".utf8).write(to: blocked)
        let store = ActivityStore(defaults: defaults, revisionDirectory: blocked)
        XCTAssertFalse(store.save(entry("Edit", id: original.id)))
        XCTAssertFalse(store.deleteManual(id: original.id)); XCTAssertNotNil(store.lastManualWriteError)
        XCTAssertEqual(defaults.data(forKey: "strap.activities.v1"), bytes)
    }

    func testMergeRetainsOriginalsAndUndoRestoresThem() throws {
        let suite = "ManualMerge-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ActivityStore(defaults: defaults, revisionDirectory: folder)
        let a = entry("Morning walk"), b = entry("Evening walk")
        XCTAssertTrue(store.save(a)); XCTAssertTrue(store.save(b))
        let merged = try store.mergeManual(ids: [a.id, b.id], name: "Combined walk")
        XCTAssertEqual(merged.minutes, 40)
        XCTAssertEqual(merged.mergedFrom, [a, b])
        XCTAssertEqual(store.manualActivities(), [merged])
        try store.undoManualMerge(id: merged.id)
        XCTAssertEqual(Set(store.manualActivities().map(\.id)), [a.id, b.id])
    }
}
