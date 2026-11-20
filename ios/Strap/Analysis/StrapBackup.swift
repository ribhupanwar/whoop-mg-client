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
            "\(manifest.database?.rows ?? 0) SQLite records plus retained legacy/capture evidence · \(manifest.files.filter { !$0.path.hasPrefix("source-inventory/") }.count) files. Existing raw seconds and storage keys are retained. Conflicting collections are kept in the recovery archive, not silently replaced. Apply on next app launch."
        }
    }
    struct Journal: Codable {
        let token: String
        let absentKeys: [String]
        let createdFiles: [PersistenceDiagnostics.FileRecord]
    }
    static func failure(_ message: String) -> PersistenceDiagnostics.Failure { .init(message: message) }
    static func allowedPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.contains("\\"), !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return false }
        return ["persisted-records.plist", "history.sqlite", "strap-history-v18.json", "Strap/gps-runs-v2.json"].contains(path)
            || (path.hasPrefix("captures/") && ["bin", "json", "raw", "jsonl"].contains((path as NSString).pathExtension.lowercased()))
            || (path.hasPrefix("sleep-recovery/") && path.hasSuffix(".json"))
    }
    /// Directory entries must be rooted in a supported backup namespace.
    /// No directory entry is extracted, but malformed metadata is rejected.
    static func allowedDirectoryPath(_ path: String) -> Bool {
        guard path.hasSuffix("/"), !path.contains("\\"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        let parts = path.dropLast().split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return false }
        let name = parts.joined(separator: "/")
        // Do not allow a directory to impersonate a supported capture file.
        if name.hasPrefix("captures/"), let leaf = parts.last,
           ["bin", "json", "raw", "jsonl"].contains((String(leaf) as NSString).pathExtension.lowercased()) {
            return false
        }
        return name == "captures" || name.hasPrefix("captures/")
            || name == "sleep-recovery" || name.hasPrefix("sleep-recovery/")
            || name == "Strap"
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
                    throw failure("Unsafe, unknown or duplicate backup path: " + entry.path)
                }
                let bytes = UInt64(entry.uncompressedSize)
                guard bytes <= 1_000_000_000, size <= 2_000_000_000 - bytes else { throw failure("Backup exceeds 2 GB extraction limit.") }
                size += bytes
            }
            // Preflight every path (including directories) before extraction.
            for entry in archive {
                guard entry.path == "manifest.json" || allowedPath(entry.path) ||
                      (entry.type == .directory && allowedDirectoryPath(entry.path)) else {
                    throw failure("Unsafe backup path.")
                }
            }
            var extracted: UInt64 = 0
            for entry in archive where entry.type == .file {
                let target = folder.appendingPathComponent(entry.path)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard fm.createFile(atPath: target.path, contents: nil) else { throw failure("Cannot stage backup file.") }
                let handle = try FileHandle(forWritingTo: target)
                defer { try? handle.close() }
                var actual: UInt64 = 0
                _ = try archive.extract(entry) { chunk in
                    actual += UInt64(chunk.count)
                    extracted += UInt64(chunk.count)
                    guard actual <= UInt64(entry.uncompressedSize), extracted <= 2_000_000_000 else {
                        throw failure("Backup extraction exceeds declared size.")
                    }
                    try handle.write(contentsOf: chunk)
                }
                guard actual == UInt64(entry.uncompressedSize) else { throw failure("Incomplete backup file.") }
            }
            return try validate(folder)
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
    }
    static func validate(_ folder: URL, allowJournal: Bool = false) throws -> Preview {
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
        if let entries = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            for case let url as URL in entries {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw failure("Backup contains a symbolic link.") }
                if values.isRegularFile == true {
                    let path = String(url.path.dropFirst(folder.path.count + 1))
                    guard path == "manifest.json" || paths.contains(path) || (allowJournal && path == "restore-journal.json") else {
                        throw failure("Backup file is missing from the checksum manifest.")
                    }
                }
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
        let fm = FileManager.default
        let pending = support.appendingPathComponent("restore-pending", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: pending.path) else { throw failure("A restore is already pending. Restart STRAP to finish it.") }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        // Copy to a unique sibling, then atomically publish the pending request.
        let staging = support.appendingPathComponent("restore-staging-" + UUID().uuidString)
        do {
            try fm.copyItem(at: preview.folder, to: staging)
            try fm.moveItem(at: staging, to: pending)
        } catch {
            // A failed copy can leave a partial restore-staging directory.
            // Never leave that unvalidated copy behind for a later startup.
            try? fm.removeItem(at: staging)
            throw error
        }
    }
    static func streamSamples(_ url: URL, accept: ([V18Sample]) throws -> Void) throws {
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
            if status == SQLITE_DONE { if !result.isEmpty { try accept(result) }; return }
            guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw failure("Unreadable backup record.") }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            result.append(try JSONDecoder().decode(V18Sample.self, from: data))
            if result.count >= 1000 { try accept(result); result.removeAll(keepingCapacity: true) }
        }
    }
    static func streamLiveRR(_ url: URL, accept: ([LiveRRRecord]) throws -> Void) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db); throw failure("Cannot read live R-R backup history.")
        }
        defer { sqlite3_close(db) }
        var check: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' AND name='live_rr_record'", -1, &check, nil) == SQLITE_OK else {
            throw failure("Cannot inspect live R-R backup schema.")
        }
        let present = sqlite3_step(check) == SQLITE_ROW
        sqlite3_finalize(check)
        guard present else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM live_rr_record ORDER BY unix, source_id", -1, &statement, nil) == SQLITE_OK else {
            throw failure("Unsupported live R-R backup schema.")
        }
        defer { sqlite3_finalize(statement) }
        var batch: [LiveRRRecord] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { if !batch.isEmpty { try accept(batch) }; return }
            guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
                throw failure("Unreadable live R-R backup record.")
            }
            batch.append(try JSONDecoder().decode(LiveRRRecord.self,
                from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))))
            if batch.count >= 1000 { try accept(batch); batch.removeAll(keepingCapacity: true) }
        }
    }

    /// Crash recovery uses the SQLite commit marker to distinguish rollback
    /// from completion. On failure the app does not construct its live stores.
    static func activatePending(support: URL, documents: URL, defaults: UserDefaults = .standard) throws {
        let fm = FileManager.default
        let pending = support.appendingPathComponent("restore-pending", isDirectory: true)
        guard fm.fileExists(atPath: pending.path) else { return }
        let preview = try validate(pending, allowJournal: true)
        let plistData = try Data(contentsOf: pending.appendingPathComponent("persisted-records.plist"))
        guard let preferences = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw failure("Corrupt persisted-records.plist in restore payload")
        }
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
            allowedPath(record.path) && !["persisted-records.plist", "history.sqlite", "strap-history-v18.json"].contains(record.path)
                && !fm.fileExists(atPath: destination(record.path).path)
        }
        let journal = Journal(token: UUID().uuidString, absentKeys: absent, createdFiles: files)
        let source = pending.appendingPathComponent("history.sqlite")
        let legacy = pending.appendingPathComponent("strap-history-v18.json")
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
        do {
            try database.restoreMissing(token: journal.token, stream: { accept in
                let hasDatabase = fm.fileExists(atPath: source.path)
                if hasDatabase { try streamSamples(source, accept: accept) }
                if fm.fileExists(atPath: legacy.path) {
                    let bytes = try Data(contentsOf: legacy)
                    if let rows = try? JSONDecoder().decode([V18Sample].self, from: bytes) {
                        try accept(rows)
                    } else if !hasDatabase {
                        throw failure("No decodable history source; original backup retained.")
                    }
                }
                // The legacy source remains in restore-history, never at the
                // live migration path: later startup must not reimport older
                // backup packets over existing valid seconds.

            }, liveRRStream: { accept in
                if fm.fileExists(atPath: source.path) { try streamLiveRR(source, accept: accept) }
            }, legacyLiveRRImported: preview.manifest.database?.liveRRRecords != nil) {
                for file in files {
                    let target = destination(file.path)
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(contentsOf: pending.appendingPathComponent(file.path), options: .mappedIfSafe)
                        .write(to: target, options: .atomic)
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
