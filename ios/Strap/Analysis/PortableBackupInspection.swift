import Foundation
import SQLite3
import ZIPFoundation

/// Foreign backups are not STRAP's raw band archive. Inspect only; never
/// fabricate V18 headers, copy credentials, or mutate either database.
enum PortableBackupInspection {
    struct Report: Equatable {
        let channels: [String]
        let missing: [String]
        var description: String {
            "Readable schema: " + channels.joined(separator: ", ") +
            (missing.isEmpty ? "" : ". Missing or unsupported: " + missing.joined(separator: ", ")) +
            ". Preview only; no STRAP records changed."
        }
    }
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func inspect(_ url: URL) throws -> Report {
        let fm = FileManager.default
        let handle = try FileHandle(forReadingFrom: url)
        let header: Data
        do { header = try handle.read(upToCount: 16) ?? Data(); try handle.close() }
        catch { try? handle.close(); throw error }
        if header == Data("SQLite format 3\0".utf8) { return try inspectDatabase(url) }

        let archive = try Archive(url: url, accessMode: .read)
        let folder = fm.temporaryDirectory.appendingPathComponent("portable-preview-" + UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        var entry: Entry?
        var count = 0
        for candidate in archive {
            count += 1
            guard count <= 100_000, candidate.type != .symlink else {
                throw Failure(message: "Unsupported archive entries.")
            }
            // Only the documented root database. Ignore all other content.
            if candidate.path == "noop-backup.sqlite" && candidate.type == .file {
                guard entry == nil else { throw Failure(message: "Duplicate database entry.") }
                entry = candidate
            }
        }
        guard let entry else {
            throw Failure(message: "No supported NOOP database found. Woop archive schema requires a representative export.")
        }
        let limit: UInt64 = 1_000_000_000
        guard UInt64(entry.uncompressedSize) <= limit else {
            throw Failure(message: "Portable database exceeds the 1 GB preview limit.")
        }
        let target = folder.appendingPathComponent("source.sqlite")
        guard fm.createFile(atPath: target.path, contents: nil) else {
            throw Failure(message: "Cannot create temporary database.")
        }
        let out = try FileHandle(forWritingTo: target)
        var actual: UInt64 = 0
        do {
            let checksum = try archive.extract(entry) { bytes in
                actual += UInt64(bytes.count)
                guard actual <= limit, actual <= UInt64(entry.uncompressedSize) else {
                    throw Failure(message: "Archive exceeds declared database size.")
                }
                try out.write(contentsOf: bytes)
            }
            guard checksum == entry.checksum else {
                throw Failure(message: "Database archive checksum mismatch.")
            }
            try out.close()
        } catch { try? out.close(); throw error }
        guard actual == UInt64(entry.uncompressedSize) else {
            throw Failure(message: "Incomplete database extraction.")
        }
        return try inspectDatabase(target)
    }

    static func inspectDatabase(_ url: URL) throws -> Report {
        var db: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        defer { sqlite3_close(db) }
        guard status == SQLITE_OK, let db else { throw Failure(message: "Database cannot be opened read-only.") }
        sqlite3_busy_timeout(db, 1000)
        guard sqlite3_exec(db, "PRAGMA query_only=ON; PRAGMA trusted_schema=OFF;", nil, nil, nil) == SQLITE_OK else {
            throw Failure(message: "Cannot configure read-only database inspection.")
        }
        func strings(_ sql: String, column: Int32 = 0) throws -> Set<String> {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw Failure(message: "Portable database schema could not be read.")
            }
            defer { sqlite3_finalize(statement) }
            var result = Set<String>()
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { return result }
                guard step == SQLITE_ROW else { throw Failure(message: "Portable database is unreadable.") }
                if let value = sqlite3_column_text(statement, column) { result.insert(String(cString: value)) }
            }
        }
        let tables = try strings("SELECT name FROM sqlite_master WHERE type='table'")
        let known: [(String, Set<String>)] = [
            ("hrSample", ["ts", "bpm"]),
            ("rrInterval", ["ts", "rrMs"]),
            ("gravitySample", ["ts", "x", "y", "z"]),
            ("skinTempSample", ["ts", "raw"]),
            ("stepSample", ["ts", "counter"]),
            ("spo2Sample", ["ts", "red", "ir"])
        ]
        var supported: [String] = [], missing: [String] = []
        for (table, required) in known {
            if tables.contains(table), required.isSubset(of: try strings("PRAGMA table_info(" + table + ")", column: 1)) {
                supported.append(table)
            } else { missing.append(table) }
        }
        guard supported.contains("hrSample") else {
            throw Failure(message: "No compatible heart-rate table. No data imported.")
        }
        return Report(channels: supported, missing: missing)
    }
}
