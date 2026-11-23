import SwiftUI

/// Home — ports the approved mockup's structure and ordering.
/// Live mode: every unmeasured metric is "—"; waiting states say what is needed.
/// Demo mode: labelled sample values behind the persistent banner.
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var activityTitleSize = 15.0
    @ScaledMetric(relativeTo: .caption) private var activityDetailSize = 12.0
    @ScaledMetric(relativeTo: .body) private var activityValueSize = 17.0
    @ScaledMetric(relativeTo: .body) private var activityTileWidth = 84.0
    @AppStorage(ProfileView.nameKey) private var profileName = ""
    let openPlan: () -> Void
    let openInsights: () -> Void

    private let sleepRingColor = Color(hex: 0x7CA0BA)
    private let strainRingColor = Color(hex: 0x0193E8)
    private let highRecoveryRingColor = Color(hex: 0x24E21A)

    @State private var appStreak = AppOpenStreak.stored().current
    @State private var compactScores = false
    @State private var pullProgress: CGFloat = 0
    @State private var isPullRefreshing = false
    @State private var syncSuccessAt: Date?
    @State private var syncSuccessDismissal: Task<Void, Never>?
    @State private var hasObservedInitialSync = false
    @State private var dayOffset = 0
    @State private var showLogger = false
    @State private var nextWake = WakeAlarm.nextWakeDate()
    @State private var showLiveSession = false
    @State private var editingDetectedID: String?
    @State private var correctedKind: ActivityKind = .other
    @State private var correctedLabels: [String: String] = UserDefaults.standard.dictionary(forKey: "strap.detected.activity.labels.v1") as? [String: String] ?? [:]
    @State private var showDeviceSettings = false
    @State private var showDashboardCustomize = false
    @State private var showSleepEditor = false
    @State private var correctedSleepStart = Date()
    @State private var correctedSleepEnd = Date()
    private var sleepCorrections: [String: [Int]] {
        UserDefaults.standard.dictionary(forKey: SleepCorrectionStore.defaultsKey) as? [String: [Int]] ?? [:]
    }

    private var demo: Bool { store.isPreview }

    private var previewsActiveRefresh: Bool {
        #if DEBUG
        return demo && ProcessInfo.processInfo.arguments.contains("--preview-home-refresh")
        #else
        return false
        #endif
    }

    private var syncIsActive: Bool {
        if previewsActiveRefresh { return true }
        guard !demo else { return false }
        return isPullRefreshing || HomeHistoryRefresh.isActive(
            status: store.band.status,
            saving: store.band.isSavingHistory,
            analyzing: store.band.isAnalyzingHistory,
            failed: store.band.historySyncError != nil
        )
    }

    private var isRefreshingVisible: Bool {
        previewsActiveRefresh || syncIsActive || pullProgress > 0.10
    }

    private var refreshIndicator: some View {
        TimelineView(.animation(paused: reduceMotion || !syncIsActive)) { clock in
            let turn: Double = clock.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.0) / 1.0
            let angle: Double = syncIsActive
                ? (reduceMotion ? HomeRefreshConstants.arcGapStartAngleDegrees : turn * 360.0 + HomeRefreshConstants.arcGapStartAngleDegrees)
                : Double(pullProgress) * 90.0 + HomeRefreshConstants.arcGapStartAngleDegrees
            let trimEnd: Double = syncIsActive
                ? HomeRefreshConstants.arcTrimFraction
                : min(HomeRefreshConstants.arcTrimFraction, max(0.05, Double(pullProgress) * HomeRefreshConstants.arcTrimFraction))
            let indicatorOpacity: Double = syncIsActive
                ? 1.0
                : min(1.0, max(0.0, Double(pullProgress - 0.10) / 0.50))
            let indicatorColor = Color.appMuted.opacity(0.85)

            ZStack {
                Circle()
                    .trim(from: 0, to: trimEnd)
                    .stroke(indicatorColor, style: StrokeStyle(lineWidth: HomeRefreshConstants.arcStrokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(angle))

                WhoopWGlyph(color: indicatorColor)
                    .equatable()
                    .accessibilityHidden(true)
            }
            .frame(width: HomeRefreshConstants.diameter, height: HomeRefreshConstants.diameter)
            .opacity(indicatorOpacity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(syncIsActive ? "Syncing band history" : "Pull to sync")
        .accessibilityIdentifier("home.history.refresh")
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                if dayOffset != 0 {
                    Text("Activity history · scores show the latest recorded day")
                        .font(StrapTypography.body(9))
                        .foregroundStyle(Color.appMuted)
                        .padding(.bottom, 5)
                }
                if let completedAt = syncSuccessAt {
                    syncSuccessBanner(completedAt: completedAt)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                ringTrio
                    .onScrollVisibilityChange(threshold: 0.05) { isVisible in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                            compactScores = !isVisible
                        }
                    }
                HistorySyncCard()
                monitorDuo
                myDayOutlook
                if dayOffset == 0 { tonightCard }
                activitiesCard
                journalCard
                planCard
                dashboardSection
                CombinedLoadChart()
                discoverSection
            }
        }
        .onAppear {
            UIRefreshControl.appearance().tintColor = .clear
            // An existing persisted completion is not a new sync success.
            hasObservedInitialSync = true
            AppOpenDayTracker.recordOpen()
            appStreak = AppOpenStreak.stored().current
            nextWake = WakeAlarm.nextWakeDate()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            AppOpenDayTracker.recordOpen()
            appStreak = AppOpenStreak.stored().current
            nextWake = WakeAlarm.nextWakeDate()
        }
        .task(id: nextWake) {
            guard let nextWake else { return }
            let delay = max(0, nextWake.timeIntervalSinceNow)
            do {
                try await Task.sleep(for: .seconds(delay))
                self.nextWake = WakeAlarm.nextWakeDate()
            } catch {
                return
            }
        }
        .safeAreaInset(edge: .top) {
            Group {
                if compactScores {
                    compactRingRow
                } else {
                    topBar
                }
            }
            .frame(height: 44)
            .padding(.horizontal, AppLayout.screenInset)
            .padding(.top, 8)
            .overlay(alignment: .bottom) {
                if isRefreshingVisible && compactScores {
                    refreshIndicator
                        .offset(y: 38)
                        .allowsHitTesting(false)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.88)))
                }
            }
            .background {
                if #available(iOS 26.0, *) {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Color.appCanvasTop.opacity(0.70))
                        .ignoresSafeArea(edges: .top)
                } else {
                    Color.appCanvasTop.opacity(0.98)
                }
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            let overscroll = -(geometry.contentOffset.y + geometry.contentInsets.top)
            return min(1, max(0, overscroll / 64))
        } action: { _, progress in
            pullProgress = progress
        }
        .refreshable {
            guard !demo,
                  HomeHistoryRefresh.canRequest(
                    status: store.band.status,
                    saving: store.band.isSavingHistory,
                    analyzing: store.band.isAnalyzingHistory
                  ) else { return }
            isPullRefreshing = true
            defer { isPullRefreshing = false }

            if store.band.isConnected {
                store.band.readHistory()
            } else {
                store.connectBand()
            }

            let startTime = Date()
            var observedActive = false
            while Date().timeIntervalSince(startTime) < 35 {
                if store.band.historySyncError != nil {
                    break
                }
                let active = HomeHistoryRefresh.isActive(
                    status: store.band.status,
                    saving: store.band.isSavingHistory,
                    analyzing: store.band.isAnalyzingHistory,
                    failed: false
                )
                if active {
                    observedActive = true
                } else if observedActive || Date().timeIntervalSince(startTime) > 1.2 {
                    break
                }
                do {
                    try await Task.sleep(for: .milliseconds(120))
                } catch {
                    break
                }
            }
        }
        .onChange(of: store.band.lastHistorySyncAt) { _, completedAt in
            guard hasObservedInitialSync, let completedAt,
                  store.band.historySyncError == nil else { return }
            syncSuccessDismissal?.cancel()
            withAnimation(.easeInOut(duration: 0.25)) { syncSuccessAt = completedAt }
            syncSuccessDismissal = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) { syncSuccessAt = nil }
            }
        }
        .onDisappear {
            syncSuccessDismissal?.cancel()
            syncSuccessDismissal = nil
            syncSuccessAt = nil
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showLogger) {
            ActivityLoggerView()
        }
        .sheet(isPresented: Binding(get: { editingDetectedID != nil }, set: { if !$0 { editingDetectedID = nil } })) {
            NavigationStack {
                Form {
                    Picker("Correct activity", selection: $correctedKind) {
                        ForEach(ActivityKind.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    Text("Only the activity label changes. Recorded HR, duration and steps stay untouched.")
                        .font(StrapTypography.body(11))
                }
                .navigationTitle("Edit activity")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingDetectedID = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let id = editingDetectedID {
                                correctedLabels[id] = correctedKind.rawValue
                                UserDefaults.standard.set(correctedLabels, forKey: "strap.detected.activity.labels.v1")
                            }
                            editingDetectedID = nil
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSleepEditor) {
            NavigationStack {
                Form {
                    DatePicker("Sleep started", selection: $correctedSleepStart)
                    DatePicker("Woke up", selection: $correctedSleepEnd)
                    Button {
                        correctedSleepEnd = Date()
                    } label: {
                        Label("Mark sleep ended now", systemImage: "moon.zzz")
                            .font(StrapTypography.body(14, weight: .bold))
                    }
                    Text("Bed and wake times are editable. Recovery uses estimated time asleep (excluding awake periods); HRV and RHR remain sensor-derived.")
                        .font(StrapTypography.body(11))
                }
                .navigationTitle("Edit sleep")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showSleepEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if correctedSleepEnd > correctedSleepStart,
                               correctedSleepEnd.timeIntervalSince(correctedSleepStart) <= 86400,
                               let period = latestSleepPeriod {
                                let corrections = SleepCorrectionStore.saving([
                                    Int(correctedSleepStart.timeIntervalSince1970),
                                    Int(correctedSleepEnd.timeIntervalSince1970)
                                ], for: period, overrides: sleepCorrections)
                                UserDefaults.standard.set(corrections, forKey: SleepCorrectionStore.defaultsKey)
                                store.band.notifySleepCorrectionChanged()
                            }
                            showSleepEditor = false
                        }
                        .disabled(correctedSleepEnd <= correctedSleepStart || correctedSleepEnd.timeIntervalSince(correctedSleepStart) > 86400)
                    }
                }
            }
        }
        .sheet(isPresented: $showLiveSession) {
            LiveSessionView()
        }
        .sheet(isPresented: $showDeviceSettings) {
            HomeBandDeviceSettingsView()
        }
        .sheet(isPresented: $showDashboardCustomize) {
            DashboardCustomizeSheet()
        }
    }

    // MARK: Pull-to-refresh completion

    private func syncSuccessBanner(completedAt: Date) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "cloud")
                .font(.system(size: 18))
                .foregroundStyle(.white)
            Text("DATA CAUGHT UP")
                .font(StrapTypography.body(12, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(.white)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text("SYNCED TO")
                    .font(StrapTypography.body(11, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(.white)
                Text(completedAt, format: .dateTime.hour().minute())
                    .font(StrapTypography.metric(11, weight: .bold))
                    .foregroundStyle(Color.green)
            }
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.green)
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            NavigationLink(value: Route.profile) {
                ProfileAvatarView(size: 32)
            }.buttonStyle(.plain).accessibilityLabel("Profile")
            NavigationLink(value: Route.dayStreak) {
                HStack(spacing: 4) {
                    Image("health_strain").resizable().aspectRatio(contentMode: .fit).frame(width: 14, height: 14).foregroundStyle(Color.orange)
                    Text(appStreak.formatted()).font(StrapTypography.metric(14, weight: .bold))
                }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .background(LinearGradient.appCard, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Day Streak")
            .accessibilityValue("\(appStreak) days")

            Spacer()

            HStack(spacing: 0) {
                Button {
                    if dayOffset > -6 { dayOffset -= 1 }
                } label: {
                    Text("‹").font(StrapTypography.body(16)).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(dayOffset <= -6)
                .foregroundStyle(dayOffset <= -6 ? Color.appLine : Color.appFG)

                Text(dayLabel)
                    .font(StrapTypography.body(11, weight: .medium))
                    .tracking(0.9)
                    .foregroundStyle(Color.appFG)
                    .frame(minWidth: 62)
                    .accessibilityIdentifier("home.today")

                Button {
                    if dayOffset < 0 { dayOffset += 1 }
                } label: {
                    Text("›").font(StrapTypography.body(16)).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(dayOffset >= 0)
                .foregroundStyle(dayOffset >= 0 ? Color.appLine : Color.appFG)
            }
            .padding(2)
            .background(Capsule().fill(Color.appRaised))

            Spacer()

            Button {
                showDeviceSettings = true
            } label: {
                HStack(spacing: 6) {
                    Text(demo ? "\(SampleData.batteryPercent)%" : batteryText)
                        .font(StrapTypography.metric(12, weight: .bold))
                        .foregroundStyle(Color.appMuted)
                        .monospacedDigit()
                    WhoopBandBatteryIcon(
                        charge: displayedBattery,
                        connected: store.band.isConnected,
                        isCharging: store.band.isCharging
                    )
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Band battery \(demo ? "\(SampleData.batteryPercent) percent" : batteryText), device settings")
            .accessibilityHint("Opens band status and advanced information")

        }
        .padding(.bottom, 10)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Home")
                .font(StrapTypography.body(28, weight: .bold))
                .foregroundStyle(Color.appFG)
            Text(subtitle)
                .font(StrapTypography.body(12))
                .foregroundStyle(Color.appMuted)
        }
        .padding(.bottom, 12)
    }

    // MARK: Trio rings

    private var ringTrio: some View {
        VStack(spacing: 0) {
            if isRefreshingVisible && !compactScores {
                refreshIndicator
                    .padding(.bottom, HomeRefreshConstants.indicatorToTitleGap)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.88)))
            }
            Text("STRAP")
                .font(StrapTypography.body(18, weight: .medium))
                .tracking(3.2)
                .foregroundStyle(Color.appFG)
                .frame(maxWidth: .infinity)
                .padding(.top, (isRefreshingVisible && !compactScores) ? 0 : 8)
                .padding(.bottom, HomeRefreshConstants.titleToRingsGap)
                .accessibilityLabel("STRAP")
            let diameter: CGFloat = AppLayout.heroRingDiameter
            HStack(spacing: AppLayout.ringGap) {
                NavigationLink(value: Route.sleepAnalysis) {
                    trioItem(
                        label: "SLEEP",
                        text: demo ? "\(SampleData.sleepRingPercent)%" : percentText(sleepPercent),
                        progress: demo ? Double(SampleData.sleepRingPercent) / 100 : sleepPercent.map { Double($0) / 100 },
                        color: sleepRingColor,
                        ringSize: diameter
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: Route.recovery) {
                    trioItem(
                        label: "RECOVERY",
                        text: demo ? "\(SampleData.recoveryRingPercent)%" : percentText(recoveryScore.map { Int($0.rounded()) }),
                        progress: demo ? Double(SampleData.recoveryRingPercent) / 100 : recoveryScore.map { $0 / 100 },
                        color: (demo ? Double(SampleData.recoveryRingPercent) : recoveryScore).map { score in
                            score >= 67 ? highRecoveryRingColor : DetailMetric.recovery.color(score)
                        } ?? DetailMetric.recovery.color(nil),
                        ringSize: diameter
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: Route.strain) {
                    trioItem(
                        label: "STRAIN",
                        text: demo ? String(format: "%.1f", SampleData.strain) : strain.map { String(format: "%.1f", $0) } ?? "—",
                        progress: demo ? SampleData.strain / 21 : strain.map { $0 / 21 },
                        color: strainRingColor,
                        ringSize: diameter
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 108)
        }
        .padding(.bottom, 18)
    }

    private func percentText(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)%"
    }

    private var trioHint: String {
        if sleepPercent == nil && recoveryScore == nil && strain == nil {
            return "Sleep needs an overnight capture; recovery needs a 7-day baseline; strain needs a measured max HR and a full day of wear."
        }
        var parts: [String] = []
        if sleepPercent == nil { parts.append("sleep needs an overnight capture") }
        if recoveryScore == nil { parts.append(store.band.recovery.reason ?? "recovery needs a baseline") }
        if strain == nil { parts.append("strain needs recorded awake HR and a resting HR") }
        return parts.joined(separator: " · ")
    }

    private var sleepPercent: Int? {
        guard let score = store.band.lastSleepAnalysis?.performancePct, score.isFinite else { return nil }
        return Int(min(100, max(0, score)).rounded())
    }

    private var recoveryScore: Double? { store.band.recovery.score }

    private var strain: Double? {
        // Keep the Home ring consistent with the daily Strain History bar while
        // updating reactively in real time as live heart rate is streamed.
        let today = JournalStore.dayKey(for: Date())
        let batchStrain = store.band.days.first(where: { $0.dateKey == today })?.strain
        if let live = store.band.liveDayStrain {
            if let batch = batchStrain {
                return max(batch, live)
            }
            return live
        }
        return batchStrain
    }

    private var displayedBattery: Int? {
        demo ? SampleData.batteryPercent : store.band.batteryPercent
    }

    private var batteryText: String {
        guard let battery = store.band.batteryPercent else { return "—" }
        return "\(battery)%"
    }

    private func trioItem(label: String, text: String, progress: Double?, color: Color, ringSize: CGFloat) -> some View {
        VStack(spacing: 8) {
            RingView(progress: progress, color: color, size: ringSize, centerText: text)
                .accessibilityHidden(true)
            HStack(spacing: 3) {
                Text(label)
                    .font(StrapTypography.body(11, weight: .bold))
                    .tracking(0.6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Color.appFG)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + ", " + (text == "—" ? "unavailable" : text))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Insight

    private var insightCard: some View {
        Panel {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(demo ? "Elevated HRV" : insightTitle)
                        .font(StrapTypography.body(14, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text(demo
                         ? "Sample: your HRV is 6% above your usual, which signals strong recovery. A planned threshold run or heavy lift both fit today."
                         : insightBody)
                        .font(StrapTypography.body(12))
                        .foregroundStyle(Color.appMuted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(StrapTypography.body(13))
                        .foregroundStyle(Color.appGood)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.appRaised))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
                    Text(demo ? "1" : "\(store.recordedDayCount)")
                        .font(StrapTypography.body(11))
                        .foregroundStyle(Color.appMuted)
                }
            }
        }
    }

    private var insightTitle: String {
        if let score = store.band.recovery.score {
            return "Recovery \(Int(score.rounded())) · \(store.band.recovery.band)"
        }
        if let summary = store.lastCapture {
            return "Capture stored · \(summary.sampleCount) s"
        }
        return "Waiting for first capture"
    }

    private var insightBody: String {
        if let reason = store.band.recovery.reason {
            return "\(reason). Each history capture adds its own days; baselines need a week of them."
        }
        if store.band.isAnalyzingHistory { return "Updating the saved sleep window and its metrics…" }
        if let session = store.band.latestSleepSession {
            if let hours = session.asleepHours {
                let pct = Int((min(1, hours / max(0.1, store.settings.sleepNeedHours)) * 100).rounded())
                return "Last night: \(CoachFormat.duration(hours)) estimated asleep, \(pct)% of base need. \(session.movementBouts) movement bouts (not verified awakenings)."
            }
            return "\(CoachFormat.duration(session.timeInBedHours)) in bed. Full sleep duration is unknown; missing data is not counted as awake or added to sleep debt."
        }
        if let summary = store.lastCapture {
            let hrv = summary.hrv.rmssdMS.map { String(format: "%.0f ms", $0) } ?? "no steady R-R window"
            let rhr = summary.restingHeartRate.map { String(format: "%.0f bpm", $0) } ?? "RHR unavailable"
            return "Last capture: \(summary.sampleCount.formatted()) samples · \(rhr) · HRV \(hrv). Long enough for a baseline day."
        }
        return "Strap reads your band locally. Sleep, recovery and HRV insights appear once overnight and daytime captures exist — nothing is estimated until then."
    }

    // MARK: Monitor duo

    private var monitorDuo: some View {
        let health = store.healthMonitor
        let outside = health.readings.filter { $0.status == .outsideRange }.count
        let within = health.withinCount
        let healthState: String
        let healthColor: Color
        if demo {
            healthState = "WITHIN RANGE"
            healthColor = .appGood
        } else if outside > 0 {
            healthState = "\(outside) OUTSIDE RANGE"
            healthColor = .appWarn
        } else if within > 0 {
            healthState = "\(within) IN RANGE"
            healthColor = .appGood
        } else {
            healthState = health.availableCount == 0 ? "UNAVAILABLE" : "BASELINE PENDING"
            healthColor = .appMuted
        }

        let stress = store.band.stress
        let stressColor: Color
        switch demo ? "low" : stress.band {
        case "low": stressColor = .appSleep
        case "elevated": stressColor = .appGood
        case "high": stressColor = .appWarn
        default: stressColor = .appMuted
        }

        return HStack(alignment: .top, spacing: 10) {
            NavigationLink(value: Route.health) {
                tapCard(
                    title: "Health monitor",
                    pill: demo ? "✓" : "\(within)/\(HealthVital.allCases.count)",
                    pillColor: healthColor,
                    state: healthState,
                    stateColor: healthColor,
                    detail: demo ? "5 metrics · sample" : "\(health.availableCount)/\(HealthVital.allCases.count) available"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: Route.stress) {
                tapCard(
                    title: "Stress monitor",
                    pill: (demo ? SampleData.stressHome : stress.index).map { String(format: "%.1f", $0) } ?? "—",
                    pillColor: stressColor,
                    state: demo ? "LOW" : stress.band.uppercased(),
                    stateColor: stressColor,
                    detail: demo ? "11:49 · sample" : stress.reason ?? "Awake-quiet estimate"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 14)
    }

    private func tapCard(title: String, pill: String, pillColor: Color, state: String, stateColor: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(StrapTypography.body(11.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.appFG)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Color.appMuted)
            }
            HStack(spacing: 8) {
                HStack {
                    if pill == "✓" {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(pillColor)
                    } else {
                        Text(pill)
                            .font(StrapTypography.metric(11.5, weight: .bold))
                            .foregroundStyle(pillColor)
                    }
                }
                .frame(minWidth: 22, minHeight: 22)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(pillColor.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(pillColor.opacity(0.3), lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(state)
                        .font(StrapTypography.body(12, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(stateColor)
                    Text(detail)
                        .font(StrapTypography.body(10.5))
                        .foregroundStyle(Color.appMuted)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 83, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(LinearGradient.appCard))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
    }

    // MARK: My Day

    private var myDayOutlook: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("My Day")
                    .font(StrapTypography.body(22, weight: .bold))
                    .foregroundStyle(Color.appFG)
                Spacer()
                Button { showLogger = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.appBG)
                        .frame(width: 32, height: 32)
                        .background(Color.appFG, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add activity")
            }
            Button(action: openInsights) {
                HStack(spacing: 10) {
                    Image(systemName: "moon")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: 0x89B9DD))
                    Text(dayInReviewTitle)
                        .font(StrapTypography.body(13.5, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x89B9DD))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [Color(hex: 0x302751), Color(hex: 0x234C58)], startPoint: .leading, endPoint: .trailing)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                )
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 14)
    }

    private var dayInReviewTitle: String {
        guard let first = profileName.split(whereSeparator: \.isWhitespace).first else {
            return "Day in Review"
        }
        return "\(first)’s Day in Review"
    }

    // MARK: Today's activities

    private var todayNaps: [SleepSession] {
        (store.band.summary?.sleepSessions ?? []).filter {
            $0.classification == .nap && Calendar.current.isDateInToday(Date(timeIntervalSince1970: Double($0.endUnix - 1)))
        }
    }

    private var activitiesCard: some View {
        Panel {
            CardHead(title: "TODAY'S ACTIVITIES", trailing: "⤢")

            if demo || store.band.latestSleepSession != nil {
            NavigationLink(value: Route.sleepAnalysis) {
                activityTile(icon: ActivityIconRegistry.sleep, name: "Sleep",
                             value: demo ? SampleData.lastNightSleep : lastNightText,
                             detail: demo ? "00:26\n07:33" : sleepTimesText,
                             tint: Color.appSleep)
            }
            .buttonStyle(.plain)
            .contextMenu {
                if !demo, latestSleepPeriod != nil {
                    Button("Edit sleep time") { openHomeSleepEditor() }
                }
            }
            .padding(.bottom, 10)
            }
            VStack(spacing: 8) {
                if !demo {
                    ForEach(todayNaps, id: \.sourceStartUnix) { session in
                        activityRow(icon: ActivityIconRegistry.nap, name: "Nap", detail: "\(Self.sleepClock(session.startUnix, includeDay: false))–\(Self.sleepClock(session.endUnix, includeDay: false))")
                    }
                }
                if demo {
                    activityRow(icon: ActivityKind.run.icon, name: "Run", detail: "42 min · Z2")
                    activityRow(icon: ActivityKind.walk.icon, name: "Walk", detail: "28 min · errands")
                    activityRow(icon: ActivityKind.lift.icon, name: "Gym workout", detail: "55 min · push")
                    activityRow(icon: "clock", name: "Rest session", detail: "15 min · measured")
                } else {
                    ForEach(timedRows, id: \.id) { row in
                        activityRow(icon: row.icon, name: row.name, detail: row.times ?? row.detail, strain: row.strain)
                        .accessibilityHint(row.detail)
                        .modifier(ActivityDeleteReveal(delete: { deleteActivityRow(row) }))
                        .contentShape(Rectangle())
                        .contextMenu {
                            Text(row.detail)
                            if row.id.hasPrefix("band-") {
                                Button {
                                    editingDetectedID = row.id
                                    correctedKind = ActivityKind(rawValue: correctedLabels[row.id] ?? "") ?? .other
                                } label: {
                                    Label("Edit activity", systemImage: "pencil")
                                }
                            }
                            Button(role: .destructive) {
                                deleteActivityRow(row)
                            } label: {
                                Label("Delete Activity", systemImage: "trash")
                            }
                        }
                    }
                    // Manual entries have a date but no recorded start time.
                    // Keep them separate rather than inventing a clock time.
                    ForEach(manualRows, id: \.id) { row in
                        activityRow(icon: row.icon, name: row.name, detail: row.detail)
                            .modifier(ActivityDeleteReveal(delete: { deleteActivityRow(row) }))
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteActivityRow(row)
                                } label: {
                                    Label("Delete Activity", systemImage: "trash")
                                }
                            }
                    }
                    if detectedRows.isEmpty && liveRows.isEmpty && manualRows.isEmpty {
                        Text("No activities for this day yet.")
                            .font(StrapTypography.body(11))
                            .foregroundStyle(Color.appMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.bottom, 16)
            HStack(spacing: 10) {
                Button { showLogger = true } label: {
                    Label("ADD ACTIVITY", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                Button { showLiveSession = true } label: {
                    Label("START ACTIVITY", systemImage: "stopwatch")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .font(StrapTypography.body(10, weight: .bold))
            .tracking(0.7)
            .buttonStyle(.plain)
            .foregroundStyle(Color.appFG)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.appRaised, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Activity rows

    private func openHomeSleepEditor() {
        guard let period = latestSleepPeriod else { return }
        let session = store.band.latestSleepSession
        let times = SleepCorrectionStore.times(for: period, overrides: sleepCorrections)
        // Explicit user corrections must win over a stale derived sleep session.
        correctedSleepStart = Date(timeIntervalSince1970: TimeInterval(times?.first ?? session?.startUnix ?? period.startUnix))
        correctedSleepEnd = Date(timeIntervalSince1970: TimeInterval(times?.last ?? session?.endUnix ?? (period.endUnix + 1)))
        showSleepEditor = true
    }

    private struct ActivityRowModel: Identifiable {
        let id: String
        let icon: String
        let name: String
        let detail: String
        let startUnix: Int?
        var strain: Double? = nil
        var times: String? = nil
    }

    private var timedRows: [ActivityRowModel] {
        (detectedRows + liveRows).sorted {
            ($0.startUnix ?? Int.max) < ($1.startUnix ?? Int.max)
        }
    }

    private static func clockRange(_ start: Int, _ end: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "\(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(start))))\n\(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(end))))"
    }

    private var selectedDayKey: String {
        JournalStore.dayKey(for: shiftedDate)
    }

    private var detectedRows: [ActivityRowModel] {
        store.detectedActivities(on: selectedDayKey).map { session in
            let minutes = Int(session.minutes.rounded())
            let heart = session.meanHR.map { " · \(Int($0.rounded())) bpm" } ?? ""
            let steps = session.steps > 0 ? " · \(session.steps.formatted()) steps" : ""
            let kcal = store.activeKcal(for: session).map { " · \(Int($0.rounded())) kcal" } ?? ""
            let strainText = session.strain.map { " · Strain \(String(format: "%.1f", $0))" } ?? ""
            let key = "band-\(session.startUnix)"
            let corrected = correctedLabels[key].flatMap(ActivityKind.init(rawValue:))
            return ActivityRowModel(
                id: key,
                icon: corrected?.icon ?? ActivityIconRegistry.detectedIcon(session.kind),
                name: "\(corrected?.label ?? session.kind.capitalized) · band",
                detail: "\(minutes) min\(strainText)\(steps)\(heart)\(kcal)",
                startUnix: session.startUnix,
                strain: session.strain,
                times: Self.clockRange(session.startUnix, session.endUnix)
            )
        }
    }

    private var liveRows: [ActivityRowModel] {
        store.liveActivities(on: selectedDayKey).map { record in
            let minutes = Int(record.minutes.rounded())
            let heart = record.meanHR.map { " · \(Int($0.rounded())) bpm" } ?? ""
            let kcal = store.activeKcal(for: record).map { " · \(Int($0.rounded())) kcal" } ?? ""
            return ActivityRowModel(
                id: "live-\(record.id)",
                icon: "waveform.path.ecg",
                name: "Live session · measured",
                detail: "\(minutes) min\(heart)\(kcal)",
                startUnix: record.startedUnix,
                times: Self.clockRange(record.startedUnix, record.endedUnix)
            )
        }
    }

    private var manualRows: [ActivityRowModel] {
        store.manualActivities(on: selectedDayKey).map { activity in
            ActivityRowModel(
                id: "manual-\(activity.id)",
                icon: activity.kind.icon,
                name: "\(activity.name) · logged",
                detail: activity.summary,
                startUnix: nil
            )
        }
    }

    private func deleteActivityRow(_ row: ActivityRowModel) {
        if row.id.hasPrefix("band-"), let start = Int(row.id.dropFirst("band-".count)),
           let session = store.detectedActivities(on: selectedDayKey).first(where: { $0.startUnix == start }) {
            store.deleteDetectedActivity(session)
        } else if row.id.hasPrefix("live-"),
                  let id = UUID(uuidString: String(row.id.dropFirst("live-".count))) {
            store.deleteLiveActivity(id: id)
        } else if row.id.hasPrefix("manual-"),
                  let id = UUID(uuidString: String(row.id.dropFirst("manual-".count))) {
            store.deleteActivity(id: id)
        }
    }

    private func activityRow(icon: String, name: String, detail: String, strain: Double? = nil) -> some View {
        activityTile(icon: icon, name: name,
                     value: strain.map { String(format: "%.1f", $0) } ?? "—",
                     detail: detail, tint: Color.appAccent)
    }

    private func activityTile(icon: String, name: String, value: String, detail: String, tint: Color) -> some View {
        let title = Text(cleanActivityName(name))
            .font(StrapTypography.body(activityTitleSize, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Color.appFG)
        let subtitle = Text(detail)
            .font(StrapTypography.metric(activityDetailSize, weight: .medium))
            .foregroundStyle(Color.appMuted)
            .monospacedDigit()
        let tile = HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
            Text(value).font(StrapTypography.metric(activityValueSize, weight: .bold)).monospacedDigit()
        }
        .foregroundStyle(Color.appFG)
        .padding(.horizontal, 8)
        .frame(minWidth: activityTileWidth, minHeight: 36)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    colors: [tint, tint.opacity(0.82)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        }

        return HStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    tile
                    title.fixedSize()
                    Spacer(minLength: 4)
                    subtitle.multilineTextAlignment(.trailing).fixedSize()
                }
                HStack(alignment: .top, spacing: 10) {
                    tile
                    VStack(alignment: .leading, spacing: 4) {
                        title
                        subtitle
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Capsule().fill(tint).frame(width: 2, height: 26)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .frame(minHeight: 52)
        .background {
            RoundedRectangle(cornerRadius: 11)
                .fill(Color.appRaised)
                .overlay {
                    RoundedRectangle(cornerRadius: 11).strokeBorder(Color.appCardBorder, lineWidth: 1)
                }
        }
    }

    private func cleanActivityName(_ name: String) -> String {
        name.replacingOccurrences(of: " · band", with: "")
            .replacingOccurrences(of: " · logged", with: "")
            .replacingOccurrences(of: " · measured", with: "")
            .uppercased()
    }

    private func activityButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(StrapTypography.body(11, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(Color.appFG)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.appRaised))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Tonight's sleep

    private var tonightCard: some View {
        let plan = store.sleepPlan(nextWake: nextWake)
        return Panel {
            HStack {
                Text("TONIGHT'S SLEEP")
                    .font(StrapTypography.body(11, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(Color.appFG)
                Spacer()
                NavigationLink(value: Route.sleepCoach) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.appMuted)
                        .frame(width: 30, height: 30)
                }
            }
            .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: "sunrise")
                            .font(.system(size: 19))
                            .foregroundStyle(Color.appMuted)
                        Text(CoachFormat.localClock(plan.bedtimeMinutes))
                            .accessibilityIdentifier("home.bedtime")
                            .font(StrapTypography.metric(24, weight: .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(Color.appFG)
                    Text("RECOMMENDED\nBEDTIME")
                        .font(StrapTypography.body(11, weight: .bold))
                        .tracking(1.0)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.appMuted)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 3) {
                    ForEach(0..<8, id: \.self) { _ in
                        Capsule().fill(Color.appMuted.opacity(0.40))
                            .frame(width: 4, height: 1)
                    }
                }
                .frame(width: 48)
                .padding(.top, 16)

                VStack(spacing: 7) {
                    HStack(spacing: 7) {
                        Image("device_strap_idle").resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 20)
                            .font(.system(size: 19))
                            .foregroundStyle(Color.appMuted)
                        Text(demo || nextWake != nil ? CoachFormat.localClock(plan.wakeMinutes) : "—")
                            .font(StrapTypography.metric(24, weight: .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(Color.appFG)
                    if demo || nextWake != nil {
                        HStack(spacing: 5) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("ALARM ON")
                                .font(StrapTypography.body(11, weight: .bold))
                                .tracking(0.9)
                                .foregroundStyle(Color.green)
                        }
                        Text("EXACT TIME")
                            .font(StrapTypography.body(11, weight: .bold))
                            .tracking(1.0)
                            .foregroundStyle(Color.appMuted)
                    } else {
                        Text("NO ALARM SCHEDULED")
                            .font(StrapTypography.body(10, weight: .bold))
                            .foregroundStyle(Color.appMuted)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 18)

            NavigationLink(value: Route.sleepCoach) {
                Label("EDIT ALARM", systemImage: "pencil")
                    .font(StrapTypography.body(12, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Color.appFG)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.appRaised, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.sleepPlanner")
        }
        .padding(.bottom, 14)
    }

    private var lastNightText: String {
        store.band.lastNightHours.map(CoachFormat.duration) ?? "—"
    }

    private var latestSleepPeriod: SleepPeriod? {
        guard !store.band.isAnalyzingHistory else { return nil }
        let periods = store.lastCapture?.sleepPeriods ?? []
        if let session = store.band.latestSleepSession {
            return periods.first { $0.startUnix == session.sourceStartUnix } ?? session.sourcePeriod
        }
        return periods.max(by: { $0.endUnix < $1.endUnix })
    }

    private var sleepTimesText: String {
        if store.band.isAnalyzingHistory { return "Updating…" }
        guard let period = latestSleepPeriod else { return "wear it\ntonight" }
        let times = SleepCorrectionStore.times(for: period, overrides: sleepCorrections)
        let session = store.band.latestSleepSession
        // Display saved user edits even while a cached session is being refreshed.
        let start = times?.first ?? session?.startUnix ?? period.startUnix
        let end = times?.last ?? session?.endUnix ?? (period.endUnix + 1)
        return "\(Self.sleepClock(start, includeDay: true))\n\(Self.sleepClock(end, includeDay: false))"
    }

    private static func sleepClock(_ unix: Int, includeDay: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = includeDay ? "[EEE] h:mm a" : "h:mm a"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
    }

    // MARK: Journal

    private var journalCard: some View {
        Panel {
            HStack {
                Text("MY JOURNAL")
                    .font(StrapTypography.body(11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Color.appFG)
                Spacer()
                NavigationLink(value: Route.journal) {
                    Text("✎ FILL OUT")
                        .font(StrapTypography.body(10, weight: .medium))
                        .tracking(0.7)
                        .foregroundStyle(Color.appFG)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.appRaised))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
                }
            }
            .padding(.bottom, 9)

            HStack(spacing: 0) {
                ForEach(0..<7) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: offset - 6, to: Date()) ?? Date()
                    let key = JournalStore.dayKey(for: date)
                    NavigationLink(value: Route.journal) {
                        VStack(spacing: 9) {
                            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                                .font(StrapTypography.body(9, weight: .bold))
                            Image(systemName: store.journalEntries[key] == nil ? "circle" : "checkmark.circle.fill")
                                .font(StrapTypography.body(20, weight: .light))
                        }.foregroundStyle(store.journalEntries[key] == nil ? Color.appMuted : Color.appGood)
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }
            }.padding(.vertical, 14)
            NavigationLink(value: Route.journal) {
                Label("BEHAVIOR INSIGHTS", systemImage: "lightbulb")
                    .font(StrapTypography.body(11, weight: .bold)).foregroundStyle(Color.appFG)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.appRaised, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain)
            Text(journalStateText)
                .font(StrapTypography.body(11))
                .foregroundStyle(Color.appMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var journalStateText: String {
        if let entry = store.todayEntry() {
            return "Filled today · \(entry.yesCount) yes · mood \(entry.mood?.label ?? "—"). Edit any time."
        }
        if demo {
            return "Filled · 2 yes · mood Good · sample"
        }
        return "Not filled today"
    }

    // MARK: Inline dashboard

    private var dashboardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("My Dashboard")
                    .font(StrapTypography.body(24, weight: .bold))
                    .foregroundStyle(Color.appFG)
                Spacer()
                Button {
                    showDashboardCustomize = true
                } label: {
                    Label("CUSTOMIZE", systemImage: "slider.horizontal.3")
                        .font(StrapTypography.body(11, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(Color.appFG)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 7).fill(
                                LinearGradient(colors: [Color.appCustomizeStart, Color.appCustomizeEnd],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
            .padding(.bottom, 10)

            DashboardRows()
        }
    }

    private var compactRingRow: some View {
        // Use exactly the same progress and palette as the full-size rings.
        // Otherwise the sticky header changes colors/scores while scrolling.
        let displayedRecovery = demo ? Double(SampleData.recoveryRingPercent) : recoveryScore
        let recoveryColor = displayedRecovery.map { score in
            score >= 67 ? highRecoveryRingColor : DetailMetric.recovery.color(score)
        } ?? DetailMetric.recovery.color(nil)
        return HStack(spacing: 4) {
            compactRing("SLEEP", route: .sleepAnalysis,
                        progress: demo ? Double(SampleData.sleepRingPercent) / 100 : sleepPercent.map { Double($0) / 100 },
                        color: sleepRingColor)
            compactRing("RECOVERY", route: .recovery,
                        progress: displayedRecovery.map { $0 / 100 }, color: recoveryColor)
            compactRing("STRAIN", route: .strain,
                        progress: demo ? SampleData.strain / 21 : strain.map { $0 / 21 },
                        color: strainRingColor)
        }.frame(maxWidth: .infinity)
    }

    private func compactRing(_ title: String, route: Route, progress: Double?, color: Color) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 6) {
                RingView(progress: progress, color: color, lineWidth: 3.0, size: 25, centerText: "")
                Text(title)
                    .font(StrapTypography.body(11, weight: .bold))
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .foregroundStyle(Color.appFG)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.compact." + title.lowercased())
        .accessibilityValue(progress == nil ? "Unavailable" : "")
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Plan").font(StrapTypography.body(24, weight: .bold))
            Button(action: openPlan) {
                Panel {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Build Your Best Self").font(StrapTypography.body(18, weight: .bold))
                            Text("Set goals, track progress, and build a consistent routine.").font(StrapTypography.body(12)).foregroundStyle(Color.appMuted)
                            Label("EXPLORE PLANS", systemImage: "arrow.right").font(StrapTypography.body(10, weight: .bold)).foregroundStyle(Color.appAccent)
                        }
                        PlanOrbitView().frame(width: 90, height: 96)
                    }.foregroundStyle(Color.appFG)
                }
            }.buttonStyle(.plain)
        }.padding(.top, 10)
    }

    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discover More").font(StrapTypography.body(23, weight: .bold))
            NavigationLink(value: Route.health) {
                Panel { discoveryRow("Understand your health", detail: "Explore recorded measurements and their quality.", icon: "heart.text.square") }
            }.buttonStyle(.plain)
            NavigationLink(value: Route.settings) {
                Panel { discoveryRow("Your band & data", detail: "Manage history sync, your profile and recorded sources.", icon: StrapIcon.Device.bandSensor) }
            }.buttonStyle(.plain)
            NavigationLink(value: Route.sleepAnalysis) {
                Panel { discoveryRow("Explore your sleep data", detail: "Review a night and export its recorded sensor channels.", icon: "moon.stars") }
            }.buttonStyle(.plain)

            HStack {
                Spacer()
                Button {
                    // Discover More
                } label: {
                    Text("DISCOVER MORE")
                        .font(StrapTypography.body(12, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.appFG)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(hex: 0x252D33), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(hex: 0x3A4650), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 10)
            .padding(.bottom, 20)
        }.padding(.top, 12)
    }

    private func discoveryRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(StrapTypography.body(36, weight: .light)).foregroundStyle(Color.appAccent).frame(width: 54)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(StrapTypography.body(16, weight: .bold)).foregroundStyle(Color.appFG)
                Text(detail).font(StrapTypography.body(12)).foregroundStyle(Color.appMuted)
                Label("EXPLORE", systemImage: "arrow.right").font(StrapTypography.body(10, weight: .bold)).foregroundStyle(Color.appAccent)
            }
        }
    }

    // MARK: Day navigation helpers

    private var shiftedDate: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }

    private var dayLabel: String {
        dayOffset == 0 ? "TODAY" : Self.shortDayFormatter.string(from: shiftedDate).uppercased()
    }

    private var subtitle: String {
        if dayOffset != 0 {
            return "Past day · activities only"
        }
        let date = Self.longDateFormatter.string(from: shiftedDate)
        if demo { return "\(date) · design preview" }
        return store.lastCapture == nil
            ? "\(date) · waiting for first capture"
            : "\(date) · latest capture loaded"
    }

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d"
        return formatter
    }()

    private static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()
}

private struct PlanOrbitView: View {
    private let symbols = ["moon.stars", "heart", "figure.strengthtraining.traditional", "book.closed"]
    private let positions: [CGPoint] = [CGPoint(x: 62, y: 24), CGPoint(x: 23, y: 39), CGPoint(x: 34, y: 77), CGPoint(x: 75, y: 67)]
    var body: some View {
        ZStack {
            ForEach(0..<4) { index in
                ZStack {
                    Circle().stroke(Color.appMuted.opacity(0.2), lineWidth: 2)
                    Circle().trim(from: 0.05, to: index == 0 ? 0.8 : 0.5)
                        .stroke(Color.appGood, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: symbols[index]).font(.system(size: index == 0 ? 18 : 12)).foregroundStyle(Color.appMuted)
                }.frame(width: index == 0 ? 46 : 30, height: index == 0 ? 46 : 30).position(positions[index])
            }
        }.accessibilityHidden(true)
    }
}

// Count distinct calendar days on which STRAP was opened. This is intentionally
// not the number of historical WHOOP days, and not a consecutive-day streak.
// Persist locally; do not fabricate visits before this counter was introduced.
enum AppOpenDayTracker {
    static let key = "strap.app.open.days.v1"

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func count(defaults: UserDefaults = .standard) -> Int {
        Set(defaults.stringArray(forKey: key) ?? []).count
    }

    @discardableResult
    static func recordOpen(at date: Date = Date(), defaults: UserDefaults = .standard,
                           calendar: Calendar = .current) -> Int {
        var days = Set(defaults.stringArray(forKey: key) ?? [])
        days.insert(dayKey(date, calendar: calendar))
        defaults.set(days.sorted(), forKey: key)
        return days.count
    }
}

// Clean-room rendering of the supplied band-battery reference.
private struct WhoopBandBatteryIcon: View {
    let charge: Int?
    let connected: Bool
    var isCharging: Bool = false

    private var strokeColor: Color {
        if let charge = charge, charge < 20, !isCharging {
            return Color.appWarn
        }
        return Color.appFG
    }

    var body: some View {
        // Traced from the user's WHOOP battery reference. The right shoulder
        // is intentionally interrupted by the connection dot; the central
        // descending contour is separate from the exterior band silhouette.
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 8.1, y: 1.3))
                p.addCurve(to: CGPoint(x: 17.0, y: 1.3),
                           control1: CGPoint(x: 10.1, y: 0.8), control2: CGPoint(x: 14.6, y: 1.3))
                p.move(to: CGPoint(x: 8.1, y: 1.3))
                p.addCurve(to: CGPoint(x: 2.5, y: 20.8),
                           control1: CGPoint(x: 3.5, y: 4.1), control2: CGPoint(x: 1.5, y: 15.2))
                p.addCurve(to: CGPoint(x: 6.4, y: 26.6),
                           control1: CGPoint(x: 3.0, y: 25.3), control2: CGPoint(x: 4.3, y: 26.6))
                p.addLine(to: CGPoint(x: 15.0, y: 26.6))
                p.addCurve(to: CGPoint(x: 19.4, y: 14.0),
                           control1: CGPoint(x: 18.3, y: 26.6), control2: CGPoint(x: 19.4, y: 20.2))
            }
            .stroke(strokeColor, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))

            Path { p in
                p.move(to: CGPoint(x: 16.9, y: 1.4))
                p.addCurve(to: CGPoint(x: 13.1, y: 20.8),
                           control1: CGPoint(x: 13.7, y: 6.8), control2: CGPoint(x: 12.2, y: 15.8))
                p.addCurve(to: CGPoint(x: 14.5, y: 23.5),
                           control1: CGPoint(x: 13.1, y: 22.3), control2: CGPoint(x: 13.7, y: 23.0))
                p.move(to: CGPoint(x: 3.8, y: 20.6))
                p.addLine(to: CGPoint(x: 9.6, y: 20.6))
            }
            .stroke(strokeColor, style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))

            if isCharging {
                // Charging lightning bolt indicator centered in cavity
                Path { p in
                    p.move(to: CGPoint(x: 8.5, y: 4.0))
                    p.addLine(to: CGPoint(x: 5.5, y: 11.5))
                    p.addLine(to: CGPoint(x: 8.5, y: 11.5))
                    p.addLine(to: CGPoint(x: 6.5, y: 19.0))
                    p.addLine(to: CGPoint(x: 11.5, y: 10.0))
                    p.addLine(to: CGPoint(x: 8.5, y: 10.0))
                    p.closeSubpath()
                }
                .fill(Color(hex: 0x24E7A5))
            }

            if connected {
                Circle()
                    .fill(Color(hex: 0x24E7A5))
                    .frame(width: 6.2, height: 6.2)
                    .overlay(Circle().stroke(Color.appCanvasTop, lineWidth: 0.7))
                    .offset(x: 16.8, y: 4.4)
            }
        }
        .frame(width: 23, height: 28)
        .scaleEffect(0.86)
        .frame(width: 20, height: 24)
        .accessibilityHidden(true)
    }
}


// Clean-room Device Settings layout based on the supplied STATUS and ADVANCED screenshots.
// Device maintenance actions are intentionally informational until independently verified.
private struct HomeBandDeviceSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var advanced = false
    private let muted = Color.appMuted
    private let panel = Color(hex: 0x252D33)
    @State private var showPairingSheet = false
    @State private var showUnpairConfirmation = false
    @State private var showRebootConfirmation = false
    @State private var showRegulatoryLabels = false

    var body: some View {
        VStack(spacing: 0) {
            // HEADER BAR
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.appFG)
                }
                Spacer()
                Text("DEVICE SETTINGS")
                    .font(StrapTypography.body(15, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color.appFG)
                Spacer()
                Image(systemName: "xmark")
                    .font(.system(size: 18))
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)

            // CONNECTED DEVICE STATUS & SYNC BANNER
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.band.isConnected ? "CONNECTED TO" : "DISCONNECTED")
                        .foregroundStyle(store.band.isConnected ? Color.appGood : muted)
                        .font(StrapTypography.body(11, weight: .bold))
                        .tracking(1.0)
                    Text(store.band.preferredBandName ?? "WHOOP MG")
                        .font(StrapTypography.body(17, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.appFG)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("LAST HISTORY SYNC")
                        .foregroundStyle(muted)
                        .font(StrapTypography.body(10, weight: .bold))
                        .tracking(0.6)
                    Text(store.band.lastHistorySyncAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                        .font(StrapTypography.body(13, weight: .bold))
                        .foregroundStyle(Color.appFG)
                }
                Image(systemName: store.band.lastHistorySyncAt == nil ? "icloud" : "checkmark.icloud")
                    .font(.system(size: 22))
                    .foregroundStyle(muted)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            // SEGMENTED TABS: STATUS vs ADVANCED
            HStack(spacing: 36) {
                tab("STATUS", selected: !advanced) { advanced = false }
                tab("ADVANCED", selected: advanced) { advanced = true }
                Spacer()
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 6)

            ScrollView {
                if advanced {
                    advancedContent
                } else {
                    statusContent
                }
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(Color.white)
        .sheet(isPresented: $showPairingSheet) { PairDeviceView().environmentObject(store) }
        .sheet(isPresented: $showRegulatoryLabels) { regulatoryLabelsSheet }
        .confirmationDialog("Unpair WHOOP Band?", isPresented: $showUnpairConfirmation, titleVisibility: .visible) {
            Button("Unpair Device", role: .destructive) { store.unpairBand() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Disconnects the band and clears the saved STRAP association. Historical data is retained.") }
        .confirmationDialog("Reboot WHOOP Band?", isPresented: $showRebootConfirmation, titleVisibility: .visible) {
            Button("Reboot Device", role: .destructive) { store.rebootBand() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("It will take a few moments to reboot your WHOOP. Historical data stored on your band and phone is preserved.") }
        .background {
            LinearGradient.appCanvas
                .ignoresSafeArea()
        }
    }

    private func tab(_ name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(name)
                    .font(StrapTypography.body(11, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(selected ? Color.white : muted)
                Rectangle()
                    .fill(selected ? Color.white : Color.clear)
                    .frame(height: 2)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
    }

    private var statusContent: some View {
        VStack(spacing: 20) {
            // HARDWARE ARTWORK HERO & VERTICAL BATTERY GAUGE
            HStack(alignment: .center, spacing: 18) {
                BandIllustrationView(
                    status: store.band.status,
                    isConnected: store.band.isConnected,
                    batteryPercent: store.band.batteryPercent
                )
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .accessibilityLabel("WHOOP MG genuine band hardware with live indicator")

                VStack(alignment: .trailing, spacing: 6) {
                    Text(store.band.batteryPercent.map { "\($0)%" } ?? "—")
                        .font(StrapTypography.metric(34, weight: .bold))
                        .foregroundStyle(batteryColor)

                    Text("OF CHARGE\nREMAINING")
                        .font(StrapTypography.metric(9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(muted)
                        .multilineTextAlignment(.trailing)

                    Text(store.band.modelNumber ?? store.band.preferredBandName ?? "WHOOP MG")
                        .font(StrapTypography.body(11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(muted)
                }

                // VERTICAL BATTERY CAPSULE GAUGE
                Capsule().fill(Color(hex: 0x2A333A))
                    .frame(width: 6, height: 140)
                    .overlay(alignment: .bottom) {
                        GeometryReader { geo in
                            VStack {
                                Spacer(minLength: 0)
                                Capsule().fill(batteryColor)
                                    .frame(height: geo.size.height * CGFloat(min(100, max(0, store.band.batteryPercent ?? 0))) / 100)
                            }
                        }
                    }
            }
            .frame(height: 280)
            .padding(.horizontal, 24)

            // BROADCAST HEART RATE
            deviceRow(
                "BROADCAST HEART RATE",
                icon: "heart.fill",
                subtitle: "TO COMPATIBLE APPS & DEVICES",
                enabled: store.band.isConnected,
                isToggle: true,
                toggleValue: store.band.isBroadcastingHR,
                onToggle: { enabled in
                    store.setBroadcastHeartRate(enabled: enabled)
                }
            )
            Text(store.band.isConnected
                 ? "Verified Command 14 (0x0E) enables standard BLE 0x180D heart-rate broadcast to gym equipment and apps."
                 : "Connect your WHOOP to adjust live broadcast.")
                .font(StrapTypography.body(11))
                .foregroundStyle(muted)
                .padding(.horizontal, 24)
        }
        .padding(.top, 16)
        .padding(.bottom, 36)
    }

    private var batteryColor: Color {
        guard let p = store.band.batteryPercent else { return muted }
        if p >= 50 { return Color.appGood }
        if p >= 20 { return Color.appWarn }
        return Color.appHigh
    }

    private var advancedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                metadata("DEVICE ID", value: store.band.serialNumber ?? "UNAVAILABLE", icon: StrapIcon.Device.bandSensor)
                metadata("FIRMWARE", value: store.band.firmwareRevision ?? "UNVERIFIED", icon: "cpu")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
            .padding(.bottom, 36)

            Button { showPairingSheet = true } label: {
                deviceRow("PAIR A DEVICE", icon: "plus.rectangle.on.rectangle", subtitle: "Scan and select a nearby WHOOP band.", enabled: true)
            }.buttonStyle(.plain)

            Button { showUnpairConfirmation = true } label: {
                deviceRow("UNPAIR DEVICE", icon: "minus.rectangle", subtitle: "Disconnect and clear the saved STRAP association.", enabled: store.band.preferredBandID != nil || store.band.isConnected)
            }.buttonStyle(.plain).disabled(store.band.preferredBandID == nil && !store.band.isConnected)

            Button { showRegulatoryLabels = true } label: {
                deviceRow("REGULATORY LABELS", icon: "tag",
                          subtitle: "Manufacturer regulatory information; no unverified labels are generated.", enabled: true)
            }.buttonStyle(.plain)

            Link(destination: URL(string: "https://support.whoop.com/s/topic/0TO6Q000000gQa7WAE/regulatory-information")!) {
                deviceRow("SAFETY & REGULATORY", icon: "tag",
                          subtitle: "Open official WHOOP safety and regulatory information.", enabled: true)
            }.buttonStyle(.plain)

            deviceRow("FIRMWARE CHECK", icon: "cpu",
                      subtitle: "Updates disabled. Custom firmware flashing (0x53, 0x8E–0x90) is restricted to official signed images to prevent bricking.", enabled: false)

            Button {
                showRebootConfirmation = true
            } label: {
                deviceRow("REBOOT DEVICE", icon: "power",
                          subtitle: store.band.isRebooting ? "WHOOP is restarting and will reconnect automatically..." : "Verified warm restart (0x1D). Preserves circular flash history without data loss.",
                          enabled: store.band.isConnected && !store.band.isRebooting)
            }
            .buttonStyle(.plain)
            .disabled(!store.band.isConnected || store.band.isRebooting)

            deviceRow("ERASE DEVICE DATA", icon: "trash",
                      subtitle: "Unavailable: protects stored circular buffer sensor history from irreversible deletion (FORCE_TRIM 0x19 quarantined).", enabled: false)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 36)
    }

    private var regulatoryLabelsSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("REGULATORY LABELS").font(StrapTypography.body(17, weight: .bold))
                Text("STRAP cannot verify manufacturer regulatory markings from the band telemetry. Open WHOOP's official regulatory information instead of displaying invented labels.")
                    .font(StrapTypography.body(13))
                Link("VIEW OFFICIAL WHOOP REGULATORY INFORMATION",
                     destination: URL(string: "https://support.whoop.com/s/topic/0TO6Q000000gQa7WAE/regulatory-information")!)
                Spacer()
            }
            .padding(24)
            .navigationTitle("Regulatory Labels")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { showRegulatoryLabels = false }
            } }
        }
    }

    private func metadata(_ title: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 23)).foregroundStyle(muted)
            Text(title).font(StrapTypography.body(11, weight: .bold)).foregroundStyle(muted)
            Text(value).font(StrapTypography.body(11, weight: .bold))
        }
    }

    private func deviceRow(
        _ title: String,
        icon: String,
        subtitle: String,
        enabled: Bool,
        isToggle: Bool = false,
        toggleValue: Bool = false,
        onToggle: ((Bool) -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 26)
                    .foregroundStyle(muted)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(StrapTypography.body(13, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.appFG)
                    if isToggle {
                        Text(subtitle)
                            .font(StrapTypography.body(10))
                            .foregroundStyle(muted)
                    }
                }
                Spacer(minLength: 8)
                if isToggle {
                    Toggle(title, isOn: Binding(
                        get: { toggleValue },
                        set: { onToggle?($0) }
                    ))
                    .labelsHidden()
                    .disabled(!enabled)
                    .tint(Color.appGood)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: 58)
            .background(panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.appCardBorder.opacity(0.5), lineWidth: 0.5)
            )

            if !isToggle {
                Text(subtitle)
                    .font(StrapTypography.body(11))
                    .foregroundStyle(muted)
                    .padding(.horizontal, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.bottom, 22)
    }
}


enum HomeRefreshConstants {
    static let diameter: CGFloat = 30.0
    static let arcStrokeWidth: CGFloat = 1.6
    static let arcTrimFraction: CGFloat = 0.84
    static let arcGapStartAngleDegrees: Double = -150.0
    static let glyphStrokeWidth: CGFloat = 1.6
    static let glyphSize: CGFloat = 14.0
    static let indicatorToTitleGap: CGFloat = 14.0
    static let titleToRingsGap: CGFloat = 14.0
}

struct WhoopWGlyph: View, Equatable {
    var color: Color = Color.appMuted.opacity(0.85)

    static let pathPoints: [(start: CGPoint, end: CGPoint)] = [
        (start: CGPoint(x: 1.2, y: 0.4), end: CGPoint(x: 3.4, y: 8.2)),
        (start: CGPoint(x: 9.4, y: 0.4), end: CGPoint(x: 5.1, y: 13.8)),
        (start: CGPoint(x: 10.8, y: 5.6), end: CGPoint(x: 13.6, y: 11.2))
    ]

    var body: some View {
        Path { path in
            for stroke in Self.pathPoints {
                path.move(to: stroke.start)
                path.addLine(to: stroke.end)
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: HomeRefreshConstants.glyphStrokeWidth, lineCap: .round, lineJoin: .round))
        .frame(width: HomeRefreshConstants.glyphSize, height: HomeRefreshConstants.glyphSize)
    }
}

enum HomeHistoryRefresh {
    static func isActive(status: BandStatus, saving: Bool, analyzing: Bool, failed: Bool) -> Bool {
        guard !failed else { return false }
        return status == .authenticating || status == .draining || saving || analyzing
    }

    static func canRequest(status: BandStatus, saving: Bool, analyzing: Bool) -> Bool {
        guard !saving, !analyzing else { return false }
        switch status {
        case .authenticating, .draining, .scanning, .connecting, .reconnecting:
            return false
        default:
            return true
        }
    }
}
