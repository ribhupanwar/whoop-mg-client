import XCTest
import ZIPFoundation
@testable import Strap

final class StrapBackupTests: XCTestCase {
    private func sample(_ unix: Int, hr: Int = 63) -> V18Sample {
        V18Sample(header: BandRecordHeader(version: 18, flags: 0, recordIndex: UInt32(unix), unix: UInt32(unix), subsecQ15: 0),
            heartRate: hr, rrIntervalsMS: [943, 951], dynamicAccelG: 0.02,
            gravityXG: nil, gravityYG: nil, gravityZG: nil, stepCounter: 12, stepCadence: nil,
            activityClass: nil, skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: nil, sleepState: nil, cardiacFlags: nil, hrQualityFlags: nil,
            spo2CandidateRaw: nil, spo2CandidatePct: nil, spo2CandidateKind: .absent,
            signalQualityLogVariance: nil, psnrB: nil, psnrA: nil)
    }

    func testFullExportFreshContainerRestoreAndRepeatedImport() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source")
        let documents = root.appendingPathComponent("documents")
        let destination = root.appendingPathComponent("fresh")
        let restoredDocuments = root.appendingPathComponent("fresh-documents")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: documents.appendingPathComponent("captures"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let rows = [sample(100), sample(200)]
        let database = try HistoryDatabase(url: source.appendingPathComponent("strap-history-v18.sqlite"))
        try database.commit(rows)
        try JSONEncoder().encode([sample(50), sample(100, hr: 90)])
            .write(to: source.appendingPathComponent("strap-history-v18.json"))
        let captured = Data("{\"fixture\":true}\n".utf8)
        try captured.write(to: documents.appendingPathComponent("captures/fixture.jsonl"))
        let preferences: [String: Any] = [SleepCorrectionStore.defaultsKey: ["100": [100, 201]], "strap.days.v1": Data("[]".utf8)]
        let backup = try PersistenceDiagnostics.write(support: source, documents: documents,
            preferences: preferences, destinationDirectory: root, fullBackup: true)
        let packaged = try Archive(url: backup, accessMode: .read)
        XCTAssertTrue(packaged.allSatisfy { $0.path == "manifest.json" || StrapBackup.allowedPath($0.path) },
            "A generated full backup must contain only restore-supported manifest entries")
        let preview = try StrapBackup.inspect(backup)
        defer { try? fm.removeItem(at: preview.folder) }
        XCTAssertEqual(preview.manifest.database?.rows, 2)
        let suite = "StrapBackupTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { for key in preferences.keys { defaults.removeObject(forKey: key) } }
        try StrapBackup.stage(preview, support: destination)
        try StrapBackup.activatePending(support: destination, documents: restoredDocuments, defaults: defaults)
        let restored = try HistoryDatabase(url: destination.appendingPathComponent("strap-history-v18.sqlite"))
        XCTAssertEqual(try restored.samples(from: 0, through: 300), [sample(50)] + rows)
        XCTAssertFalse(fm.fileExists(atPath: destination.appendingPathComponent("strap-history-v18.json").path),
            "Older backup packets must not enter the live migration path")
        XCTAssertEqual(defaults.data(forKey: "strap.days.v1"), preferences["strap.days.v1"] as? Data)
        XCTAssertEqual(defaults.dictionary(forKey: SleepCorrectionStore.defaultsKey) as? [String: [Int]], ["100": [100, 201]])
        XCTAssertEqual(try Data(contentsOf: restoredDocuments.appendingPathComponent("captures/fixture.jsonl")), captured)
        // A repeat import must retain later valid raw records and manual edits.
        // Use a separate second in the current container as well.
        try restored.commit([sample(300)])
        defaults.set(["100": [110, 190]], forKey: SleepCorrectionStore.defaultsKey)
        try StrapBackup.stage(preview, support: destination)
        try StrapBackup.activatePending(support: destination, documents: restoredDocuments, defaults: defaults)
        XCTAssertEqual(try restored.samples(from: 0, through: 300).count, 4)
        XCTAssertEqual(defaults.dictionary(forKey: SleepCorrectionStore.defaultsKey) as? [String: [Int]], ["100": [110, 190]])
    }

