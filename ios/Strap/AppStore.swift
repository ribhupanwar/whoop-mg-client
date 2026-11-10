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
    @Published private(set) var manualActivities: [ManualActivity] = []
    @Published private(set) var liveActivities: [LiveActivityRecord] = []

    let band = BandLink()
    let journal: JournalStore
    let activities: ActivityStore
    private let defaults: UserDefaults
    private let settingsKey = "strap.settings.v1"
    private var bandCancellable: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.journal = JournalStore(defaults: defaults)
        self.activities = ActivityStore(defaults: defaults)
        if let data = defaults.data(forKey: "strap.settings.v1"),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = saved
        } else {
            self.settings = AppSettings()
        }
        self.journalEntries = Dictionary(
            uniqueKeysWithValues: journal.allEntries().map { ($0.dateKey, $0) }
        )
        self.manualActivities = activities.manualActivities()
        self.liveActivities = activities.liveActivities()
        band.configure(sex: settings.sex, maxHR: maxHeartRate, needHours: settings.sleepNeedHours)
        bandCancellable = band.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Design preview toggle. OFF (default) == live mode: measured values where
    /// a capture supports them, an em dash where it does not.
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

    // MARK: - Activities

    /// Karvonen zones for a live session: resting HR comes from the override or
    /// the last measured resting value; max HR is never invented beyond the
    /// documented age estimate.
    var liveZones: [HRZone]? {
        guard let resting = settings.restingHROverride ?? band.summary?.restingHeartRate,
              let zones = Karvonen.zones(restingHR: resting, maxHR: maxHeartRate) else {
            return nil
        }
        return zones
    }

    func addActivity(_ activity: ManualActivity) {
        activities.save(activity)
        manualActivities = activities.manualActivities()
    }

    func deleteActivity(id: UUID) {
        activities.deleteManual(id: id)
        manualActivities = activities.manualActivities()
    }

    func addLiveSession(_ record: LiveActivityRecord) {
        activities.saveLive(record)
        liveActivities = activities.liveActivities()
    }

    func manualActivities(on dateKey: String) -> [ManualActivity] {
        manualActivities.filter { $0.dateKey == dateKey }
    }

    func liveActivities(on dateKey: String) -> [LiveActivityRecord] {
        liveActivities.filter { $0.dateKey == dateKey }
    }

    /// Band-detected sessions for a local day, from the most recent capture.
    func detectedActivities(on dateKey: String) -> [ActivitySession] {
        (band.summary?.activities ?? []).filter {
            JournalStore.dayKey(for: Date(timeIntervalSince1970: TimeInterval($0.startUnix)))
                == dateKey
        }
    }

    // MARK: - Measured values shared by the health screens

    var lastCapture: CaptureSummary? { band.summary }

    /// Resting HR from the user's override, else the last measured quiet window.
    var measuredRestingHR: Double? {
        settings.restingHROverride ?? band.summary?.restingHeartRate
    }

    var recordedDayCount: Int { band.days.count }

    var hasRecoveryBaseline: Bool {
        (band.baseline?.days ?? 0) >= Recovery.minBaselineDays
    }

    /// Uth 2004 (15.3 × HRmax / HRrest). Only when a measured max HR override
    /// exists — the age formula alone is too weak to publish as a number.
    var vo2Estimate: Double? {
        guard let maxHR = settings.maxHROverride, let resting = measuredRestingHR,
              resting > 0, maxHR > resting else { return nil }
        return 15.3 * maxHR / resting
    }

    /// Minutes in Z1–Z3 (low) or Z4–Z5 (high) over the last seven days of
    /// measured live sessions. nil when no zone-timed session exists.
    func weeklyZoneMinutes(high: Bool) -> Double? {
        let cutoff = Int(Date().timeIntervalSince1970) - 7 * 86_400
        let records = liveActivities.filter { $0.startedUnix >= cutoff && !$0.zoneSeconds.isEmpty }
        guard !records.isEmpty else { return nil }
        let seconds = records.reduce(0) { total, record in
            let slice = high ? record.zoneSeconds.dropFirst(3) : record.zoneSeconds.prefix(3)
            return total + slice.reduce(0, +)
        }
        return Double(seconds) / 60.0
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