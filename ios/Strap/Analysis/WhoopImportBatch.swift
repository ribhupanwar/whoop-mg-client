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
        var context = existing
        for (category, records) in grouped { context[category, default: []].append(contentsOf: records) }
        let dates = WhoopSourceDates(sources: context)
        var sources = existing
        var results: [CategoryResult] = []
        let encoder = JSONEncoder()
        for category in WhoopCSVImport.sourceCategories {
            guard let rows = grouped[category] else { continue }
            let filtered = rows.filter { dates.includes($0, from: fromDate, through: throughDate) }
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
