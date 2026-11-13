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
    /// Band-detected sessions, kept across syncs so a walk logged yesterday
    /// still shows on yesterday's screen.
    @Published private(set) var detectedBandActivities: [ActivitySession] = []

    let band = BandLink()
    /// Optional Apple Health export. OFF until the toggle in Settings asks.
    let health = HealthKitBridge()
    let journal: JournalStore
    let activities: ActivityStore
    private let defaults: UserDefaults
    private let settingsKey = "strap.settings.v1"
    private var bandCancellable: AnyCancellable?
    private var summaryCancellable: AnyCancellable?
    private var healthCancellable: AnyCancellable?

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
        self.detectedBandActivities = activities.detectedActivities()
        band.configure(sex: settings.sex, maxHR: maxHeartRate, needHours: settings.sleepNeedHours)
        bandCancellable = band.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // @Published fires in willSet, so listen to the projected value to see
        // the new summary rather than the previous one.
        summaryCancellable = band.$summary.sink { [weak self] fresh in
            self?.syncDetectedActivities(fresh)
        }
        healthCancellable = health.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        if settings.healthKitEnabled {
            Task { [weak self] in
                await self?.activateHealthKit(exportBacklog: true)
            }
        }
    }

    /// A drain can report the same session twice; the store merges overlaps,
    /// and the published list only changes when something new arrived.
    private func syncDetectedActivities(_ fresh: CaptureSummary?) {
        guard let sessions = fresh?.activities, !sessions.isEmpty else { return }
        // The same workout may be re-detected with a slightly shifted start
        // or a longer duration. Always merge overlaps, not just start seconds.
        activities.mergeDetected(sessions)
        detectedBandActivities = activities.detectedActivities()
        if settings.healthKitEnabled, health.state.isOn {
            let merged = detectedBandActivities
            Task { [weak self] in
                await self?.health.export(merged)
            }
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
            guard !band.isAnalyzingHistory, day.sleepDurationReliable == true,
                  day.sleepHours.isFinite, day.sleepHours >= 0 else { return nil }
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
        if settings.healthKitEnabled, health.state.isOn {
            Task { [weak self] in
                await self?.health.export(live: record)
            }
        }
    }

    // MARK: - Dashboard layout

    /// What Home and Dashboard render, in the saved order. Hiding a row never
    /// removes it from `dashboardOrder`, so unhiding restores its position.
    var visibleDashboardRows: [DashboardRow] {
        settings.dashboardOrder.filter { !settings.hiddenDashboardRows.contains($0) }
    }

    func isDashboardRowHidden(_ row: DashboardRow) -> Bool {
        settings.hiddenDashboardRows.contains(row)
    }

    func setDashboardRow(_ row: DashboardRow, hidden: Bool) {
        var hiddenRows = settings.hiddenDashboardRows.filter { $0 != row }
        if hidden { hiddenRows.append(row) }
        settings.hiddenDashboardRows = hiddenRows
    }

    /// Moves a row one slot at a time within the FULL order, so a step across a
    /// hidden neighbour lands where the wearer pointed rather than being
    /// swallowed by it.
    func moveDashboardRow(_ row: DashboardRow, by offset: Int) {
        guard let from = settings.dashboardOrder.firstIndex(of: row) else { return }
        let to = from + offset
        guard settings.dashboardOrder.indices.contains(to) else { return }
        settings.dashboardOrder.swapAt(from, to)
    }

    func resetDashboardLayout() {
        settings.dashboardOrder = DashboardRow.allCases
        settings.hiddenDashboardRows = []
    }

    // MARK: - Apple Health

    /// The toggle is the only entry point: it requests permission, then
    /// exports anything already logged so nothing measured is lost.
    func setHealthKit(_ enabled: Bool) {
        settings.healthKitEnabled = enabled
        if enabled {
            Task { [weak self] in
                await self?.activateHealthKit(exportBacklog: true)
            }
        } else {
            Task { [weak self] in
                await self?.health.deactivate()
            }
        }
    }

    var healthKitStatus: String { health.state.text }

    private func activateHealthKit(exportBacklog: Bool) async {
        await health.activate()
        guard health.state.isOn, exportBacklog else { return }
        await health.export(detectedBandActivities)
        for record in liveActivities {
            await health.export(live: record)
        }
    }

    func manualActivities(on dateKey: String) -> [ManualActivity] {
        manualActivities.filter { $0.dateKey == dateKey }
    }

    func liveActivities(on dateKey: String) -> [LiveActivityRecord] {
        liveActivities.filter { $0.dateKey == dateKey }
    }

    /// Band-detected sessions for a local day. Merges the persisted log with
    /// the latest capture so a session appears the moment a drain lands.
    func detectedActivities(on dateKey: String) -> [ActivitySession] {
        var seen = Set<Int>()
        let merged = (band.summary?.activities ?? []) + detectedBandActivities
        return merged
            .filter { JournalStore.dayKey(for: Date(timeIntervalSince1970: TimeInterval($0.startUnix))) == dateKey }
            .filter { seen.insert($0.startUnix).inserted }
            .sorted { $0.startUnix < $1.startUnix }
    }

    // MARK: - Measured values shared by the health screens

    var lastCapture: CaptureSummary? { band.summary }

    /// Resting HR from the user's override, else the last measured quiet window.
    var measuredRestingHR: Double? {
        // Daytime capture lows are not interchangeable with overnight RHR.
        settings.restingHROverride ?? latestOvernightRestingHR
    }

    var recordedDayCount: Int { band.days.count }

    var hasRecoveryBaseline: Bool {
        (band.baseline?.days ?? 0) >= Recovery.minBaselineDays
    }

    /// Uth 2004 (15.3 × HRmax / HRrest). Uses a measured max HR when one is
    /// set; otherwise the documented 208 − 0.7 × age estimate, labelled as
    /// such. Needs a measured resting HR — the ratio means nothing without it.
    var vo2Estimate: Double? {
        // Never turn an unconfirmed default age or a short daytime capture
        // into an apparently precise fitness estimate.
        guard settings.ageConfirmed,
              let resting = settings.restingHROverride ?? latestOvernightRestingHR else { return nil }
        let maxHR = settings.maxHROverride ?? Karvonen.agePredictedMaxHR(age: settings.age)
        return Hrv.vo2Max(maxHR: maxHR, restingHR: resting)
    }

    /// Use a dated night-associated resting measurement for fitness trends.
    /// A transient quiet daytime window is not an overnight resting HR.
    private var latestOvernightRestingHR: Double? {
        band.days
            .filter { $0.sleepHours >= 3 && $0.restingHR != nil && $0.hrvWindowSeconds >= 300 }
            .sorted { $0.dateKey > $1.dateKey }
            .first?.restingHR
    }

    /// Where the max HR in the VO₂ estimate came from, for the caption.
    var vo2Basis: String? {
        guard vo2Estimate != nil else { return nil }
        return settings.maxHROverride == nil
            ? "Uth 2004 · age-predicted max HR"
            : "Uth 2004 · your measured max HR"
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

    /// Active energy over the last capture's per-minute heart rates. Nil when
    /// the body data or a resting HR is missing — `caloriesDetail` names the gap.
    var captureActiveKcal: Double? {
        guard let summary = band.summary, !summary.heartRateSeries.isEmpty,
              let weight = settings.weightKG, let height = settings.heightCM,
              settings.sex != .unspecified,
              let resting = measuredRestingHR else { return nil }
        return Calories.activeKcal(
            hrPerMinute: summary.heartRateSeries,
            restingHR: resting,
            maxHR: maxHeartRate,
            weightKg: weight,
            heightCm: height,
            age: Double(settings.age),
            sex: settings.sex
        )
    }

    /// Why the calorie figure is absent, or what it is measured over.
    var caloriesDetail: String {
        if settings.weightKG == nil || settings.heightCM == nil {
            return "needs weight + height (Settings)"
        }
        if settings.sex == .unspecified {
            return "needs sex selection (Settings) for Keytel estimate"
        }
        guard let summary = band.summary, !summary.heartRateSeries.isEmpty else {
            return "needs a capture"
        }
        guard measuredRestingHR != nil else { return "needs a measured resting HR" }
        return "last capture only · active kcal estimate (\(summary.heartRateSeries.count) HR bins); not daily total"
    }

    /// ACTIVE kcal of a detected session. Nil without body data; zero when the
    /// session never rose above the HR gate and had no measured walking cadence.
    func activeKcal(for session: ActivitySession) -> Double? {
        guard let weight = settings.weightKG, let height = settings.heightCM,
              let resting = measuredRestingHR else { return nil }
        return Calories.sessionActiveKcal(
            meanHR: session.meanHR,
            steps: session.steps,
            minutes: session.minutes,
            restingHR: resting,
            maxHR: maxHeartRate,
            weightKg: weight,
            heightCm: height,
            age: Double(settings.age),
            sex: settings.sex
        )
    }

    func activeKcal(for record: LiveActivityRecord) -> Double? {
        guard let weight = settings.weightKG, let height = settings.heightCM,
              let resting = measuredRestingHR else { return nil }
        return Calories.sessionActiveKcal(
            meanHR: record.meanHR,
            steps: 0,
            minutes: record.minutes,
            restingHR: resting,
            maxHR: maxHeartRate,
            weightKg: weight,
            heightCm: height,
            age: Double(settings.age),
            sex: settings.sex
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