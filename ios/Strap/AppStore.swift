import Foundation
import Combine

/// Single source of truth for the UI. Settings and journal persist to
/// UserDefaults. No BLE in this chunk: `recordedNights` stays empty in live
/// mode, so every unmeasured metric renders "—" and debt stays unknown.
final class AppStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persistSettings() }
    }
    @Published private(set) var journalEntries: [String: JournalEntry] = [:]
    /// Overnight captures will populate this in the BLE chunk. Empty until then.
    @Published var recordedNights: [RecordedNight] = []

    let journal: JournalStore
    private let defaults: UserDefaults
    private let settingsKey = "strap.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.journal = JournalStore(defaults: defaults)
        if let data = defaults.data(forKey: "strap.settings.v1"),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = saved
        } else {
            self.settings = AppSettings()
        }
        self.journalEntries = Dictionary(
            uniqueKeysWithValues: journal.allEntries().map { ($0.dateKey, $0) }
        )
    }

    /// Design preview toggle. OFF (default) == live mode: em dashes only.
    var isPreview: Bool { settings.designPreview }

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    func saveJournal(_ entry: JournalEntry) {
        journal.save(entry)
        journalEntries = Dictionary(
            uniqueKeysWithValues: journal.allEntries().map { ($0.dateKey, $0) }
        )
    }

    func todayEntry() -> JournalEntry? {
        journalEntries[JournalStore.dayKey(for: Date())]
    }
}