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
}

extension ManualActivityPreservationTests {
    func testLiveSessionDeleteAndFailedUpdateRetainOriginalAndIncomingMeasurement() throws {
        let suite = "LivePreserve-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ActivityStore(defaults: defaults, revisionDirectory: folder)
        let record = LiveActivityRecord(dateKey: "2026-10-02", startedUnix: 100, endedUnix: 200,
                                       meanHR: 100, maxHR: 120, beats: 10, hrv: .empty, zoneSeconds: [])
        XCTAssertTrue(store.saveLive(record))
        let bytes = try XCTUnwrap(defaults.data(forKey: "strap.live.sessions.v1"))
        XCTAssertTrue(store.deleteLive(id: record.id)); XCTAssertTrue(store.liveActivities().isEmpty)
        let liveFolder = folder.appendingPathComponent("live-sessions")
        let files = try FileManager.default.contentsOfDirectory(at: liveFolder, includingPropertiesForKeys: nil)
        XCTAssertTrue(try files.map { try Data(contentsOf: $0) }.contains(bytes))
        XCTAssertTrue(try store.restoreMissingLive(record))
        let restored = defaults.data(forKey: "strap.live.sessions.v1")
        XCTAssertFalse(try store.restoreMissingLive(record))
        XCTAssertEqual(defaults.data(forKey: "strap.live.sessions.v1"), restored)
        let bad = Data("preserve unreadable original".utf8)
        defaults.set(bad, forKey: "strap.live.sessions.v1")
        XCTAssertFalse(store.saveLive(record)); XCTAssertEqual(defaults.data(forKey: "strap.live.sessions.v1"), bad)
        let recovery = try XCTUnwrap(store.lastLiveRecoveryURL)
        XCTAssertEqual(try JSONDecoder().decode([LiveActivityRecord].self, from: Data(contentsOf: recovery)), [record])
        XCTAssertFalse(store.deleteLive(id: record.id)); XCTAssertEqual(defaults.data(forKey: "strap.live.sessions.v1"), bad)
    }
}
