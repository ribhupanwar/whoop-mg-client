import XCTest
import SQLite3
@testable import Strap

final class LiveRRArchiveTests: XCTestCase {
    private func record(_ unix: Int, id: String? = nil) -> LiveRRRecord {
        LiveRRRecord(id: id ?? "fixture-\(unix)", source: "synthetic-test", receivedAtUnix: Double(unix) + 0.25,
            sample: LiveSample(unix: unix, heartRate: 60, rrIntervalsMS: [980, 1000]))
    }
    func testDurableHistorySurvivesBeyondAnalysisWindowAndReplayDoesNotDuplicate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("history.sqlite")
        let rows = (0..<4001).map { record(1000 + $0) }
        do {
            let db = try HistoryDatabase(url: url)
            XCTAssertEqual(try db.commitLiveRR(rows), 4001)
            XCTAssertEqual(try db.commitLiveRR(rows), 0)
            XCTAssertEqual(try db.liveRRCount(), 4001)
        }
        let reopened = try HistoryDatabase(url: url)
        XCTAssertEqual(try reopened.liveRR(from: 1000, through: 1000), [rows[0]])
        XCTAssertEqual(try reopened.liveRRCount(), 4001)
    }
    func testTwoNotificationsInOneSecondRetainOriginalSourceAndReceiptPrecision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try HistoryDatabase(url: root.appendingPathComponent("history.sqlite"))
        let a = record(100, id: "first")
        let b = LiveRRRecord(id: "second", source: "Bluetooth 2A37", receivedAtUnix: 100.75,
            sample: LiveSample(unix: 100, heartRate: 61, rrIntervalsMS: [990]))
        try db.commitLiveRR([a, b])
        XCTAssertEqual(Set(try db.liveRR(from: 100, through: 100).map(\.id)), ["first", "second"])
        XCTAssertEqual(try db.liveRRCount(), 2)
    }
    func testExistingNotificationNeverGetsOverwrittenByAConflictingRestore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try HistoryDatabase(url: root.appendingPathComponent("history.sqlite"))
        let original = record(100)
        let conflicting = LiveRRRecord(id: original.id, source: "older-backup", receivedAtUnix: nil,
            sample: LiveSample(unix: 100, heartRate: 90, rrIntervalsMS: [700]))
        try db.commitLiveRR([original])
        XCTAssertEqual(try db.commitLiveRR([conflicting]), 0)
        XCTAssertEqual(try db.liveRR(from: 100, through: 100), [original])
    }
    func testOlderBackupWithoutLiveRRTableStillRestores() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var old: OpaquePointer?
        let path = source.appendingPathComponent("strap-history-v18.sqlite").path
        XCTAssertEqual(sqlite3_open(path, &old), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(old, "CREATE TABLE history_sample(unix INTEGER PRIMARY KEY, payload BLOB NOT NULL)", nil, nil, nil), SQLITE_OK)
        sqlite3_close(old)
        let zip = try PersistenceDiagnostics.write(support: source, documents: root,
            preferences: [:], destinationDirectory: root, fullBackup: true)
        let preview = try StrapBackup.inspect(zip)
        defer { try? fm.removeItem(at: preview.folder) }
        XCTAssertNil(preview.manifest.database?.liveRRRecords)
        let target = root.appendingPathComponent("target")
        try StrapBackup.stage(preview, support: target)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "OlderRRBackup-" + UUID().uuidString))
        try StrapBackup.activatePending(support: target, documents: root.appendingPathComponent("docs"), defaults: defaults)
        XCTAssertEqual(try HistoryDatabase(url: target.appendingPathComponent("strap-history-v18.sqlite")).liveRRCount(), 0)
    }
    func testLegacyMigrationIsDeterministicWithoutInventedSubseconds() throws {
        let sample = LiveSample(unix: 100, heartRate: 60, rrIntervalsMS: [1000])
        XCTAssertEqual(try LiveRRRecord.legacy(sample), try LiveRRRecord.legacy(sample))
        XCTAssertNil(try LiveRRRecord.legacy(sample).receivedAtUnix)
    }
    func testFullBackupRestorePreservesRawRRAndRepeatedRestoreIsIdempotent() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let target = root.appendingPathComponent("target")
        let db = try HistoryDatabase(url: source.appendingPathComponent("strap-history-v18.sqlite"))
        let rows = [record(100), record(200)]
        try db.commitLiveRR(rows)
        let zip = try PersistenceDiagnostics.write(support: source, documents: root.appendingPathComponent("documents"),
            preferences: [:], destinationDirectory: root, fullBackup: true)
        let preview = try StrapBackup.inspect(zip)
        defer { try? fm.removeItem(at: preview.folder) }
        XCTAssertEqual(preview.manifest.database?.liveRRRecords, 2)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "LiveRRRestore-" + UUID().uuidString))
        for _ in 0..<2 {
            try StrapBackup.stage(preview, support: target)
            try StrapBackup.activatePending(support: target, documents: root.appendingPathComponent("restored-documents"), defaults: defaults)
        }
        let restored = try HistoryDatabase(url: target.appendingPathComponent("strap-history-v18.sqlite"))
        XCTAssertEqual(try restored.liveRR(from: 0, through: 300), rows)
        XCTAssertEqual(try restored.liveRRCount(), 2)
    }
    func testRawRRAndHistoryRestoreRollBackTogether() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try HistoryDatabase(url: root.appendingPathComponent("history.sqlite"))
        enum Injected: Error { case diskFailure }
        XCTAssertThrowsError(try db.restoreMissing(token: "rr-failure", stream: { _ in },
            liveRRStream: { accept in try accept([self.record(100)]) }, accompanyingWrites: { throw Injected.diskFailure }))
        XCTAssertEqual(try db.liveRRCount(), 0)
        XCTAssertNil(try db.metadata("restore:rr-failure"))
    }
}

extension LiveRRArchiveTests {
    func testMigrationRunsOnlyOnceAndDoesNotDuplicateLaterNotificationPreferences() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("history.sqlite")
        let old = LiveSample(unix: 100, heartRate: 60, rrIntervalsMS: [1000])
        let later = LiveSample(unix: 200, heartRate: 61, rrIntervalsMS: [980])
        do {
            let db = try HistoryDatabase(url: url)
            XCTAssertEqual(try db.migrateLegacyLiveRR([old]), 1)
            try db.commitLiveRR([LiveRRRecord.received(later, source: "synthetic")])
        }
        let reopened = try HistoryDatabase(url: url)
        XCTAssertEqual(try reopened.migrateLegacyLiveRR([old, later]), 2,
            "The recent preferences must not be imported again over already durable notifications")
        XCTAssertEqual(try reopened.liveRRCount(), 2)
    }
}
