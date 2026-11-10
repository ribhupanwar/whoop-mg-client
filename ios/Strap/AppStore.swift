import Foundation
import Combine

/// Single source of truth for the UI. Settings and journal persist to
/// UserDefaults; band state lives in `BandLink`, which persists its own
/// captures and per-day metrics.
final class AppStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            persistSettings()
            band.configure(sex: settings.sex, maxHR: maxHeartRate, needHours: settings.sleepNeedHours)
        }
    }
    @Published private(set) var journalEntries: [String: JournalEntry] = [:]

    let band = BandLink()
    let journal: JournalStore
    private let defaults: UserDefaults
    private let settingsKey = "strap.settings.v1"
    private var bandCancellable: AnyCancellable?

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
        band.configure(sex: settings.sex, maxHR: maxHeartRate, needHours: settings.sleepNeedHours)
        bandCancellable = band.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Design preview toggle. OFF (default) == live mode: em dashes only.
    var isPreview: Bool { settings.designPreview }

    var maxHeartRate: Double {
        settings.maxHROverride ?? Karvonen.agePredictedMaxHR(age: settings.age)
    }

    /// Detected nights from captured history. Empty until a capture lands, so
    /// sleep debt stays unknown instead of zero.
    var recordedNights: [RecordedNight] {
        band.days.compactMap { day in
            guard day.sleepHours > 0 else { return nil }
            return RecordedNight(
                dateKey: day.dateKey,
                neededHours: settings.sleepNeedHours,
                actualHours: day.sleepHours
            )
        }
    }

    func connectBand() {
        band.connect(
            sex: settings.sex, maxHR: maxHeartRate, needHours: settings.sleepNeedHours
        )
    }

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