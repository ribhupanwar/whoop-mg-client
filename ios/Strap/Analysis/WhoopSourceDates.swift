import Foundation

/// One source-calendar policy for import, charts, journal and reports. Never
/// adds a day or converts an original wall-clock date into the phone timezone.
struct WhoopSourceDates {
    private struct Cycle: Hashable { let start: String; let timezone: String? }
    private var cycleWakeDates: [Cycle: Set<String>] = [:]
    private let formatter: DateFormatter
    init(sources: [String: [WhoopCSVImport.SupplementalRecord]]) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        formatter = f
        for record in sources["physiological_cycles"] ?? [] {
            guard let start = Self.field(record, "Cycle start time"),
                  let wake = day(Self.field(record, "Wake onset")) else { continue }
            cycleWakeDates[Cycle(start: start, timezone: Self.field(record, "Cycle timezone")), default: []].insert(wake)
        }
    }
    static func field(_ record: WhoopCSVImport.SupplementalRecord, _ name: String) -> String? {
        let wanted = WhoopImportedHistory.normalized(name)
        return record.fields.first { WhoopImportedHistory.normalized($0.key) == wanted }?.value
    }
    private func day(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = String(text.prefix(10))
        formatter.dateFormat = "yyyy-MM-dd"
        if key.count == 10, let parsed = formatter.date(from: key), formatter.string(from: parsed) == key { return key }
        // Retain existing generic CSV date compatibility, without changing raw fields.
        for pattern in ["MM/dd/yyyy", "dd/MM/yyyy"] {
            formatter.dateFormat = pattern
            if let parsed = formatter.date(from: text) {
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.string(from: parsed)
            }
        }
        return nil
    }

    private func linkedWake(_ record: WhoopCSVImport.SupplementalRecord) -> String? {
        guard let start = Self.field(record, "Cycle start time"),
              let dates = cycleWakeDates[Cycle(start: start, timezone: Self.field(record, "Cycle timezone"))],
              dates.count == 1 else { return nil }
        return dates.first // Unique original wake date; conflicting revisions never guess.
    }
    func dateKey(for record: WhoopCSVImport.SupplementalRecord) -> String? {
        if record.source == "physiological_cycles" || record.source == "sleeps" {
            return day(Self.field(record, "Wake onset")) ?? linkedWake(record)
                ?? day(Self.field(record, "Cycle start time")) ?? day(Self.field(record, "Sleep onset"))
                ?? day(Self.field(record, "Date"))
        }
        if record.source == "workouts" {
            return day(Self.field(record, "Workout start time")) ?? day(Self.field(record, "Date"))
        }
        if record.source == "journal_entries", let wake = linkedWake(record) { return wake }
        return day(Self.field(record, "Cycle start time")) ?? day(Self.field(record, "Date"))
    }
    func includes(_ record: WhoopCSVImport.SupplementalRecord, from: String?, through: String?) -> Bool {
        if from == nil && through == nil { return true }
        guard let key = dateKey(for: record) else { return false }
        return (from.map { key >= $0 } ?? true) && (through.map { key <= $0 } ?? true)
    }
}
