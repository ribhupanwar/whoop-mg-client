import Foundation
import SQLite3

/// One connection per worker, never shared across queues. Keep raw history on
/// disk and load only the bounded window needed by current analysis.
final class HistoryDatabase {
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let error = failure(); sqlite3_close(db); db = nil; throw error
        }
        encoder.outputFormatting = [.sortedKeys]
        do {
            sqlite3_busy_timeout(db, 5000)
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            // One durable schema commit, rather than a FULL fsync for every
            // table during the first morning sync or retry on a slow device.
            try transaction {
                try execute("CREATE TABLE IF NOT EXISTS history_sample (unix INTEGER PRIMARY KEY, payload BLOB NOT NULL)")
                try execute("CREATE TABLE IF NOT EXISTS live_rr_record (source_id TEXT PRIMARY KEY, unix INTEGER NOT NULL, payload BLOB NOT NULL)")
                try execute("CREATE INDEX IF NOT EXISTS live_rr_unix ON live_rr_record(unix)")
                try execute("CREATE TABLE IF NOT EXISTS history_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
                try execute("CREATE TABLE IF NOT EXISTS analysis_checkpoint (key TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, result BLOB NOT NULL)")
            }
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }

    /// Decoded rows and their chunk token either commit together or roll back.
    @discardableResult
    func commit(_ rows: [V18Sample], token: String? = nil) throws -> Int {
        try commitReportingProgress(rows, token: token).changed
    }

    struct CommitProgress {
        var changed = 0
        var newestInserted: Int?
    }

    func commitReportingProgress(_ rows: [V18Sample], token: String?) throws -> CommitProgress {
        let batchSize = rows.count
        try transactionWithBatchSize(batchSize) {
            let progress = try insert(rows)
            if let token { try setMetadata("last_history_chunk", value: token) }
            return progress
        }
    }

    private func transactionWithBatchSize<T>(_ batchSize: Int, _ body: () throws -> T) throws -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        var contentionCount = 0
        let maxRetries = 3
        for attempt in 1...maxRetries {
            do {
                try execute("BEGIN IMMEDIATE")
                do { let result = try body(); try execute("COMMIT");
                    let latency = CFAbsoluteTimeGetCurrent() - startTime
                    PerformanceProfiler.shared.recordSQLiteTransaction(batchSize: batchSize, latency: latency, contentionCount: contentionCount)
                    return result }
                catch { try? execute("ROLLBACK"); throw error }
            } catch {
                if attempt < maxRetries {
                    contentionCount += 1
                    Thread.sleep(forTimeInterval: 0.01 * Double(attempt))
                    continue
                }
                let latency = CFAbsoluteTimeGetCurrent() - startTime
                PerformanceProfiler.shared.recordSQLiteTransaction(batchSize: batchSize, latency: latency, contentionCount: contentionCount)
                throw error
            }
        }
        throw failure()
    }

    /// Keep the original JSON intact. The migration marker commits with its
    /// rows, so interruption cannot mark a partially imported file as complete.
    func migrateLegacyJSON(at url: URL) throws {
        guard try metadata("legacy_json_imported") == nil else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var rows: [V18Sample] = []
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            do { rows = try decoder.decode([V18Sample].self, from: data) }
            catch is DecodingError {
                let backup = url.deletingPathExtension().appendingPathExtension("invalid-\(PersistenceDiagnostics.digest(data)).json")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try FileManager.default.copyItem(at: url, to: backup)
                }
                // An unreadable file is not a completed migration. Keep it,
                // allow raw BLE writes, and retry the legacy source on reopen.
                return
            }
        }
        try transaction {
            _ = try insert(rows)
            try setMetadata("legacy_json_imported", value: "1")
        }
    }

    func recentSamples(windowSeconds: Int = 72 * 3600) throws -> [V18Sample] {
        let s = try prepare("SELECT payload FROM history_sample WHERE unix >= (SELECT MAX(unix) FROM history_sample) - ? ORDER BY unix")
        defer { sqlite3_finalize(s) }
        sqlite3_bind_int64(s, 1, Int64(max(0, windowSeconds)))
        return try readSamples(s)
    }
    func samples(from start: Int, through end: Int) throws -> [V18Sample] {
        let s = try prepare("SELECT payload FROM history_sample WHERE unix BETWEEN ? AND ? ORDER BY unix")
        defer { sqlite3_finalize(s) }
        sqlite3_bind_int64(s, 1, Int64(start)); sqlite3_bind_int64(s, 2, Int64(end))
        return try readSamples(s)
    }
    func metadata(_ key: String) throws -> String? {
        let s = try prepare("SELECT value FROM history_meta WHERE key = ?")
        defer { sqlite3_finalize(s) }
        sqlite3_bind_text(s, 1, key, -1, transient)
        let status = sqlite3_step(s)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW, let value = sqlite3_column_text(s, 0) else { throw failure() }
        return String(cString: value)
    }
    func cached<T: Decodable>(_ type: T.Type, key: String, fingerprint: String) throws -> T? {
        let s = try prepare("SELECT result FROM analysis_checkpoint WHERE key = ? AND fingerprint = ?")
        defer { sqlite3_finalize(s) }
        sqlite3_bind_text(s, 1, key, -1, transient); sqlite3_bind_text(s, 2, fingerprint, -1, transient)
        let status = sqlite3_step(s)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW else { throw failure() }
        let data = try blob(s, column: 0)
        return try? decoder.decode(type, from: data) // Obsolete derived caches may be recomputed.
    }
    func cache<T: Encodable>(_ result: T, key: String, fingerprint: String) throws {
        let data = try encoder.encode(result)
        let s = try prepare("INSERT INTO analysis_checkpoint (key, fingerprint, result) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET fingerprint=excluded.fingerprint, result=excluded.result")
        defer { sqlite3_finalize(s) }
        sqlite3_bind_text(s, 1, key, -1, transient); sqlite3_bind_text(s, 2, fingerprint, -1, transient)
        bind(data, to: s, column: 3)
        guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
    }
    /// Backup restore never replaces a retained second. The marker and raw rows
    /// commit together; accompanying startup-only writes have a recovery journal.
    func restoreMissing(_ rows: [V18Sample], token: String, accompanyingWrites: () throws -> Void) throws {
        try restoreMissing(token: token, stream: { accept in try accept(rows) }, accompanyingWrites: accompanyingWrites)
    }

    func restoreMissing(token: String, stream: (_ accept: ([V18Sample]) throws -> Void) throws -> Void,
                        liveRRStream: (_ accept: ([LiveRRRecord]) throws -> Void) throws -> Void = { _ in },
                        legacyLiveRRImported: Bool = false,
                        accompanyingWrites: () throws -> Void) throws {
        try transaction {
            let lookup = try prepare("SELECT 1 FROM history_sample WHERE unix = ?")
            defer { sqlite3_finalize(lookup) }
            try stream { rows in
                var missing: [V18Sample] = []
                for row in rows {
                    sqlite3_reset(lookup)
                    sqlite3_bind_int64(lookup, 1, Int64(row.unix))
                    let result = sqlite3_step(lookup)
                    if result == SQLITE_DONE { missing.append(row) }
                    else if result != SQLITE_ROW { throw failure() }
                }
                _ = try insert(missing)
            }
            try liveRRStream { _ = try insertLiveRR($0) }
            if legacyLiveRRImported, try metadata("legacy_live_rr_preferences_imported") == nil {
                try setMetadata("legacy_live_rr_preferences_imported", value: "1")
            }
            try accompanyingWrites()
            try setMetadata("restore:" + token, value: "committed")
        }
    }

    private func insert(_ rows: [V18Sample]) throws -> CommitProgress {
        // Fast-path insert with conflict bypass: 99.9% of incoming sync records are new timestamps.
        // Inserting directly with ON CONFLICT DO NOTHING avoids redundant SELECT queries and
        // expensive JSON deserialization for every non-conflicting row.
        let tryInsert = try prepare("INSERT INTO history_sample (unix, payload) VALUES (?, ?) ON CONFLICT(unix) DO NOTHING")
        defer { sqlite3_finalize(tryInsert) }
        let lookup = try prepare("SELECT payload FROM history_sample WHERE unix = ?")
        defer { sqlite3_finalize(lookup) }
        let update = try prepare("UPDATE history_sample SET payload = ? WHERE unix = ?")
        defer { sqlite3_finalize(update) }
        var progress = CommitProgress()
        for row in rows {
            let data = try encoder.encode(row)
            sqlite3_reset(tryInsert); sqlite3_clear_bindings(tryInsert)
            sqlite3_bind_int64(tryInsert, 1, Int64(row.unix))
            bind(data, to: tryInsert, column: 2)
            guard sqlite3_step(tryInsert) == SQLITE_DONE else { throw failure() }
            if sqlite3_changes(db) > 0 {
                progress.changed += 1
                progress.newestInserted = max(progress.newestInserted ?? row.unix, row.unix)
                continue
            }
            // Conflict encountered: evaluate HistoricalRecordSelection preference
            sqlite3_reset(lookup); sqlite3_clear_bindings(lookup)
            sqlite3_bind_int64(lookup, 1, Int64(row.unix))
            let status = sqlite3_step(lookup)
            if status == SQLITE_ROW {
                if let old = try? decoder.decode(V18Sample.self, from: blob(lookup, column: 0)) {
                    if HistoricalRecordSelection.prefers(row, over: old) {
                        sqlite3_reset(update); sqlite3_clear_bindings(update)
                        bind(data, to: update, column: 1)
                        sqlite3_bind_int64(update, 2, Int64(row.unix))
                        guard sqlite3_step(update) == SQLITE_DONE else { throw failure() }
                        progress.changed += 1
                    }
                }
            } else if status != SQLITE_DONE {
                throw failure()
            }
        }
        return progress
    }
    func migrateLegacyLiveRR(_ samples: [LiveSample]) throws -> Int {
        try transaction {
            if try metadata("legacy_live_rr_preferences_imported") == nil {
                _ = try insertLiveRR(samples.map { try LiveRRRecord.legacy($0) })
                try setMetadata("legacy_live_rr_preferences_imported", value: "1")
            }
            return try liveRRCount()
        }
    }
    @discardableResult
    func commitLiveRR(_ rows: [LiveRRRecord]) throws -> Int {
        try transaction { try insertLiveRR(rows) }
    }
    func liveRRCount() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM live_rr_record")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw failure() }
        return Int(sqlite3_column_int64(statement, 0))
    }
    func liveRR(from start: Int, through end: Int) throws -> [LiveRRRecord] {
        let statement = try prepare("SELECT payload FROM live_rr_record WHERE unix BETWEEN ? AND ? ORDER BY unix, source_id")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(start)); sqlite3_bind_int64(statement, 2, Int64(end))
        var rows: [LiveRRRecord] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return rows }
            guard status == SQLITE_ROW else { throw failure() }
            rows.append(try decoder.decode(LiveRRRecord.self, from: blob(statement, column: 0)))
        }
    }
    private func insertLiveRR(_ rows: [LiveRRRecord]) throws -> Int {
        let statement = try prepare("INSERT OR IGNORE INTO live_rr_record(source_id, unix, payload) VALUES (?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        var changed = 0
        for row in rows {
            sqlite3_reset(statement); sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, row.id, -1, transient)
            sqlite3_bind_int64(statement, 2, Int64(row.sample.unix))
            bind(try encoder.encode(row), to: statement, column: 3)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
            changed += Int(sqlite3_changes(db))
        }
        return changed
    }

    private func readSamples(_ s: OpaquePointer) throws -> [V18Sample] {
        var rows: [V18Sample] = []
        while true {
            let status = sqlite3_step(s)
            if status == SQLITE_DONE { return rows }
            guard status == SQLITE_ROW else { throw failure() }
            rows.append(try decoder.decode(V18Sample.self, from: blob(s, column: 0)))
        }
    }
    private func setMetadata(_ key: String, value: String) throws {
        let s = try prepare("INSERT INTO history_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
        defer { sqlite3_finalize(s) }
        sqlite3_bind_text(s, 1, key, -1, transient); sqlite3_bind_text(s, 2, value, -1, transient)
        guard sqlite3_step(s) == SQLITE_DONE else { throw failure() }
    }
    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let result = try body(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func transactionWithBatchSize<T>(_ batchSize: Int, _ body: () throws -> T) throws -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        var contentionCount = 0
        let maxRetries = 3
        for attempt in 1...maxRetries {
            do {
                try execute("BEGIN IMMEDIATE")
                do { let result = try body(); try execute("COMMIT");
                    let latency = CFAbsoluteTimeGetCurrent() - startTime
                    PerformanceProfiler.shared.recordSQLiteTransaction(batchSize: batchSize, latency: latency, contentionCount: contentionCount)
                    return result }
                catch { try? execute("ROLLBACK"); throw error }
            } catch {
                if attempt < maxRetries {
                    contentionCount += 1
                    Thread.sleep(forTimeInterval: 0.01 * Double(attempt))
                    continue
                }
                let latency = CFAbsoluteTimeGetCurrent() - startTime
                PerformanceProfiler.shared.recordSQLiteTransaction(batchSize: batchSize, latency: latency, contentionCount: contentionCount)
                throw error
            }
        }
        throw failure()
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        return statement
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func blob(_ s: OpaquePointer, column: Int32) throws -> Data {
        guard let bytes = sqlite3_column_blob(s, column) else { throw Failure(message: "Empty history database record") }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(s, column)))
    }
    private func bind(_ data: Data, to s: OpaquePointer, column: Int32) {
        _ = data.withUnsafeBytes { sqlite3_bind_blob(s, column, $0.baseAddress, Int32($0.count), transient) }
    }
    private func failure() -> Failure {
        Failure(message: db.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open history database")
    }
}
