import Foundation

/// Local WHOOP CSV import. Imports only identifiable, dated HRV/RHR readings;
/// never fabricates a baseline from recovery scores or missing fields.
enum WhoopCSVImport {
    struct Row {
        let dateKey: String
        let hrvMS: Double
        let restingHR: Double
    }

    enum ImportError: LocalizedError {
        case unsupportedColumns
        case noValidRows
        var errorDescription: String? {
            switch self {
            case .unsupportedColumns: return "CSV needs date, HRV (RMSSD ms), and resting heart rate columns."
            case .noValidRows: return "No rows with a valid date, HRV and resting HR were found."
            }
        }
    }

    static func parse(_ data: Data) throws -> [Row] {
        let string = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? ""
        let records = try csvRecords(string)
        guard let headers = records.first else { throw ImportError.unsupportedColumns }
        func normalized(_ text: String) -> String {
            text.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let names = headers.map(normalized)
        func column(_ candidates: [String]) -> Int? {
            names.firstIndex(where: { candidates.contains($0) })
        }
        // A wake column may exist but be empty for an awake-only cycle.
        // Resolve dates per row, preserving the usual wake-date precedence.
        let dateColumns = [
            column(["wakeonset"]),
            column(["date", "cycledate", "start", "cyclestart", "cyclestarttime", "cycle start", "starttime", "createdat"].map(normalized)),
            column(["cycleendtime", "cycleend"])
        ].compactMap { $0 }
        guard !dateColumns.isEmpty,
              let hrv = column(["hrv", "hrvms", "rmssd", "rmssdms", "heartratevariability", "heartratevariabilityms", "heartratevariabilityrmssd", "heartratevariabilityrmssdms", "heartratevariabilityms", "heartratevariabilitymilliseconds"].map(normalized)),
              let rhr = column(["rhr", "restinghr", "restingheartrate", "restingheartratebpm", "restingheartratebeatsperminute"].map(normalized))
        else { throw ImportError.unsupportedColumns }
        let required = max(hrv, rhr)
        var rows: [String: Row] = [:]
        for record in records.dropFirst() where record.count > required {
            let key = dateColumns.lazy.compactMap { index in
                record.indices.contains(index) ? dateKey(record[index]) : nil
            }.first
            guard let key,
                  let h = Double(record[hrv].trimmingCharacters(in: .whitespaces)),
                  let r = Double(record[rhr].trimmingCharacters(in: .whitespaces)),
                  h.isFinite, r.isFinite, (5...300).contains(h), (30...130).contains(r)
            else { continue }
            rows[key] = Row(dateKey: key, hrvMS: h, restingHR: r)
        }
        guard !rows.isEmpty else { throw ImportError.noValidRows }
        return rows.values.sorted { $0.dateKey < $1.dateKey }
    }

    /// Preserves the complete exported sleep, workout and journal rows locally.
    /// These are source records, not band-measured sessions or Recovery inputs.
    struct SupplementalRecord: Codable, Equatable {
        let source: String
        let fields: [String: String]
    }

    static func importSupplemental(_ data: Data, source: String,
                                   defaults: UserDefaults = .standard,
                                   fromDate: String? = nil, throughDate: String? = nil) throws -> Int {
        let rows = try parseSupplemental(data, source: source)
        let old = try loadSources(defaults: defaults)
        let key = source.lowercased()
        let encoder = JSONEncoder()
        let merged = try mergeSupplemental(rows, existing: old[key].map { try encoder.encode($0) },
                                          fromDate: fromDate, throughDate: throughDate)
        var updated = old
        updated[key] = try JSONDecoder().decode([SupplementalRecord].self, from: merged.data)
        try saveSources(updated, defaults: defaults)
        return merged.count
    }

    static let sourceCategories = ["physiological_cycles", "sleeps", "workouts", "journal_entries"]
    static let bundleKey = "strap.whoop.import.bundle.v1"

    static func loadSources(defaults: UserDefaults = .standard) throws -> [String: [SupplementalRecord]] {
        var result: [String: [SupplementalRecord]] = [:]
        if let data = defaults.data(forKey: bundleKey) {
            result = try JSONDecoder().decode([String: [SupplementalRecord]].self, from: data)
        }
        for category in sourceCategories where result[category] == nil {
            if let data = defaults.data(forKey: "strap.whoop.import." + category + ".v1") {
                result[category] = try JSONDecoder().decode([SupplementalRecord].self, from: data)
            }
        }
        return result
    }

    static func saveSources(_ sources: [String: [SupplementalRecord]], defaults: UserDefaults = .standard) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // A whole batch becomes visible through one preference value. Keep the
        // original legacy keys intact for recovery and older export evidence.
        let data = try encoder.encode(sources)
        defaults.set(data, forKey: bundleKey)
    }

