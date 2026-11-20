import Foundation
import Combine

/// Single source of truth for the UI. Settings and journal persist to
/// UserDefaults; band state lives in `BandLink`, which persists its own
/// captures and per-day metrics.
final class AppStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            persistSettings()
            band.configure(sex: settings.sex, maxHR: maxHeartRate, restingHR: measuredRestingHR, needHours: settings.sleepNeedHours)
        }
    }
    @Published private(set) var whoopImportedDays: [String: WhoopImportedDay] = [:]
    @Published private(set) var whoopImportReadError: String?
    @Published private(set) var journalEntries: [String: JournalEntry] = [:]
    @Published private(set) var activityWriteError: String?
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
    private var monitorCancellable: AnyCancellable?
    @Published private(set) var healthMonitor = HealthMonitor.make(days: [], session: nil)
    private var fitnessCancellable: AnyCancellable?
    @Published private(set) var fitnessSnapshot: FitnessAgeSnapshot?
    private let activityQueue = DispatchQueue(label: "strap.activities.merge", qos: .utility)
    private var detectedGeneration = 0
    private let fitnessQueue = DispatchQueue(label: "strap.fitness.snapshot", qos: .utility)

    private struct FitnessInputs: Equatable {
        let age: Int
        let sex: Sex
        let confirmed: Bool
        let days: [DayMetrics]
        let detected: [ActivitySession]
        let live: [LiveActivityRecord]
    }

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
        WakeAlarm.restoreWakeTimeIfNeeded(settings.wakeTimeMinutes, defaults: defaults)
        self.journalEntries = Dictionary(
            uniqueKeysWithValues: journal.allEntries().map { ($0.dateKey, $0) }
        )
        self.manualActivities = activities.manualActivities()
        self.liveActivities = activities.liveActivities()
        self.detectedBandActivities = activities.detectedActivities()
        refreshWhoopImportedHistory()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--design-preview") {
            self.settings.designPreview = true
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--stress-tab-switching") { band.startUIStressReplay() }
        #endif
        band.configure(sex: settings.sex, maxHR: maxHeartRate, restingHR: measuredRestingHR, needHours: settings.sleepNeedHours)
        // A backfill publishes several diagnostics per sensor packet. Forward
        // at most four UI updates per second, including the final trailing one,
        // rather than rebuilding every screen thousands of times during sync.
        // Delivery after willSet also guarantees views read the committed values.
        bandCancellable = band.objectWillChange
            .throttle(for: .milliseconds(250), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.objectWillChange.send() }
        // @Published fires in willSet, so listen to the projected value to see
        // the new summary rather than the previous one.
        summaryCancellable = band.$summary.sink { [weak self] fresh in
            self?.syncDetectedActivities(fresh)
        }
        healthCancellable = health.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        monitorCancellable = Publishers.CombineLatest3(band.$days, band.$summary, band.$isAnalyzingHistory)
            .map { days, summary, analyzing in
                HealthMonitor.make(days: days, session: summary?.latestSleepSession, analyzing: analyzing)
            }
            .sink { [weak self] snapshot in self?.healthMonitor = snapshot }
        // Fitness comparisons change with saved observations/profile, never
        // with each live pulse or history packet. Work runs on a serial worker.
        fitnessCancellable = Publishers.CombineLatest4($settings, band.$days, $detectedBandActivities, $liveActivities)
            .map { settings, days, detected, live in
                FitnessInputs(age: settings.age, sex: settings.sex, confirmed: settings.ageConfirmed,
                              days: days, detected: detected, live: live)
            }
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: fitnessQueue)
            .map { input in
                FitnessAgeModel.snapshot(age: input.age, sex: input.sex, ageConfirmed: input.confirmed,
                    days: input.days, detected: input.detected, live: input.live)
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                if self?.fitnessSnapshot != value { self?.fitnessSnapshot = value }
            }
        if settings.healthKitEnabled {
            Task { [weak self] in
                await self?.activateHealthKit(exportBacklog: true)
            }
        }
        band.autoConnectIfNeeded()
    }

    /// A drain can report the same session twice; the store merges overlaps,
    /// and the published list only changes when something new arrived.
    private func syncDetectedActivities(_ fresh: CaptureSummary?) {
        guard let sessions = fresh?.activities, !sessions.isEmpty else { return }
        detectedGeneration += 1
        let generation = detectedGeneration
        let activityStore = activities
        activityQueue.async { [weak self] in
            activityStore.mergeDetected(sessions)
            let merged = activityStore.detectedActivities()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.detectedGeneration == generation else { return }
                if self.detectedBandActivities != merged { self.detectedBandActivities = merged }
                if self.settings.healthKitEnabled, self.health.state.isOn {
                    Task { [weak self] in await self?.health.export(merged) }
                }
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
    func refreshWhoopImportedHistory() {
        do {
            whoopImportedDays = WhoopImportedHistory.make(try WhoopCSVImport.loadSources(defaults: defaults))
            whoopImportReadError = nil
        } catch { whoopImportReadError = "WHOOP import data could not be read; original bytes preserved." }
    }

    /// Display-only union. It never writes WHOOP fields over band history.
    var historyDays: [DayMetrics] {
        var result = Dictionary(band.days.map { ($0.dateKey, $0) }, uniquingKeysWith: { _, last in last })
        for (key, imported) in whoopImportedDays {
            result[key] = imported.fillingDisplayGaps(in: result[key])
        }
        return result.values.sorted { $0.dateKey < $1.dateKey }
    }

    var recordedNights: [RecordedNight] {
        var result: [String: RecordedNight] = [:]
        for day in band.days {
            guard !band.isAnalyzingHistory, let hours = day.reliableSleepHours else { continue }
            result[day.dateKey] = RecordedNight(dateKey: day.dateKey, neededHours: settings.sleepNeedHours, actualHours: hours)
        }
        let protected = Set(band.days.filter { $0.sleepStartUnix != nil }.map(\.dateKey))
        for (key, day) in whoopImportedDays where result[key] == nil && !protected.contains(key) {
            guard let hours = day.sleepHours else { continue }
            result[key] = RecordedNight(dateKey: key, neededHours: day.sleepNeedHours ?? settings.sleepNeedHours, actualHours: hours)
        }
        return result.values.sorted { $0.dateKey < $1.dateKey }
    }

    func connectBand() {
        band.connect(
            sex: settings.sex, maxHR: maxHeartRate, restingHR: measuredRestingHR, needHours: settings.sleepNeedHours
        )
    }

    func unpairBand() {
        band.unpair()
    }

    func setBroadcastHeartRate(enabled: Bool) {
        band.setBroadcastHeartRate(enabled: enabled)
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

    @discardableResult
    func addActivity(_ activity: ManualActivity) -> Bool {
        let saved = activities.save(activity)
        activityWriteError = activities.lastManualWriteError
        if saved { manualActivities = activities.manualActivities() }
        return saved
    }

    func restoreMissingManualActivity(_ activity: ManualActivity) throws -> Bool {
        let restored = try activities.restoreMissingManual(activity)
        manualActivities = activities.manualActivities()
        return restored
    }

    func mergeManualActivities(ids: Set<UUID>, name: String) throws {
        _ = try activities.mergeManual(ids: ids, name: name)
        manualActivities = activities.manualActivities()
    }

    func undoManualActivityMerge(id: UUID) throws {
        try activities.undoManualMerge(id: id)
        manualActivities = activities.manualActivities()
    }

    @discardableResult
    func deleteActivity(id: UUID) -> Bool {
        let saved = activities.deleteManual(id: id)
        activityWriteError = activities.lastManualWriteError
        if saved { manualActivities = activities.manualActivities() }
        return saved
    }

    func deleteLiveActivity(id: UUID) {
        activities.deleteLive(id: id)
        liveActivities = activities.liveActivities()
    }

    func deleteDetectedActivity(_ session: ActivitySession) {
        detectedGeneration += 1
        let generation = detectedGeneration
        detectedBandActivities.removeAll { $0.id == session.id }
        let activityStore = activities
        activityQueue.async { [weak self] in
            activityStore.deleteDetected(session)
            let remaining = activityStore.detectedActivities()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.detectedGeneration == generation else { return }
                self.detectedBandActivities = remaining
            }
        }
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
            .filter { !activities.isDetectedDeleted($0) }
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

    var recordedDayCount: Int { historyDays.count }

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
        band.days.lazy.filter { $0.state == "sleep" && $0.restingHR != nil }
            .max { $0.dateKey < $1.dateKey }?.restingHR
    }

    /// Where the max HR in the VO₂ estimate came from, for the caption.
    var vo2Basis: String? {
        guard vo2Estimate != nil else { return nil }
        return settings.maxHROverride == nil
            ? "Uth 2004 · age-predicted max HR"
            : "Uth 2004 · your measured max HR"
    }

    /// Recorded trailing seven calendar days, including known live-session
    /// intervals outside the last raw sync. Overlaps are never counted twice.
    func weeklyZoneMinutes(high: Bool) -> Double? {
        let days = MetricTimeline.make(days: band.days, live: liveActivities, manual: [],
            caloriesByDay: [:], ending: Date(), count: 7, sleepNeedHours: settings.sleepNeedHours)
        let metric: DetailMetric = high ? .zonesHigh : .zonesLow
        let values = days.compactMap { $0.value(metric) }
        return values.isEmpty ? nil : values.reduce(0, +)
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
