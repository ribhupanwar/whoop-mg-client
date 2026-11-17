import Foundation

/// Official workout source projection. It never enters the local activity
/// store or adds scores/calories to an existing band's daily totals.
struct WhoopActivityHistory: Identifiable {
    let id: String
    let original: WhoopCSVImport.SupplementalRecord
    let dateKey: String
    let name: String
    let startUnix: Int?
    let endUnix: Int?
    let strain: Double?
    let energyKcal: Double?
    static func make(_ records: [WhoopCSVImport.SupplementalRecord]) -> [WhoopActivityHistory] {
        records.compactMap { record in
            guard record.source == "workouts",
                  let date = WhoopImportedHistory.dateKey(record.fields["Workout start time"]) else { return nil }
            func number(_ key: String, range: ClosedRange<Double>) -> Double? {
                guard let raw = record.fields[key], let value = Double(raw), value.isFinite, range.contains(value) else { return nil }
                return value
            }
            let timezone = record.fields["Cycle timezone"]
            let start = WhoopImportedHistory.timestamp(record.fields["Workout start time"], timezone: timezone)
            let end = WhoopImportedHistory.timestamp(record.fields["Workout end time"], timezone: timezone)
            let validEnd: Int?
            if let start, let end, end >= start { validEnd = end } else { validEnd = nil }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            guard let bytes = try? encoder.encode(record) else { return nil }
            return WhoopActivityHistory(id: PersistenceDiagnostics.digest(bytes), original: record,
                dateKey: date, name: record.fields["Activity name"].flatMap { $0.isEmpty ? nil : $0 } ?? "WHOOP workout",
                startUnix: start, endUnix: validEnd,
                strain: number("Activity Strain", range: 0...21), energyKcal: number("Energy burned (cal)", range: 0...100_000))
        }.sorted { $0.dateKey == $1.dateKey ? $0.id < $1.id : $0.dateKey > $1.dateKey }
    }
}