    static func parseSupplemental(_ data: Data, source: String) throws -> [SupplementalRecord] {
        let category = source.lowercased()
        guard sourceCategories.contains(category) else { throw ImportError.unsupportedColumns }
        let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
        let records = try csvRecords(string)
        guard let headers = records.first, !headers.isEmpty,
              Set(headers).count == headers.count,
              headers.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              records.dropFirst().allSatisfy({ $0.count <= headers.count }) else { throw ImportError.unsupportedColumns }
        let rows = records.dropFirst().map { values in
            SupplementalRecord(source: category, fields: Dictionary(zip(headers, values), uniquingKeysWith: { _, last in last }))
        }
        // An empty category in a valid four-file export is header-only.
        // Keep its schema validation, but do not reject the whole archive.
        return rows
    }

    /// Stable content identity preserves original columns/timestamps and conflicting
    /// source revisions. Repeated or overlapping exports never replace prior files.
    static func mergeSupplemental(_ incoming: [SupplementalRecord], existing: Data?,
                                  fromDate: String? = nil, throughDate: String? = nil) throws -> (data: Data, count: Int) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // An incompatible existing import is evidence, not an empty collection.
        var records = try existing.map { try JSONDecoder().decode([SupplementalRecord].self, from: $0) } ?? []
        var seen = Set(try records.map { PersistenceDiagnostics.digest(try encoder.encode($0)) })
        var added = 0
        for row in incoming {
            guard inRange(row, fromDate: fromDate, throughDate: throughDate) else { continue }
            let identity = PersistenceDiagnostics.digest(try encoder.encode(row))
            if seen.insert(identity).inserted { records.append(row); added += 1 }
        }
        return (try encoder.encode(records), added)
    }

    static func inRange(_ row: SupplementalRecord, fromDate: String?, throughDate: String?) -> Bool {
        if fromDate == nil && throughDate == nil { return true }
                let candidates = row.source == "sleeps" ? ["sleeponset", "cyclestarttime", "date"] :
                    (row.source == "workouts" ? ["workoutstarttime", "cyclestarttime", "date"] : ["cyclestarttime", "date"])
                let date = candidates.lazy.compactMap { wanted in
                    row.fields.first { key, _ in key.lowercased().filter { $0.isLetter || $0.isNumber } == wanted }
                        .flatMap { dateKey($0.value) }
                }.first
                guard let date else { return false }
                return (fromDate.map { date >= $0 } ?? true) && (throughDate.map { date <= $0 } ?? true)
    }

    private static func dateKey(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(value.prefix(10))
        if prefix.count == 10 && prefix[prefix.index(prefix.startIndex, offsetBy: 4)] == "-" &&
            prefix[prefix.index(prefix.startIndex, offsetBy: 7)] == "-" {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.isLenient = false
            guard f.date(from: prefix) != nil else { return nil }
            return prefix
        }
        for pattern in ["MM/dd/yyyy", "dd/MM/yyyy"] {
            let f = DateFormatter()
            f.dateFormat = pattern
            f.isLenient = false
            if let date = f.date(from: value) {
                let output = DateFormatter()
                output.dateFormat = "yyyy-MM-dd"
                return output.string(from: date)
            }
        }
        return nil
    }

    /// RFC4180-style quoted fields and embedded line breaks.
    private static func csvRecords(_ text: String) throws -> [[String]] {
        var records: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        // Swift represents CRLF as one Character. Recognize it explicitly
        // while preserving embedded CRLF inside quoted source notes.
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" {
                    field.append("\""); i += 1
                } else { quoted.toggle() }
            } else if c == "," && !quoted {
                row.append(field); field = ""
            } else if (c == "\n" || c == "\r" || c == "\r\n") && !quoted {
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                row.append(field); field = ""
                if row.contains(where: { !$0.isEmpty }) { records.append(row) }
                row = []
            } else { field.append(c) }
            i += 1
        }
        guard !quoted else { throw ImportError.unsupportedColumns }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { records.append(row) }
        return records
    }
}