    func testStagingFailureLeavesNoPartialRestoreFolder() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let backup = try PersistenceDiagnostics.write(support: root, documents: root,
            preferences: [:], destinationDirectory: root, fullBackup: true)
        let preview = try StrapBackup.inspect(backup)
        defer { try? fm.removeItem(at: preview.folder) }
        let support = root.appendingPathComponent("target")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        // A file at the pending destination makes atomic publish fail after
        // staging has copied. No temporary restore copy may survive.
        try Data("occupied".utf8).write(to: support.appendingPathComponent("restore-pending"))
        XCTAssertThrowsError(try StrapBackup.stage(preview, support: support))
        let names = try fm.contentsOfDirectory(atPath: support.path)
        XCTAssertFalse(names.contains { $0.hasPrefix("restore-staging-") })
        XCTAssertEqual(try Data(contentsOf: support.appendingPathComponent("restore-pending")),
            Data("occupied".utf8))
    }

    func testRestoreTransactionRollsBackBeforeCommitMarkerOnFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try HistoryDatabase(url: root.appendingPathComponent("history.sqlite"))
        try database.commit([sample(100)])
        enum Injected: Error { case diskFailure }
        XCTAssertThrowsError(try database.restoreMissing([sample(200)], token: "test") { throw Injected.diskFailure })
        XCTAssertEqual(try database.samples(from: 0, through: 300), [sample(100)])
        XCTAssertNil(try database.metadata("restore:test"))
    }

    func testRestoreRejectsCorruptionAndDiagnosticOnlyExports() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let backup = try PersistenceDiagnostics.write(support: root, documents: root,
            preferences: [:], destinationDirectory: root, fullBackup: true)
        let preview = try StrapBackup.inspect(backup)
        defer { try? fm.removeItem(at: preview.folder) }
        try Data("corrupt".utf8).write(to: preview.folder.appendingPathComponent("persisted-records.plist"))
        XCTAssertThrowsError(try StrapBackup.validate(preview.folder))
        let diagnostic = try PersistenceDiagnostics.write(support: root, documents: root, preferences: [:], destinationDirectory: root)
        XCTAssertThrowsError(try StrapBackup.inspect(diagnostic))
        XCTAssertFalse(StrapBackup.allowedPath("captures/../../history.sqlite"))
        XCTAssertFalse(StrapBackup.allowedPath("/history.sqlite"))
    }
}

extension StrapBackupTests {
    func testInterruptedRestoreReplaysOnlyMissingPreferencesAfterCommittedMarker() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let support = root.appendingPathComponent("target")
        let expected = Data("[]".utf8)
        let backup = try PersistenceDiagnostics.write(support: root, documents: root,
            preferences: ["strap.days.v1": expected], destinationDirectory: root, fullBackup: true)
        let preview = try StrapBackup.inspect(backup)
        defer { try? fm.removeItem(at: preview.folder) }
        try StrapBackup.stage(preview, support: support)
        let journal = StrapBackup.Journal(token: "interrupted", absentKeys: ["strap.days.v1"], createdFiles: [])
        try JSONEncoder().encode(journal).write(to: support.appendingPathComponent("restore-pending/restore-journal.json"))
        let database = try HistoryDatabase(url: support.appendingPathComponent("strap-history-v18.sqlite"))
        try database.restoreMissing([], token: journal.token) {}
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "InterruptedRestore-" + UUID().uuidString))
        defer { defaults.removeObject(forKey: "strap.days.v1") }
        try StrapBackup.activatePending(support: support, documents: root.appendingPathComponent("documents"), defaults: defaults)
        XCTAssertEqual(defaults.data(forKey: "strap.days.v1"), expected)
        XCTAssertFalse(fm.fileExists(atPath: support.appendingPathComponent("restore-pending").path))
        XCTAssertEqual(try database.metadata("restore:interrupted"), "committed")
    }

    func testExistingRawSecondWinsDuringBackupRestore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try HistoryDatabase(url: root.appendingPathComponent("history.sqlite"))
        let current = sample(100, hr: 70)
        try database.commit([current])
        try database.restoreMissing([sample(100, hr: 63), sample(200)], token: "backup") {}
        XCTAssertEqual(try database.samples(from: 0, through: 300), [current, sample(200)])
    }
}
