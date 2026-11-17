import Foundation
import CryptoKit
import SQLite3
import ZIPFoundation

/// Reads the installed container without opening the application's migrating writer.
/// A SQLite online backup includes committed WAL rows without checkpointing the source.
enum PersistenceDiagnostics {
    struct FileRecord: Codable {
        let path: String
        let bytes: Int
        let sha256: String
    }
    struct DatabaseRecord: Codable {
        let schema: [String]
        let rows: Int64
        let oldestUnix: Int64?
        let latestUnix: Int64?
    }
    struct Manifest: Codable {
        let formatVersion: Int
        let purpose: String
        let createdAt: Date
        let bundleIdentifier: String
        let build: String
        let algorithmVersion: Int
        let database: DatabaseRecord?
        let files: [FileRecord]
        let missing: [String]
        let note: String
    }
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    // Explicit data keys only: never export arbitrary strap.* tokens/credentials.
    static func permittedKey(_ key: String) -> Bool {
        let exact: Set<String> = ["strap.days.v1", "strap.capture.summary.v1", "strap.sleep.analysis.v1",
            "strap.live.rr.samples.v1", "strap.history.retained.count.v1", "strap.history.lastComplete.v1",
            SleepCorrectionStore.defaultsKey, "strap.settings.v1", "strap.activities.v1", "strap.journal.entries.v1", "strap.live.sessions.v1", "strap.detected.activities.v1",
            "strap.detected.activities.deleted.v1", "strap.whoop.official.workouts.v1",
            "strap.appleHealth.import.samples.v1", "strap.gps.runs.v1", "strap.detected.activity.labels.v1", "strap.wake.alarm.enabled.v1",
            "strap.wake.alarm.minutes.v1", "strap.spo2ResearchEnabled", "strap.spo2ResearchReport"]
        return exact.contains(key) || ["physiological_cycles", "sleeps", "workouts", "journal_entries"].contains { key == "strap.whoop.import." + $0 + ".v1" }
    }

