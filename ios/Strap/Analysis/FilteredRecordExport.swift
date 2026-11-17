import Foundation
import SQLite3

/// Streaming source-labelled record export. CSV carries original_json as a
/// quoted cell; JSON embeds the same original object without numeric rewriting.
enum FilteredRecordExport {
    struct Record {
        let source: String
        let id: String
        let unix: Double?
        let dateKey: String?
        let original: Data
        static func make<T: Encodable>(_ value: T, source: String, id: String,
                                        unix: Double? = nil, dateKey: String? = nil) throws -> Record {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            return Record(source: source, id: id, unix: unix, dateKey: dateKey, original: try encoder.encode(value))
        }
    }
    struct Result { let url: URL; let count: Int; let undated: Int }
    static func write(_ records: [Record], database: URL?, from: Date, until: Date,
                      calendar: Calendar, asCSV: Bool, destination: URL) throws -> Result {
        guard from < until else { throw PersistenceDiagnostics.Failure(message: "Export end must follow start.") }
        let fm = FileManager.default
        let url = destination.appendingPathComponent("STRAP-records-\(UUID().uuidString).\(asCSV ? "csv" : "json")")
        guard fm.createFile(atPath: url.path, contents: nil) else {
            throw PersistenceDiagnostics.Failure(message: "Cannot create export file.")
        }
        let handle = try FileHandle(forWritingTo: url)
        var finished = false
        defer { try? handle.close(); if !finished { try? fm.removeItem(at: url) } }
        var buffer = Data(); var count = 0; var undated = 0
        let encoder = JSONEncoder()
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        let firstDay = formatter.string(from: from)
        let lastDay = formatter.string(from: until.addingTimeInterval(-0.001))
        func append(_ data: Data) throws {
            buffer.append(data)
            if buffer.count >= 65536 { try handle.write(contentsOf: buffer); buffer.removeAll(keepingCapacity: true) }
        }
        func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        func emit(_ record: Record) throws {
            if let unix = record.unix {
                guard unix.isFinite, unix >= from.timeIntervalSince1970, unix < until.timeIntervalSince1970 else { return }
            } else if let day = record.dateKey {
                guard WhoopImportedHistory.dateKey(day) == day, day >= firstDay, day <= lastDay else { return }
            } else { undated += 1; return }
            guard (try JSONSerialization.jsonObject(with: record.original)) is [String: Any],
                  let original = String(data: record.original, encoding: .utf8) else {
                throw PersistenceDiagnostics.Failure(message: "Invalid source JSON; export cancelled without altering originals.")
            }
            if asCSV {
                let row = [record.source, record.id, record.unix.map { String($0) } ?? "", record.dateKey ?? "", original]
                try append(Data((row.map(quote).joined(separator: ",") + "\r\n").utf8))
            } else {
                if count > 0 { try append(Data(",".utf8)) }
                try append(Data("{\"source\":".utf8)); try append(encoder.encode(record.source))
                try append(Data(",\"id\":".utf8)); try append(encoder.encode(record.id))
                try append(Data(",\"unix\":".utf8)); try append(encoder.encode(record.unix))
                try append(Data(",\"dateKey\":".utf8)); try append(encoder.encode(record.dateKey))
                try append(Data(",\"original\":".utf8)); try append(record.original); try append(Data("}".utf8))
            }
            count += 1
        }
        try append(Data((asCSV ? "source,id,unix,date_key,original_json\r\n" : "{\"schemaVersion\":1,\"records\":[").utf8))
        for record in records { try emit(record) }
        if let database, fm.fileExists(atPath: database.path) {
            var db: OpaquePointer?
            guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                sqlite3_close(db); throw PersistenceDiagnostics.Failure(message: "Cannot read retained history.")
            }
            defer { sqlite3_close(db) }
            sqlite3_busy_timeout(db, 5000)
            guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else {
                throw PersistenceDiagnostics.Failure(message: "Cannot start consistent read-only history export.")
            }
            defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
            for (table, idColumn) in [("history_sample", "CAST(unix AS TEXT)"), ("live_rr_record", "source_id")] {
                var exists: OpaquePointer?
                let check = sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' AND name=?", -1, &exists, nil)
                guard check == SQLITE_OK else { throw PersistenceDiagnostics.Failure(message: "Cannot inspect history schema.") }
                defer { sqlite3_finalize(exists) }
                sqlite3_bind_text(exists, 1, (table as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                let existence = sqlite3_step(exists)
                if existence == SQLITE_DONE { continue }
                guard existence == SQLITE_ROW else { throw PersistenceDiagnostics.Failure(message: "Cannot inspect history table.") }
                var statement: OpaquePointer?
                let sql = "SELECT \(idColumn),unix,payload FROM \(table) WHERE unix>=? AND unix<? ORDER BY unix"
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw PersistenceDiagnostics.Failure(message: "Unsupported retained history schema.")
                }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_double(statement, 1, from.timeIntervalSince1970)
                sqlite3_bind_double(statement, 2, until.timeIntervalSince1970)
                while true {
                    let status = sqlite3_step(statement)
                    if status == SQLITE_DONE { break }
                    guard status == SQLITE_ROW, let identity = sqlite3_column_text(statement, 0),
                          let bytes = sqlite3_column_blob(statement, 2) else {
                        throw PersistenceDiagnostics.Failure(message: "Cannot read retained history row.")
                    }
                    try emit(Record(source: table, id: String(cString: identity), unix: sqlite3_column_double(statement, 1), dateKey: nil,
                        original: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 2)))))
                }
            }
        }
        if !asCSV { try append(Data("]}".utf8)) }
        try handle.write(contentsOf: buffer); try handle.synchronize(); try handle.close()
        finished = true
        return Result(url: url, count: count, undated: undated)
    }
}
