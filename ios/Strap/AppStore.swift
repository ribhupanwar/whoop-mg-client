import Foundation
import Combine
import WidgetKit
import UserNotifications

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
    /// Issue #160: Persistent sleep lifecycle state published to UI.
    @Published private(set) var sleepLifecycle: SleepLifecycleSnapshot
    private let sleepLifecyclePersistence: SleepLifecyclePersistence

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
    private var healthWidgetCancellable: AnyCancellable?
    private var batteryNoticeCancellable: AnyCancellable?
    private var workoutCoordinator: WorkoutLiveActivityCoordinator?
    private let healthWidgetCoalescer = WidgetReloadCoalescer(minimumInterval: 60)
    private var lastSavedHealthWidgetSnapshot: HealthWidgetSnapshot?
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
        let birthDate: ProfileBirthDate?
        let days: [DayMetrics]
        let detected: [ActivitySession]
        let live: [LiveActivityRecord]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.journal = JournalStore(defaults: defaults)
        self.activities = ActivityStore(defaults: defaults)
        self.sleepLifecyclePersistence = SleepLifecyclePersistence(defaults: defaults)
        self.sleepLifecycle = sleepLifecyclePersistence.load()
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
        band.isDetectedActivityDeleted = activities.isDetectedDeleted
        health.isDetectedActivityDeleted = activities.isDetectedDeleted
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
            self?.syncSleepLifecycle(fresh)
        }
        healthCancellable = health.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        monitorCancellable = Publishers.CombineLatest3(band.$days, band.$summary, band.$isAnalyzingHistory)
            .filter { _, _, analyzing in !analyzing }
            .map { days, summary, _ in
                HealthMonitor.make(days: days, session: summary?.latestSleepSession)
            }
            .sink { [weak self] snapshot in
                self?.healthMonitor = snapshot
                DispatchQueue.main.async {
                    self?.checkRestingHRTrend()
                    self?.checkRecoveryRecap()
                }
            }
        // Ignore the publisher's initial cached value. Only newly received
        // battery updates can trigger a low-battery reminder.
        batteryNoticeCancellable = band.$batteryPercent.dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] fresh in
                guard let self, let fresh, self.band.isConnected,
                      !self.band.isCharging, LocalWellnessNotice.lowBattery(fresh), !self.isPreview else { return }
                let observed = Date()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await LocalWellnessNotice.post(.battery, id: JournalStore.dayKey(for: observed),
                        defaults: self.defaults) {
                        self.band.isConnected && !self.band.isCharging && self.band.batteryPercent.map(LocalWellnessNotice.lowBattery) == true
                            && !self.isPreview && Date().timeIntervalSince(observed) < 60
                    }
                }
            }
        healthWidgetCancellable = band.objectWillChange
            .throttle(for: .seconds(60), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshHealthWidget() }
            }
        // Fitness comparisons change with saved observations/profile, never
        // with each live pulse or history packet. Work runs on a serial worker.
        fitnessCancellable = Publishers.CombineLatest4($settings, band.$days, $detectedBandActivities, $liveActivities)
            .map { settings, days, detected, live in
                FitnessInputs(age: settings.age, sex: settings.sex, confirmed: settings.ageConfirmed,
                              birthDate: settings.birthDate,
                              days: days, detected: detected, live: live)
            }
            .removeDuplicates()
            .combineLatest(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                .merge(with: NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange))
                .map { _ in () }.prepend(()))
            .debounce(for: .milliseconds(200), scheduler: fitnessQueue)
            .map { input, _ in
                FitnessAgeModel.snapshot(age: input.age, sex: input.sex, ageConfirmed: input.confirmed,
                    days: input.days, detected: input.detected, live: input.live, birthDate: input.birthDate)
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.workoutCoordinator = WorkoutLiveActivityCoordinator(
                band: self.band,
                recorder: .shared,
                maxHeartRate: { [weak self] in self?.maxHeartRate },
                isPreview: { [weak self] in self?.isPreview ?? false },
                onDayChange: { [weak self] in self?.refreshHealthWidget() }
            )
        }
        band.autoConnectIfNeeded()
    }

    /// Evaluated only after a completed recorded night, never as a live medical alarm.
    func checkRestingHRTrend() {
        guard defaults.bool(forKey: "strap.rhrTrendAlertsEnabled"), !isPreview,
              !band.isAnalyzingHistory,
              let night = band.recoveryNight,
              night.dateKey == JournalStore.dayKey(for: Date()),
              defaults.string(forKey: "strap.rhrTrendAlert.lastDay") != night.dateKey,
              RestingHRTrendAlert.isElevated(current: night, prior: band.days) else { return }
        defaults.set(night.dateKey, forKey: "strap.rhrTrendAlert.lastDay")
        let content = UNMutableNotificationContent()
        content.title = "STRAP · Resting heart rate"
        content.body = "Your recorded resting heart rate is above your recent personal trend. Open STRAP to review."
        let request = UNNotificationRequest(identifier: "strap.rhrTrend." + night.dateKey, content: content, trigger: nil)
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.defaults.bool(forKey: "strap.rhrTrendAlertsEnabled"),
                      [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
                    self.defaults.removeObject(forKey: "strap.rhrTrendAlert.lastDay")
                    return
                }
                UNUserNotificationCenter.current().add(request) { error in
                    if error != nil {
                        DispatchQueue.main.async {
                            if self.defaults.string(forKey: "strap.rhrTrendAlert.lastDay") == night.dateKey {
                                self.defaults.removeObject(forKey: "strap.rhrTrendAlert.lastDay")
                            }
                        }
                    }
                }
            }
        }
    }

    func checkRecoveryRecap() {
        let today = JournalStore.dayKey(for: Date())
        guard !isPreview, !band.isAnalyzingHistory, band.recoveryNight?.dateKey == today,
              let score = band.recovery.score, score.isFinite, (0...100).contains(score) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await LocalWellnessNotice.post(.recovery, id: today, defaults: self.defaults) {
                !self.isPreview && !self.band.isAnalyzingHistory &&
                    self.band.recoveryNight?.dateKey == today && JournalStore.dayKey(for: Date()) == today &&
                    self.band.recovery.score.map { $0.isFinite && (0...100).contains($0) } == true
            }
        }
    }

    func refreshHealthWidget() {
        guard defaults.bool(forKey: "strap.healthWidgetEnabled"), !isPreview else {
            lastSavedHealthWidgetSnapshot = nil
            if HealthWidgetSnapshot.load() != nil, HealthWidgetSnapshot.save(nil) {
                for kind in HealthWidgetMetric.kinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
            }
            return
        }
        guard !band.isAnalyzingHistory else { return }
        let now = Date()
        let key = JournalStore.dayKey(for: now)
        let night = band.recoveryNight.flatMap { $0.dateKey == key ? $0 : nil }
        let day = band.days.last { $0.dateKey == key }
        func valid(_ value: Double?, range: ClosedRange<Double>) -> Double? {
            guard let value, value.isFinite, range.contains(value) else { return nil }
            return value
        }
        let recovery = night == nil ? nil : valid(band.recovery.score, range: 0...100)
        let sleep = valid(night?.sleepPerformancePct, range: 0...100)
        let liveStrain = band.liveDayStrainDateKey == key ? band.liveDayStrain : nil
        let strain = valid(liveStrain ?? day?.strain, range: 0...21)
        let battery = band.isConnected ? band.batteryPercent.flatMap { (0...100).contains($0) ? $0 : nil } : nil
        let stress = band.stress
        let observed = stress.diagnostics?.lastUpdateUnix.map { Date(timeIntervalSince1970: Double($0)) }
        let snapshot = HealthWidgetSnapshot(dayKey: key, recovery: recovery, sleep: sleep,
                                            strain: strain, battery: battery, savedAt: now,
                                            stress: valid(stress.index, range: 0...3), stressObservedAt: observed,
                                            batteryObservedAt: battery == nil ? nil : band.batteryObservedAt)
        let unchanged = lastSavedHealthWidgetSnapshot.map { prev in
            prev.dayKey == snapshot.dayKey && prev.recovery == snapshot.recovery &&
            prev.sleep == snapshot.sleep && prev.strain == snapshot.strain &&
            prev.battery == snapshot.battery && prev.stress == snapshot.stress &&
            prev.stressObservedAt == snapshot.stressObservedAt &&
            prev.batteryObservedAt == snapshot.batteryObservedAt
        } ?? false
        if !unchanged, HealthWidgetSnapshot.save(snapshot) {
            lastSavedHealthWidgetSnapshot = snapshot
            Task { @MainActor [weak self] in
                self?.healthWidgetCoalescer.requestReload {
                    for kind in HealthWidgetMetric.kinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
                }
            }
        }
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

    /// Issue #160: Keep the published sleep lifecycle synchronized with confirmed
    /// sensor sessions without prematurely finalizing or reopening past nights.
    private func syncSleepLifecycle(_ fresh: CaptureSummary?) {
        guard let session = fresh?.latestSleepSession else { return }
        let sessionID = "\(session.sourceStartUnix)-\(session.endUnix)"
        let nowUnix = Int(Date().timeIntervalSince1970)
        let isOngoing = session.canEndNow(lastObservedUnix: fresh?.lastUnix, nowUnix: nowUnix)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if isOngoing {
                if self.sleepLifecycle.phase == .idle || (self.sleepLifecycle.phase == .completed && self.sleepLifecycle.sessionID != sessionID && session.startUnix >= (self.sleepLifecycle.endedAtUnix ?? 0)) {
                    self.sleepLifecycle.confirm(sessionID: sessionID, startUnix: session.startUnix)
                    self.sleepLifecyclePersistence.save(self.sleepLifecycle)
                }
            } else if self.sleepLifecycle.phase == .detected && self.sleepLifecycle.sessionID == sessionID {
                self.sleepLifecycle.end(sessionID: sessionID, at: session.endUnix)
                let hasQuestions = !self.journalEntries.isEmpty
                self.sleepLifecycle.finishProcessing(sessionID: sessionID, hasJournalQuestions: hasQuestions)
                self.sleepLifecyclePersistence.save(self.sleepLifecycle)
            } else if self.sleepLifecycle.phase == .processing && self.sleepLifecycle.sessionID == sessionID {
                let hasQuestions = !self.journalEntries.isEmpty
                self.sleepLifecycle.finishProcessing(sessionID: sessionID, hasJournalQuestions: hasQuestions)
                self.sleepLifecyclePersistence.save(self.sleepLifecycle)
            }
        }
    }

    /// Manual End Sleep immediately bounds the active sleep session and triggers
    /// full recalculation and morning journal progression.
    func endSleepNow() {
        guard let session = band.latestSleepSession, let lastUnix = band.summary?.lastUnix else { return }
        let now = Int(Date().timeIntervalSince1970)
        let sessionID = "\(session.sourceStartUnix)-\(session.endUnix)"
        // A stale lifecycle card or archive frontier must not save a historical
        // candidate as a newly confirmed manual wake time.
        guard sleepLifecycle.phase == .detected,
              sleepLifecycle.sessionID == sessionID,
              session.canEndNow(lastObservedUnix: lastUnix, nowUnix: now) else { return }
        let nowUnix = max(session.startUnix + 60, min(now, lastUnix + 60))

        let overrides = UserDefaults.standard.dictionary(forKey: SleepCorrectionStore.defaultsKey) as? [String: [Int]] ?? [:]
        let updated = SleepCorrectionStore.saving([session.startUnix, nowUnix], for: session.sourcePeriod,
                                                  overrides: overrides, explicitlyEndSleep: true)
        UserDefaults.standard.set(updated, forKey: SleepCorrectionStore.defaultsKey)

        sleepLifecycle.end(sessionID: sessionID, at: nowUnix)
        sleepLifecyclePersistence.save(sleepLifecycle)
        band.notifySleepCorrectionChanged()
    }

    /// Manually trigger immediate final processing for a detected sleep window.
    func processSleepNow() {
        guard let session = band.latestSleepSession else { return }
        let sessionID = "\(session.sourceStartUnix)-\(session.endUnix)"
        sleepLifecycle.end(sessionID: sessionID, at: session.endUnix)
        let hasQuestions = !journalEntries.isEmpty
        sleepLifecycle.finishProcessing(sessionID: sessionID, hasJournalQuestions: hasQuestions)
        sleepLifecyclePersistence.save(sleepLifecycle)
        band.notifySleepCorrectionChanged()
    }

    /// Acknowledge the morning journal prompt to complete the sleep lifecycle.
    func acknowledgeSleepJournal() {
        guard let sessionID = sleepLifecycle.sessionID else { return }
        sleepLifecycle.acknowledgeJournal(sessionID: sessionID)
        sleepLifecyclePersistence.save(sleepLifecycle)
    }

    /// Dismisses any stale or lingering pending sleep lifecycle card safely.
    func dismissSleepLifecycle() {
        guard let sessionID = sleepLifecycle.sessionID else { return }
        sleepLifecycle.acknowledgeJournal(sessionID: sessionID)
        sleepLifecyclePersistence.save(sleepLifecycle)
    }

    /// Design preview toggle. OFF (default) == live mode: measured values where
    /// a capture supports them, an em dash where it does not.
    var isPreview: Bool { settings.designPreview }

    var maxHeartRate: Double {
        settings.profileMaxHeartRate() ?? Karvonen.agePredictedMaxHR(age: settings.age)
    }

    /// Detected nights from captured history. Empty until a capture lands, so
    /// sleep debt stays unknown instead of zero.
    func refreshWhoopImportedHistory() {
        do {
            whoopImportedDays = WhoopImportedHistory.make(try WhoopCSVImport.loadSources(defaults: defaults))
            whoopImportReadError = nil
        } catch { whoopImportReadError = "WHOOP import data could not be read; original bytes preserved." }
        band.sleepPlanningImports = whoopImportedDays
        band.recalculateRetainedMetrics()
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
        let corrections = UserDefaults.standard.dictionary(forKey: SleepCorrectionStore.defaultsKey)
            as? [String: [Int]] ?? [:]
        return SleepCoach.recordedNights(days: band.days, sessions: band.summary?.sleepSessions ?? [],
            imported: whoopImportedDays, baselineHours: settings.sleepNeedHours, corrections: corrections)
    }

    func sleepPlan(nextWake: Date?) -> SleepRecommendation {
        let nights = isPreview ? SampleData.nights : SleepCoach.recentNights(recordedNights, ending: Date())
        let wake = isPreview ? SampleData.demoWakeMinutes
            : nextWake.map { CoachFormat.minutesSinceMidnight($0) } ?? settings.wakeTimeMinutes
        return SleepCoach.recommendation(baseNeedHours: settings.sleepNeedHours, intent: settings.sleepIntent,
            debtHours: SleepCoach.sleepDebt(nights: nights), wakeMinutes: wake,
            measuredEfficiency: SleepCoach.efficiency(nights: nights), scheduledWake: isPreview ? nil : nextWake)
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

    func rebootBand() {
        band.rebootBand()
    }

    /// Safely clears local downloaded health history and UI caches on this phone.
    /// Strictly non-destructive to hardware: on-band SPI flash memory is untouched.
    func clearLocalData() {
        if band.isConnected {
            band.readHistory()
        }
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
                guard let self else { return }
                if self.detectedGeneration == generation { self.detectedBandActivities = remaining }
                guard activityStore.isDetectedDeleted(session) else { return }
                self.band.recalculateRetainedMetrics()
                if self.settings.healthKitEnabled, self.health.state.isOn {
                    Task { [weak self] in await self?.health.deleteDetectedWorkouts(startTimes: [session.startUnix]) }
                }
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
        await health.deleteDetectedWorkouts(startTimes: activities.deletedDetectedStartTimes())
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
        // Require a confirmed age or explicit maximum and an overnight anchor.
        guard let maxHR = settings.profileMaxHeartRate(),
              let resting = settings.restingHROverride ?? latestOvernightRestingHR else { return nil }
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
              let weight = settings.weightKG, let height = settings.heightCM, let age = settings.profileAge(),
              settings.sex != .unspecified,
              let resting = measuredRestingHR else { return nil }
        return Calories.activeKcal(
            hrPerMinute: summary.heartRateSeries,
            restingHR: resting,
            maxHR: maxHeartRate,
            weightKg: weight,
            heightCm: height,
            age: age,
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
        if settings.profileAge() == nil { return "needs confirmed age (Settings)" }
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
              let age = settings.profileAge(), let resting = measuredRestingHR else { return nil }
        return Calories.sessionActiveKcal(
            meanHR: session.meanHR,
            steps: session.steps,
            minutes: session.minutes,
            restingHR: resting,
            maxHR: maxHeartRate,
            weightKg: weight,
            heightCm: height,
            age: age,
            sex: settings.sex
        )
    }

    func activeKcal(for record: LiveActivityRecord) -> Double? {
        guard let weight = settings.weightKG, let height = settings.heightCM,
              let age = settings.profileAge(), let resting = measuredRestingHR else { return nil }
        return Calories.sessionActiveKcal(
            meanHR: record.meanHR,
            steps: 0,
            minutes: record.minutes,
            restingHR: resting,
            maxHR: maxHeartRate,
            weightKg: weight,
            heightCm: height,
            age: age,
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


/// Issue #160: persistent sleep presentation lifecycle. This is deliberately
/// independent of the detector: a quiet period alone must never activate UI.
enum SleepLifecyclePhase: String, Codable, Equatable {
    case idle
    case detected
    case processing
    case journalPending
    case completed
}

struct SleepLifecycleSnapshot: Codable, Equatable {
    var phase: SleepLifecyclePhase = .idle
    var sessionID: String?
    var confirmedStartUnix: Int?
    var endedAtUnix: Int?
    var journalPresented: Bool = false

    /// Only a detector-confirmed session can start a pending sleep card.
    mutating func confirm(sessionID: String, startUnix: Int) {
        guard !sessionID.isEmpty, startUnix > 0 else { return }
        guard phase == .idle || phase == .completed else { return }
        // A replayed or re-analyzed finalized session must not bring back the
        // Sleep Detected card or overwrite the last acknowledged journal.
        if phase == .completed {
            guard self.sessionID != sessionID,
                  let previousEnd = endedAtUnix,
                  startUnix >= previousEnd else { return }
        }
        self.sessionID = sessionID
        confirmedStartUnix = startUnix
        endedAtUnix = nil
        journalPresented = false
        phase = .detected
    }

    /// Both automatic and manual End Sleep use this idempotent transition.
    mutating func end(sessionID: String, at unix: Int) {
        guard phase == .detected, self.sessionID == sessionID,
              let start = confirmedStartUnix, unix > start else { return }
        endedAtUnix = unix
        phase = .processing
    }

    /// Called only after the production sleep report has been persisted.
    mutating func finishProcessing(sessionID: String, hasJournalQuestions: Bool) {
        guard phase == .processing, self.sessionID == sessionID else { return }
        phase = hasJournalQuestions ? .journalPending : .completed
    }

    /// Prevent repeated journal prompts after app restart or refresh.
    mutating func acknowledgeJournal(sessionID: String) {
        guard phase == .journalPending, self.sessionID == sessionID else { return }
        journalPresented = true
        phase = .completed
    }
}

/// Small persistence boundary; no health data or sleep estimates are fabricated.
struct SleepLifecyclePersistence {
    static let key = "strap.sleep.lifecycle.v1"
    let defaults: UserDefaults

    func load() -> SleepLifecycleSnapshot {
        guard let data = defaults.data(forKey: Self.key),
              let snapshot = try? JSONDecoder().decode(SleepLifecycleSnapshot.self, from: data)
        else { return SleepLifecycleSnapshot() }
        return snapshot
    }

    func save(_ snapshot: SleepLifecycleSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }
}


/// Conservative personal trend notification, not a clinical threshold or diagnosis.
enum RestingHRTrendAlert {
    static let minimumPriorNights = 7
    static let elevationBPM = 10.0
    static func isElevated(current: DayMetrics, prior: [DayMetrics]) -> Bool {
        func qualified(_ day: DayMetrics) -> Double? {
            guard day.state == "sleep", day.sleepDurationReliable == true,
                  (day.restingHRWindowSeconds ?? 0) >= 300,
                  let hr = day.restingHR, hr.isFinite, (35...220).contains(hr) else { return nil }
            return hr
        }
        guard let currentHR = qualified(current) else { return false }
        let groups = Dictionary(grouping: prior.filter { $0.dateKey < current.dateKey }, by: \.dateKey)
        let values = groups.keys.sorted().suffix(30).compactMap { key -> Double? in
            guard let rows = groups[key], rows.count == 1, let row = rows.first else { return nil }
            return qualified(row)
        }
        guard values.count >= minimumPriorNights else { return false }
        return currentHR - Stats.median(values) >= elevationBPM
    }
}
