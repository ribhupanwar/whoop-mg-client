import Foundation

/// Source-only export. Never manufactures band measurements or changes retained rows.
enum WhoopSourceExport {
    struct Selection {
        let records: [WhoopCSVImport.SupplementalRecord]
        let undated: Int
    }
    static func select(_ sources: [String: [WhoopCSVImport.SupplementalRecord]],
                       from: String?, through: String?) -> Selection {
        let dates = WhoopSourceDates(sources: sources)
        var selected: [WhoopCSVImport.SupplementalRecord] = []; var undated = 0
        for category in sources.keys.sorted() {
            for record in sources[category] ?? [] {
                guard let date = dates.dateKey(for: record) else {
                    undated += 1
                    if from == nil && through == nil { selected.append(record) }
                    continue
                }
                if (from.map { date >= $0 } ?? true) && (through.map { date <= $0 } ?? true) {
                    selected.append(record)
                }
            }
        }
        return Selection(records: selected, undated: undated)
    }
    static func json(_ records: [WhoopCSVImport.SupplementalRecord]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records)
    }
    static func csv(_ records: [WhoopCSVImport.SupplementalRecord]) -> Data {
        let headers = Set(records.flatMap { $0.fields.keys }).sorted()
        func quoted(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        // Separate provenance column; even an original field called source remains intact.
        var provenance = "STRAP export source category"
        while headers.contains(provenance) { provenance += " #" }
        let rows = [[provenance] + headers] + records.map { record in
            [record.source] + headers.map { record.fields[$0] ?? "" }
        }
        return Data((rows.map { $0.map(quoted).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n").utf8)
    }
}
