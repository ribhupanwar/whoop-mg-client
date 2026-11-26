import Foundation
import ZIPFoundation

/// Parse the complete archive before mutating any persisted import records.
enum WhoopImportBatch {
    struct CategoryResult {
        let category: String
        let found: Int
        let added: Int
        let saved: Int
        let outsideRange: Int
        var alreadySaved: Int { found - added - outsideRange }
    }
    struct Plan {
        let sources: [String: [WhoopCSVImport.SupplementalRecord]]
        let categories: [CategoryResult]
        let biometricRows: [WhoopCSVImport.Row]
        let csvFiles: Int
        let unsupportedFiles: [String]
        var found: Int { categories.reduce(0) { $0 + $1.found } }
        var added: Int { categories.reduce(0) { $0 + $1.added } }
        var existing: Int { categories.reduce(0) { $0 + $1.alreadySaved } }
        var outsideRange: Int { categories.reduce(0) { $0 + $1.outsideRange } }
        func summary(updatedDays: Int) -> String {
            let detail = categories.map { "\($0.category): \($0.found) found, \($0.added) new, \($0.saved) saved" }.joined(separator: " · ")
            let repeatMessage = added == 0 && existing > 0 ? " Already imported — no duplicates added." : ""
            let filtered = outsideRange > 0 ? " \(outsideRange) rows outside selected dates." : ""
            let unsupported = unsupportedFiles.isEmpty ? "" : " Unsupported CSV files: " + unsupportedFiles.joined(separator: ", ")
            return "\(csvFiles) CSV files · \(found) source rows found · \(added) new · \(existing) already saved.\(repeatMessage)\(filtered) \(detail). \(biometricRows.count) eligible HRV/RHR days; \(updatedDays) updated, existing measured values preserved.\(unsupported)"
        }
        func commit(defaults: UserDefaults = .standard) throws {
            var current = try WhoopCSVImport.loadSources(defaults: defaults)
            let encoder = JSONEncoder()
            for (category, rows) in sources {
                let merged = try WhoopCSVImport.mergeSupplemental(rows, existing: current[category].map { try encoder.encode($0) })
                current[category] = try JSONDecoder().decode([WhoopCSVImport.SupplementalRecord].self, from: merged.data)
            }
            try WhoopCSVImport.saveSources(current, defaults: defaults)
        }
    }
    static func category(_ name: String) -> String? {
        let name = (name as NSString).lastPathComponent.lowercased()
        if name.contains("journal") { return "journal_entries" }
        if name.contains("workout") { return "workouts" }
        if name.contains("sleep") { return "sleeps" }
        if name.contains("physiological") || name.contains("cycle") { return "physiological_cycles" }
        return nil
    }
    static func prepare(_ url: URL, defaults: UserDefaults = .standard,
                        fromDate: String? = nil, throughDate: String? = nil) throws -> Plan {
        var inputs: [(String, Data)] = []
        var unsupported: [String] = []
        if url.pathExtension.lowercased() == "zip" {
            let archive = try Archive(url: url, accessMode: .read)
            var total = 0
            for entry in archive where entry.type == .file && entry.path.lowercased().hasSuffix(".csv") {
                guard inputs.count + unsupported.count < 1000 else { throw WhoopImportSafetyError.extractionLimit }
                guard entry.uncompressedSize <= 50_000_000,
                      UInt64(total) + UInt64(entry.uncompressedSize) <= 100_000_000 else { throw WhoopImportSafetyError.extractionLimit }
                total += Int(entry.uncompressedSize)
                guard let category = category(entry.path) else { unsupported.append((entry.path as NSString).lastPathComponent); continue }
                var data = Data()
                _ = try archive.extract(entry) { chunk in
                    guard data.count <= Int(entry.uncompressedSize) - chunk.count else { throw WhoopImportSafetyError.extractionLimit }
                    data.append(chunk)
                }
                guard data.count == Int(entry.uncompressedSize) else { throw WhoopImportSafetyError.extractionLimit }
                inputs.append((category, data))
            }
        } else {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 50_000_000 else { throw WhoopImportSafetyError.extractionLimit }
            inputs.append((category(url.lastPathComponent) ?? "physiological_cycles", try Data(contentsOf: url)))
        }
        return try prepare(inputs, existing: WhoopCSVImport.loadSources(defaults: defaults),
                           unsupported: unsupported, fromDate: fromDate, throughDate: throughDate)
    }
    static func prepare(_ inputs: [(String, Data)], existing: [String: [WhoopCSVImport.SupplementalRecord]],
                        unsupported: [String] = [], fromDate: String? = nil, throughDate: String? = nil) throws -> Plan {
        guard !inputs.isEmpty else { throw WhoopCSVImport.ImportError.noValidRows }
        var grouped: [String: [WhoopCSVImport.SupplementalRecord]] = [:]
        var biometrics: [String: WhoopCSVImport.Row] = [:]
        for (category, data) in inputs {
            grouped[category, default: []].append(contentsOf: try WhoopCSVImport.parseSupplemental(data, source: category))
            if category == "physiological_cycles" {
                do {
                    for row in try WhoopCSVImport.parse(data) where
                        (fromDate.map { row.dateKey >= $0 } ?? true) && (throughDate.map { row.dateKey <= $0 } ?? true) {
                        biometrics[row.dateKey] = row
                    }
                } catch WhoopCSVImport.ImportError.noValidRows { /* Partial cycles still retain source fields. */ }
                  catch WhoopCSVImport.ImportError.unsupportedColumns { /* Source columns remain readable without biometrics. */ }
            }
        }
        var sources = existing
        var results: [CategoryResult] = []
        let encoder = JSONEncoder()
        for category in WhoopCSVImport.sourceCategories {
            guard let rows = grouped[category] else { continue }
            let filtered = rows.filter { WhoopCSVImport.inRange($0, fromDate: fromDate, throughDate: throughDate) }
            let merged = try WhoopCSVImport.mergeSupplemental(filtered, existing: sources[category].map { try encoder.encode($0) })
            let saved = try JSONDecoder().decode([WhoopCSVImport.SupplementalRecord].self, from: merged.data)
            sources[category] = saved
            results.append(CategoryResult(category: category, found: rows.count, added: merged.count,
                saved: saved.count, outsideRange: rows.count - filtered.count))
        }
        return Plan(sources: sources, categories: results, biometricRows: biometrics.values.sorted { $0.dateKey < $1.dateKey },
                    csvFiles: inputs.count, unsupportedFiles: unsupported)
    }
}


