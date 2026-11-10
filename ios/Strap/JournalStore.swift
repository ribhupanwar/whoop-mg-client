import Foundation

/// UserDefaults-backed journal persistence. One entry per day; saving again
/// updates that day's entry. Tests inject a `suiteName`-based UserDefaults so
/// they never pollute the real journal.
final class JournalStore {
    private let defaults: UserDefaults
    private let storageKey = "strap.journal.entries.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Local-calendar day key, yyyy-MM-dd.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func load() -> [String: JournalEntry] {
        guard let data = defaults.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([String: JournalEntry].self, from: data) else {
            return [:]
        }
        return entries
    }

    func entry(forDayKey key: String) -> JournalEntry? {
        load()[key]
    }

    func entry(on date: Date) -> JournalEntry? {
        entry(forDayKey: Self.dayKey(for: date))
    }

    func allEntries() -> [JournalEntry] {
        Array(load().values)
    }

    /// Inserts or replaces the entry for its date — never creates duplicates.
    func save(_ entry: JournalEntry) {
        var entries = load()
        entries[entry.dateKey] = entry
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey)
        }
    }
}