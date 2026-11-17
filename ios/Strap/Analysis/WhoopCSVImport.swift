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
        let records = csvRecords(string)
        guard let headers = records.first else { throw ImportError.unsupportedColumns }
        func normalized(_ text: String) -> String {
            text.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let names = headers.map(normalized)
        func column(_ candidates: [String]) -> Int? {
            names.firstIndex(where: { candidates.contains($0) })
        }
        guard let date = column(["wakeonset", "cycleendtime", "cycleend"])
                ?? column(["date", "cycledate", "start", "cyclestart", "cyclestarttime", "cycle start", "starttime", "createdat"].map(normalized)),
              let hrv = column(["hrv", "hrvms", "rmssd", "rmssdms", "heartratevariability", "heartratevariabilityms", "heartratevariabilityrmssd", "heartratevariabilityrmssdms", "heartratevariabilityms", "heartratevariabilitymilliseconds"].map(normalized)),
              let rhr = column(["rhr", "restinghr", "restingheartrate", "restingheartratebpm", "restingheartratebeatsperminute"].map(normalized))
        else { throw ImportError.unsupportedColumns }
        let required = max(date, max(hrv, rhr))
        var rows: [String: Row] = [:]
        for record in records.dropFirst() where record.count > required {
            guard let key = dateKey(record[date]),
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
        let category = source.lowercased()
        guard ["physiological_cycles", "sleeps", "workouts", "journal_entries"].contains(category) else {
            throw ImportError.unsupportedColumns
        }
        let string = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16) ?? ""
        let records = csvRecords(string)
        guard let headers = records.first, !headers.isEmpty else {
            throw ImportError.unsupportedColumns
        }
        let rows = records.dropFirst().filter { !$0.isEmpty }.map { values in
            SupplementalRecord(source: category, fields: Dictionary(zip(headers, values).map { ($0.0, $0.1) },
                uniquingKeysWith: { _, latest in latest }))
        }
        guard !rows.isEmpty else { throw ImportError.noValidRows }
        let key = "strap.whoop.import." + category + ".v1"
        let added = try mergeSupplemental(rows, existing: defaults.data(forKey: key),
                                         fromDate: fromDate, throughDate: throughDate)
        defaults.set(added.data, forKey: key)
        return added.count
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
            if fromDate != nil || throughDate != nil {
                let date = row.fields.first { key, _ in
                    ["cyclestarttime", "sleeponset", "workoutstarttime", "date"].contains(
                        key.lowercased().filter { $0.isLetter || $0.isNumber })
                }.flatMap { dateKey($0.value) }
                guard let date, fromDate.map({ date >= $0 }) ?? true,
                      throughDate.map({ date <= $0 }) ?? true else { continue }
            }
            let identity = PersistenceDiagnostics.digest(try encoder.encode(row))
            if seen.insert(identity).inserted { records.append(row); added += 1 }
        }
        return (try encoder.encode(records), added)
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
    private static func csvRecords(_ text: String) -> [[String]] {
        var records: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
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
            } else if (c == "\n" || c == "\r") && !quoted {
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                row.append(field); field = ""
                if row.contains(where: { !$0.isEmpty }) { records.append(row) }
                row = []
            } else { field.append(c) }
            i += 1
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { records.append(row) }
        return records
    }
}