/// Compact, portable summary archive. Not a raw-sensor or database backup.
/// Imported WHOOP values are not promoted to local measurements.
enum StrapFourCSVExport {
    static func csv(_ header: [String], rows: [[String]]) -> Data {
        func quote(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let records = ([header] + rows).map { $0.map(quote).joined(separator: ",") }
        return Data((records.joined(separator: "\r\n") + "\r\n").utf8)
    }

    static func files(days: [DayMetrics], detected: [ActivitySession],
                      live: [LiveActivityRecord], manual: [ManualActivity],
                      journal: [JournalEntry]) -> [(String, Data)] {
        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(secondsFromGMT: 0)
        func time(_ unix: Int?) -> String {
            guard let unix else { return "" }
            return iso.string(from: Date(timeIntervalSince1970: Double(unix)))
        }
        func number(_ value: Double?) -> String {
            guard let value, value.isFinite else { return "" }
            return String(value)
        }
        let localDays = days.filter { $0.state != "imported" && $0.state != "whoop-imported" }
            .sorted { $0.dateKey < $1.dateKey }
        let cycleHeader = ["Cycle start time", "Cycle timezone", "Resting heart rate (bpm)",
            "Heart rate variability (ms)", "Day Strain", "Sleep onset", "Wake onset",
            "Asleep duration (min)", "Sleep performance %", "Respiratory rate (rpm)", "Source"]
        let cycleRows = localDays.map { day -> [String] in
            [day.dateKey, "UTC+00:00",
             number((day.restingHRWindowSeconds ?? 0) > 0 ? day.restingHR : nil),
             number(day.hrvWindowSeconds > 0 ? day.lnRMSSD.map { exp($0) } : nil),
             number(day.strain), time(day.sleepStartUnix), time(day.sleepEndUnix.map { $0 + 1 }),
             number(day.reliableSleepHours.map { $0 * 60 }), number(day.sleepPerformancePct),
             number((day.respiratoryWindows ?? 0) > 0 ? day.respiratoryRate : nil), "STRAP"]
        }
        let sleepHeader = ["Cycle start time", "Cycle timezone", "Sleep onset", "Wake onset",
                           "Asleep duration (min)", "Sleep performance %", "Source"]
        let sleepRows = localDays.compactMap { day -> [String]? in
            guard let start = day.sleepStartUnix, let end = day.sleepEndUnix, end >= start else { return nil }
            return [day.dateKey, "UTC+00:00", time(start), time(end + 1),
                    number(day.reliableSleepHours.map { $0 * 60 }), number(day.sleepPerformancePct), "STRAP"]
        }
        let workoutHeader = ["Cycle start time", "Cycle timezone", "Workout start time", "Workout end time",
                             "Activity name", "Duration (min)", "Activity Strain", "Average heart rate (bpm)", "Source", "Record ID"]
        var workoutRows: [[String]] = detected.map { row in
            let start = time(row.startUnix)
            return [String(start.prefix(10)), "UTC+00:00", start, time(row.endUnix + 1),
                    row.kind, number(row.minutes), number(row.strain), number(row.meanHR),
                    "STRAP detected", String(row.startUnix)]
        }
        workoutRows += live.map { row in
            [row.dateKey, "UTC+00:00", time(row.startedUnix), time(row.endedUnix), "Live HR",
             number(row.minutes), "", number(row.meanHR), "STRAP live", row.id.uuidString]
        }
        workoutRows += manual.map { row in
            [row.dateKey, "", "", "", row.name, String(row.minutes), "", "", "STRAP manual", row.id.uuidString]
        }
        let journalHeader = ["Cycle start time", "Question text", "Answered yes", "Mood", "Soreness", "Notes", "Source"]
        var journalRows: [[String]] = []
        for entry in journal.sorted(by: { $0.dateKey < $1.dateKey }) {
            let keys = entry.answers.keys.sorted()
            for key in keys.isEmpty ? [""] : keys {
                journalRows.append([entry.dateKey, key, entry.answers[key].map { $0 ? "true" : "false" } ?? "",
                                    entry.mood?.rawValue ?? "", entry.soreness.rawValue, entry.notes, "STRAP"])
            }
        }
        func stable(_ rows: [[String]]) -> [[String]] {
            var seen = Set<[String]>()
            return rows.filter { seen.insert($0).inserted }.sorted { $0.lexicographicallyPrecedes($1) }
        }
        return [("physiological_cycles.csv", csv(cycleHeader, rows: stable(cycleRows))),
                ("sleeps.csv", csv(sleepHeader, rows: stable(sleepRows))),
                ("workouts.csv", csv(workoutHeader, rows: stable(workoutRows))),
                ("journal_entries.csv", csv(journalHeader, rows: stable(journalRows)))]
    }

    static func write(_ files: [(String, Data)]) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("STRAP-data.zip")
        do {
            let archive = try Archive(url: url, accessMode: .create)
            for (name, data) in files {
                let source = root.appendingPathComponent(name)
                try data.write(to: source, options: .atomic)
                try archive.addEntry(with: name, relativeTo: root, compressionMethod: .deflate)
                try fm.removeItem(at: source)
            }
            return url
        } catch {
            try? fm.removeItem(at: root)
            throw error
        }
    }
}
