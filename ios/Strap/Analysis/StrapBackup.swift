import Foundation
import SQLite3
import ZIPFoundation

/// Stage and validate while running; activate only before any app store/BLE
/// writer exists. Existing raw seconds, settings and corrections always win.
enum StrapBackup {
    struct Preview {
        let folder: URL
        let manifest: PersistenceDiagnostics.Manifest
        var description: String {
            "\(manifest.database?.rows ?? 0) raw records · \(manifest.files.filter { !$0.path.hasPrefix("source-inventory/") }.count) files. Existing raw seconds and storage keys are retained. Conflicting collections are kept in the recovery archive, not silently replaced. Apply on next app launch."
        }
    }
    struct Journal: Codable {
        let token: String
        let absentKeys: [String]
        let createdFiles: [PersistenceDiagnostics.FileRecord]
    }
    static func failure(_ message: String) -> PersistenceDiagnostics.Failure { .init(message: message) }
    static func allowedPath(_ path: String) -> Bool {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.split(separator: "/").contains("..") else { return false }
        return ["persisted-records.plist", "history.sqlite", "strap-history-v18.json", "Strap/gps-runs-v2.json"].contains(path)
            || (path.hasPrefix("captures/") && path.hasSuffix(".jsonl"))
            || (path.hasPrefix("sleep-recovery/") && path.hasSuffix(".json"))
    }
    static func inspect(_ url: URL) throws -> Preview {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("restore-preview-" + UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let archive = try Archive(url: url, accessMode: .read)
            var size: UInt64 = 0
            var paths = Set<String>()
            var count = 0
            for entry in archive {
                count += 1
                guard count <= 100_000, entry.type != .symlink else { throw failure("Unsupported backup entries.") }
                if entry.type == .directory { continue }
                guard entry.path == "manifest.json" || allowedPath(entry.path), paths.insert(entry.path).inserted else {
                    throw failure("Unsafe, unknown or duplicate backup path.")
                }
                let bytes = UInt64(entry.uncompressedSize)
                guard bytes <= 1_000_000_000, size <= 2_000_000_000 - bytes else { throw failure("Backup exceeds 2 GB extraction limit.") }
                size += bytes
            }
            // Preflight every path (including directories) before extraction.
            for entry in archive {
                guard !entry.path.hasPrefix("/"), !entry.path.contains("\\"),
                      !entry.path.split(separator: "/").contains("..") else { throw failure("Unsafe backup path.") }
            }
            try fm.unzipItem(at: url, to: folder)
            return try validate(folder)
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
    }
    static func validate(_ folder: URL) throws -> Preview {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(PersistenceDiagnostics.Manifest.self,
            from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        guard manifest.formatVersion == 1, manifest.purpose == "strap-backup" else { throw failure("Not a supported full STRAP backup.") }
        var paths = Set<String>()
        for record in manifest.files where !record.path.hasPrefix("source-inventory/") {
            guard allowedPath(record.path), paths.insert(record.path).inserted else { throw failure("Invalid backup manifest path.") }
            let data = try Data(contentsOf: folder.appendingPathComponent(record.path), options: .mappedIfSafe)
            guard data.count == record.bytes, PersistenceDiagnostics.digest(data) == record.sha256 else {
                throw failure("Backup checksum mismatch: " + record.path)
            }
        }
        guard paths.contains("persisted-records.plist") else { throw failure("Backup has no persisted-record snapshot.") }
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: folder.appendingPathComponent("persisted-records.plist")), format: nil)
        guard let preferences = plist as? [String: Any], preferences.keys.allSatisfy(PersistenceDiagnostics.permittedKey) else {
            throw failure("Backup contains unsupported settings.")
        }
        return Preview(folder: folder, manifest: manifest)
    }
    static func stage(_ preview: Preview, support: URL) throws {
        _ = try validate(preview.folder)
        let pending = support.appendingPathComponent("restore-pending", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: pending.path) else { throw failure("A restore is already pending. Restart STRAP to finish it.") }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        // Copy to a unique sibling, then atomically publish the pending request.
        let staging = support.appendingPathComponent("restore-staging-" + UUID().uuidString)
        try FileManager.default.copyItem(at: preview.folder, to: staging)
        try FileManager.default.moveItem(at: staging, to: pending)
    }
    static func samples(_ url: URL) throws -> [V18Sample] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db); throw failure("Cannot read backup history.")
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM history_sample ORDER BY unix", -1, &statement, nil) == SQLITE_OK else {
            throw failure("Unsupported backup history schema.")
        }
        defer { sqlite3_finalize(statement) }
        var result: [V18Sample] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw failure("Unreadable backup record.") }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            result.append(try JSONDecoder().decode(V18Sample.self, from: data))
        }
    }
    /// Crash recovery uses the SQLite commit marker to distinguish rollback
    /// from completion. On failure the app does not construct its live stores.
    static func activatePending(support: URL, documents: URL, defaults: UserDefaults = .standard) throws {
        let fm = FileManager.default
        let pending = support.appendingPathComponent("restore-pending", isDirectory: true)
        guard fm.fileExists(atPath: pending.path) else { return }
        let preview = try validate(pending)
        let preferences = try PropertyListSerialization.propertyList(from: Data(contentsOf: pending.appendingPathComponent("persisted-records.plist")), format: nil) as! [String: Any]
        let journalURL = pending.appendingPathComponent("restore-journal.json")
        let database = try HistoryDatabase(url: support.appendingPathComponent("strap-history-v18.sqlite"))
        func destination(_ path: String) -> URL {
            path.hasPrefix("captures/") ? documents.appendingPathComponent(path) : support.appendingPathComponent(path)
        }
        func rollback(_ journal: Journal) throws {
            for key in journal.absentKeys { defaults.removeObject(forKey: key) }
            guard defaults.synchronize() else { throw failure("Cannot persist restore rollback; restart to retry.") }
            for file in journal.createdFiles {
                let target = destination(file.path)
                if fm.fileExists(atPath: target.path) {
                    // Startup owns these files; refuse to erase unexpected edits.
                    guard PersistenceDiagnostics.digest(try Data(contentsOf: target)) == file.sha256 else {
                        throw failure("Restore rollback found changed evidence; original files preserved.")
                    }
                    try fm.removeItem(at: target)
                }
            }
        }
        func finish(_ token: String) throws {
            let history = support.appendingPathComponent("restore-history", isDirectory: true)
            try fm.createDirectory(at: history, withIntermediateDirectories: true)
            try fm.moveItem(at: pending, to: history.appendingPathComponent(token, isDirectory: true))
        }
        if fm.fileExists(atPath: journalURL.path) {
            let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
            if try database.metadata("restore:" + journal.token) == "committed" {
                // Repair preference delivery if the process stopped after the
                // SQLite commit. Never replace an existing value on replay.
                for key in journal.absentKeys where defaults.object(forKey: key) == nil {
                    defaults.set(preferences[key], forKey: key)
                }
                guard defaults.synchronize() else { throw failure("Cannot finish restored preferences.") }
                try finish(journal.token)
                return
            }
            try rollback(journal)
        }
        let absent = preferences.keys.filter { defaults.object(forKey: $0) == nil }.sorted()
        let files = preview.manifest.files.filter { record in
            allowedPath(record.path) && !["persisted-records.plist", "history.sqlite"].contains(record.path)
                && !fm.fileExists(atPath: destination(record.path).path)
        }
        let journal = Journal(token: UUID().uuidString, absentKeys: absent, createdFiles: files)
        let source = pending.appendingPathComponent("history.sqlite")
        let legacy = pending.appendingPathComponent("strap-history-v18.json")
        let rows: [V18Sample]
        if fm.fileExists(atPath: source.path) { rows = try samples(source) }
        else if fm.fileExists(atPath: legacy.path) { rows = try JSONDecoder().decode([V18Sample].self, from: Data(contentsOf: legacy)) }
        else { rows = [] }
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
        do {
            try database.restoreMissing(rows, token: journal.token) {
                for file in files {
                    let target = destination(file.path)
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: pending.appendingPathComponent(file.path), to: target)
                }
                for key in absent { defaults.set(preferences[key], forKey: key) }
                guard defaults.synchronize() else { throw failure("Cannot persist restored preferences; SQLite restore rolled back.") }
            }
        } catch {
            try rollback(journal)
            throw error
        }
        try finish(journal.token)
    }
}
