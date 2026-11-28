import XCTest
import SQLite3
import ZIPFoundation
@testable import Strap

final class PersistenceDiagnosticsTests: XCTestCase {
    func testReadOnlySnapshotIncludesCommittedWALAndNeverMigratesSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(source.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE history_sample(unix INTEGER PRIMARY KEY, payload BLOB); INSERT INTO history_sample VALUES(100,x'00'),(200,x'01');", nil, nil, nil), SQLITE_OK)
        let wal = URL(fileURLWithPath: source.path + "-wal")
        let before = try Data(contentsOf: wal)
        let destination = root.appendingPathComponent("snapshot.sqlite")
        let result = try PersistenceDiagnostics.snapshot(source, to: destination)
        XCTAssertEqual(result.rows, 2)
        XCTAssertEqual(result.oldestUnix, 100)
        XCTAssertEqual(result.latestUnix, 200)
        XCTAssertEqual(try Data(contentsOf: wal), before, "Diagnostics must not checkpoint the source WAL")
        let snapshotBytes = try Data(contentsOf: destination)
        XCTAssertEqual(snapshotBytes[18], 1, "Exported database must be standalone rollback-journal mode")
        XCTAssertEqual(result.schema.count, 1, "Do not create app tables during read-only diagnostics")
    }

    func testSensitiveAndUnknownDefaultsNeverEnterDiagnostics() {
        for key in ["strap.auth.token", "strap.password", "strap.whoop.import.token.v1", "AppleLanguages"] {
            XCTAssertFalse(PersistenceDiagnostics.permittedKey(key))
        }
        XCTAssertTrue(PersistenceDiagnostics.permittedKey(SleepCorrectionStore.defaultsKey))
        XCTAssertTrue(PersistenceDiagnostics.permittedKey("strap.capture.summary.v1"))
    }

    func testNewOptInReminderPreferencesSurviveVerifiedBackupAllowlist() {
        let keys = [
            "strap.workout.keepScreenOn", "strap.journal.hiddenQuestions",
            "strap.journalReminderEnabled", "strap.journalReminderMinutes",
            "strap.lowBatteryNoticeEnabled", "strap.recoveryRecapNoticeEnabled",
            "strap.workoutSavedNoticeEnabled"
        ]
        for key in keys {
            XCTAssertTrue(PersistenceDiagnostics.permittedKey(key), "Backup must preserve \(key)")
        }
        XCTAssertFalse(PersistenceDiagnostics.permittedKey("strap.localNotice.last.battery"),
                       "Notification delivery dedup state must not be imported from a different device")
    }

    func testVaultPreservesUndecodableCacheIdempotently() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("old schema bytes".utf8)
        try SleepRecoveryVault.preserve(bytes, key: "strap.capture.summary.v1", directory: directory)
        try SleepRecoveryVault.preserve(bytes, key: "strap.capture.summary.v1", directory: directory)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(files.first)), bytes)
    }
}


extension PersistenceDiagnosticsTests {
    func testCalorieShadowEvidenceOnlyInDiagnosticNotRestoreBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let start = Date(timeIntervalSince1970: 1000)
        var capture = WorkoutCalorieShadowCapture()
        capture.append(hr: 150, at: start, anchors: nil)
        let session = WorkoutSession(id: UUID(), activityKind: "run", activityLabel: "Run",
            startedAt: start, endedAt: start.addingTimeInterval(2), phase: .saved)
        try WorkoutCalorieShadowCapture.write(XCTUnwrap(capture.evidence(for: session)), support: root)
        let path = "calorie-shadow/" + session.id.uuidString + ".json"
        let diagnostic = try PersistenceDiagnostics.write(support: root, documents: root, preferences: [:], destinationDirectory: root)
        let backup = try PersistenceDiagnostics.write(support: root, documents: root, preferences: [:], destinationDirectory: root, fullBackup: true)
        XCTAssertNotNil(try Archive(url: diagnostic, accessMode: .read)[path])
        XCTAssertNil(try Archive(url: backup, accessMode: .read)[path])
    }
}