    static func write(support: URL, documents: URL, preferences: [String: Any],
                      destinationDirectory: URL = FileManager.default.temporaryDirectory,
                      fullBackup: Bool = false) throws -> URL {
        let fm = FileManager.default
        let folder = destinationDirectory.appendingPathComponent("STRAP-\(fullBackup ? "backup" : "diagnostics")-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        var files: [FileRecord] = []
        var missing: [String] = []
        func record(_ relative: String) throws {
            let bytes = try Data(contentsOf: folder.appendingPathComponent(relative), options: .mappedIfSafe)
            files.append(FileRecord(path: relative, bytes: bytes.count, sha256: digest(bytes)))
        }
        let safe = preferences.filter { permittedKey($0.key) }
        let plist = try PropertyListSerialization.data(fromPropertyList: safe, format: .binary, options: 0)
        try plist.write(to: folder.appendingPathComponent("persisted-records.plist"), options: .atomic)
        try record("persisted-records.plist")
        let databaseURL = support.appendingPathComponent("strap-history-v18.sqlite")
        var database: DatabaseRecord?
        if fm.fileExists(atPath: databaseURL.path) {
            database = try snapshot(databaseURL, to: folder.appendingPathComponent("history.sqlite"))
            try record("history.sqlite")
            // Inventory sidecars, but do not copy live WAL/SHM independently: they
            // can change between reads. The online snapshot is the coherent copy.
            for suffix in ["", "-wal", "-shm"] {
                let url = URL(fileURLWithPath: databaseURL.path + suffix)
                if fm.fileExists(atPath: url.path) {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    files.append(FileRecord(path: "source-inventory/" + url.lastPathComponent,
                                            bytes: data.count, sha256: digest(data)))
                } else { missing.append(url.lastPathComponent) }
            }
        } else { missing.append(databaseURL.lastPathComponent) }
        let legacy = support.appendingPathComponent("strap-history-v18.json")
        if fm.fileExists(atPath: legacy.path) {
            try fm.copyItem(at: legacy, to: folder.appendingPathComponent(legacy.lastPathComponent))
            try record(legacy.lastPathComponent)
        } else { missing.append(legacy.lastPathComponent) }
        let captures = documents.appendingPathComponent("captures", isDirectory: true)
        if let entries = fm.enumerator(at: captures, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            for case let url as URL in entries {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      ["bin", "json", "raw", "jsonl"].contains(url.pathExtension.lowercased()) else { continue }
                let relative = "captures/" + String(url.path.dropFirst(captures.path.count + 1))
                let target = folder.appendingPathComponent(relative)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: url, to: target)
                try record(relative)
            }
        }
        let gps = support.appendingPathComponent("Strap/gps-runs-v2.json")
        if fm.fileExists(atPath: gps.path) {
            try fm.createDirectory(at: folder.appendingPathComponent("Strap"), withIntermediateDirectories: true)
            try fm.copyItem(at: gps, to: folder.appendingPathComponent("Strap/gps-runs-v2.json"))
            try record("Strap/gps-runs-v2.json")
        }
        let vault = support.appendingPathComponent("sleep-recovery", isDirectory: true)
        if fm.fileExists(atPath: vault.path) {
            try fm.copyItem(at: vault, to: folder.appendingPathComponent("sleep-recovery", isDirectory: true))
            for url in try fm.contentsOfDirectory(at: vault, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                try record("sleep-recovery/" + url.lastPathComponent)
            }
        }
        let manifest = Manifest(formatVersion: 1, purpose: fullBackup ? "strap-backup" : "diagnostics", createdAt: Date(),
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown", build: BuildInfo.revision,
            algorithmVersion: SleepSession.algorithmVersion, database: database,
            files: files.sorted { $0.path < $1.path }, missing: missing,
            note: "Versioned persisted-record snapshot; health data is private. Source sidecar checksums are observations, not a cross-file snapshot. history.sqlite is a consistent committed snapshot. No authentication data is included. Restore merges missing raw seconds and missing storage keys; existing values and manual corrections take precedence. Derived caches remain evidence and may be recomputed.")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        let destination = destinationDirectory.appendingPathComponent(folder.lastPathComponent + ".zip")
        do {
            try fm.zipItem(at: folder, to: destination, shouldKeepParent: false)
            return destination
        } catch { try? fm.removeItem(at: destination); throw error }
    }

    static func snapshot(_ source: URL, to destination: URL) throws -> DatabaseRecord {
        var input: OpaquePointer?, output: OpaquePointer?
        guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(input); throw Failure(message: "Cannot read retained SQLite history; original files preserved.")
        }
        defer { sqlite3_close(input) }
        guard sqlite3_open_v2(destination.path, &output, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            sqlite3_close(output); throw Failure(message: "Cannot create diagnostic snapshot.")
        }
        defer { sqlite3_close(output) }
        guard let backup = sqlite3_backup_init(output, "main", input, "main") else {
            throw Failure(message: "Cannot initialize read-only history snapshot.")
        }
        let status = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard status == SQLITE_DONE, finished == SQLITE_OK else {
            throw Failure(message: "History changed or is busy; retry diagnostics after sync finishes.")
        }
        func query(_ sql: String) throws -> [[String?]] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(output, sql, -1, &statement, nil) == SQLITE_OK else {
                throw Failure(message: "Cannot inspect history schema.")
            }
            defer { sqlite3_finalize(statement) }
            var rows: [[String?]] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { return rows }
                guard result == SQLITE_ROW else { throw Failure(message: "Cannot inspect history rows.") }
                rows.append((0..<sqlite3_column_count(statement)).map { column in
                    sqlite3_column_text(statement, column).map { String(cString: $0) }
                })
            }
        }
        let schema = try query("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name").compactMap { $0[0] }
        let bounds = try query("SELECT COUNT(*), MIN(unix), MAX(unix) FROM history_sample")[0]
        return DatabaseRecord(schema: schema, rows: Int64(bounds[0] ?? "0") ?? 0,
                              oldestUnix: bounds[1].flatMap(Int64.init), latestUnix: bounds[2].flatMap(Int64.init))
    }
}
