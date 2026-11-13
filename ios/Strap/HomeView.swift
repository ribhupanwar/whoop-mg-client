import SwiftUI

/// Home — ports the approved mockup's structure and ordering.
/// Live mode: every unmeasured metric is "—"; waiting states say what is needed.
/// Demo mode: labelled sample values behind the persistent banner.
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    let openPlan: () -> Void

    @State private var compactScores = false
    @State private var dayOffset = 0
    @State private var showLogger = false
    @State private var showLiveSession = false
    @State private var editingDetectedID: String?
    @State private var correctedKind: ActivityKind = .other
    @State private var correctedLabels: [String: String] = UserDefaults.standard.dictionary(forKey: "strap.detected.activity.labels.v1") as? [String: String] ?? [:]
    @State private var showDashboardCustomize = false
    @State private var showSleepEditor = false
    @State private var correctedSleepStart = Date()
    @State private var correctedSleepEnd = Date()
    private var sleepCorrections: [String: [Int]] {
        UserDefaults.standard.dictionary(forKey: SleepCorrectionStore.defaultsKey) as? [String: [Int]] ?? [:]
    }

    private var demo: Bool { store.isPreview }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                Text("STRAP")
                    .font(StrapTypography.body(20, weight: .bold)).tracking(2)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                ringTrio
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: HomeHeroPosition.self,
                            value: geometry.frame(in: .named("home-scroll")).maxY)
                    })
                monitorDuo
                myDayOutlook
                tonightCard
                activitiesCard
                journalCard
                planCard
                dashboardSection
                CombinedLoadChart()
                discoverSection
            }
        }
        .coordinateSpace(name: "home-scroll")
        .onPreferenceChange(HomeHeroPosition.self) { value in
            // Hysteresis prevents repeated whole-home re-layout while dragging
            // near the hero boundary. Do not animate every scroll-position update.
            let shouldCompact = compactScores ? value < 80 : value < 0
            guard shouldCompact != compactScores else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { compactScores = shouldCompact }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                topBar
                if dayOffset != 0 {
                    Text("Activity history · scores show the latest recorded day")
                        .font(.system(size: 9)).foregroundStyle(Color.appMuted).padding(.bottom, 5)
                }
                if compactScores { compactRingRow }
            }
            .padding(.horizontal, AppLayout.screenInset)
            .padding(.top, 8)
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
        .refreshable {
            if store.band.isConnected {
                store.band.readHistory()
            } else {
                store.connectBand()
            }
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
                        .font(.footnote)
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
                    Text("Bed and wake times are editable. Recovery uses estimated time asleep (excluding awake periods); HRV and RHR remain sensor-derived.")
                        .font(.footnote)
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
        .sheet(isPresented: $showDashboardCustomize) {
            DashboardCustomizeSheet()
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            NavigationLink(value: Route.settings) {
                Image(systemName: "person.fill").font(.system(size: 17))
                    .foregroundStyle(Color.appBG).frame(width: 32, height: 32)
                    .background(LinearGradient(colors: [Color(hex: 0x80F5DE), Color(hex: 0x51BADB)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("Profile and settings")
            HStack(spacing: 4) {
                Image(systemName: "flame.fill").foregroundStyle(Color.orange)
                Text("\(store.recordedDayCount)").font(.system(size: 11, weight: .bold))
            }.padding(.horizontal, 8).padding(.vertical, 7)
                .background(LinearGradient.appCard, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("\(store.recordedDayCount) recorded days")

            Spacer()

            HStack(spacing: 0) {
                Button {
                    if dayOffset > -6 { dayOffset -= 1 }
                } label: {
                    Text("‹").font(.system(size: 16)).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(dayOffset <= -6)
                .foregroundStyle(dayOffset <= -6 ? Color.appLine : Color.appFG)

                Text(dayLabel)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.9)
                    .foregroundStyle(Color.appFG)
                    .frame(minWidth: 62)

                Button {
                    if dayOffset < 0 { dayOffset += 1 }
                } label: {
                    Text("›").font(.system(size: 16)).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .disabled(dayOffset >= 0)
                .foregroundStyle(dayOffset >= 0 ? Color.appLine : Color.appFG)
            }
            .padding(2)
            .background(Capsule().fill(Color.appRaised))

            Spacer()

            HStack(spacing: 5) {
                Text(demo ? "\(SampleData.batteryPercent)%" : batteryText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
                Image(systemName: batterySymbol)
                    .font(.system(size: 14))
                    .foregroundStyle(batteryColor)
            }

        }
        .padding(.bottom, 10)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Home")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.appFG)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
        }
        .padding(.bottom, 12)
    }

    // MARK: Trio rings

    private var ringTrio: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                NavigationLink(value: Route.sleepAnalysis) {
                    trioItem(
                        label: "SLEEP ›",
                        text: demo ? "\(SampleData.sleepRingPercent)%" : percentText(sleepPercent),
                        progress: demo ? Double(SampleData.sleepRingPercent) / 100.0 : sleepPercent.map { Double($0) / 100.0 },
                        color: .appSleep
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: Route.recovery) {
                    trioItem(
                    label: "RECOVERY ›",
                    text: demo ? "\(SampleData.recoveryRingPercent)%" : percentText(recoveryScore.map { Int($0.rounded()) }),
                    progress: demo ? Double(SampleData.recoveryRingPercent) / 100.0 : recoveryScore.map { $0 / 100.0 },
                    color: DetailMetric.recovery.color(recoveryScore)
                    )
                }
                .buttonStyle(.plain)
                NavigationLink(value: Route.strain) {
                    trioItem(
                    label: "STRAIN ›",
                    text: demo ? String(format: "%.1f", SampleData.strain) : strain.map { String(format: "%.1f", $0) } ?? "—",
                    progress: demo ? SampleData.strain / 21.0 : strain.map { $0 / 21.0 },
                    color: .appAccent
                    )
                }
                .buttonStyle(.plain)
            }
            if !demo && !trioHint.isEmpty { Hint(trioHint) }
        }
        .padding(.bottom, 20)
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
        // Keep the Home ring consistent with the daily Strain History bar.
        let today = JournalStore.dayKey(for: Date())
        // Never substitute a capture-wide score for today's day score:
        // it may include a different date or an invalid sleep exclusion.
        return store.band.days.first(where: { $0.dateKey == today })?.strain
    }

    private var displayedBattery: Int? {
        demo ? SampleData.batteryPercent : store.band.batteryPercent
    }

    private var batterySymbol: String {
        guard let percent = displayedBattery else { return "battery.0" }
        switch percent {
        case 88...: return "battery.100"
        case 63...: return "battery.75"
        case 38...: return "battery.50"
        case 13...: return "battery.25"
        default: return "battery.0"
        }
    }

    private var batteryColor: Color {
        guard let percent = displayedBattery else { return .appMuted }
        if percent <= 10 { return .appHigh }
        if percent <= 20 { return .appWarn }
        return .appMuted
    }

    private var batteryText: String {
        guard let battery = store.band.batteryPercent else { return "—" }
        return "\(battery)%"
    }

    private func trioItem(label: String, text: String, progress: Double?, color: Color) -> some View {
        VStack(spacing: 8) {
            RingView(progress: progress, color: color, lineWidth: 6, size: 82, centerText: text)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .tracking(0.9)
                .foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Insight

    private var insightCard: some View {
        Panel {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(demo ? "Elevated HRV" : insightTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text(demo
                         ? "Sample: your HRV is 6% above your usual, which signals strong recovery. A planned threshold run or heavy lift both fit today."
                         : insightBody)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appMuted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appGood)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.appRaised))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
                    Text(demo ? "1" : "\(store.recordedDayCount)")
                        .font(.system(size: 11))
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
            return "Last capture: \(summary.sampleCount) s · \(rhr) · HRV \(hrv). Long enough for a baseline day."
        }
        return "Strap reads your band locally. Sleep, recovery and HRV insights appear once overnight and daytime captures exist — nothing is estimated until then."
    }

    // MARK: Monitor duo

    private var monitorDuo: some View {
        HStack(spacing: 10) {
            NavigationLink(value: Route.health) {
                tapCard(
                    title: "Health monitor",
                    pill: demo ? "✓" : healthPill,
                    pillColor: demo ? .appGood : (healthCount > 0 ? .appGood : .appWarn),
                    state: demo ? "WITHIN RANGE" : (healthCount > 0 ? "CAPTURED" : "WAITING"),
                    stateColor: demo ? .appGood : (healthCount > 0 ? .appGood : .appWarn),
                    detail: demo ? "4/4 metrics · sample" : healthDetail
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: Route.stress) {
                tapCard(
                    title: "Stress monitor",
                    pill: demo ? String(format: "%.1f", SampleData.stressHome) : stressPill,
                    pillColor: demo ? .appAccent : .appMuted,
                    state: demo ? "LOW" : store.band.stress.band.uppercased(),
                    stateColor: demo ? .appAccent : .appWarn,
                    detail: demo ? "11:49 · sample" : stressDetail
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 14)
    }

    private var healthCount: Int {
        guard let summary = store.lastCapture else { return 0 }
        let flags = [
            summary.hrv.rmssdMS != nil,
            store.measuredRestingHR != nil,
            summary.lastHeartRate != nil,
            summary.steps != nil
        ]
        return flags.filter { $0 }.count
    }

    private var healthPill: String { "\(healthCount)/4" }

    private var healthDetail: String {
        guard let summary = store.lastCapture else { return "needs a capture" }
        return "last capture · \(summary.sampleCount) s"
    }

    private var stressPill: String {
        guard let index = store.band.stress.index else { return "—" }
        return String(format: "%.1f", index)
    }

    private var stressDetail: String {
        store.band.stress.reason ?? "awake baseline · \(store.recordedDayCount)/7 days"
    }

    private func tapCard(title: String, pill: String, pillColor: Color, state: String, stateColor: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(Color.appFG)
                Spacer()
                Text("›").font(.system(size: 15)).foregroundStyle(Color.appMuted)
            }
            HStack(spacing: 7) {
                Text(pill)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(pillColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.appRaised))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(state)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(stateColor)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.appMuted)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient.appCard))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
    }

    // MARK: My Day

    private var myDayOutlook: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("My Day").font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.appFG)
                Spacer()
                Button { showLogger = true } label: {
                    Image(systemName: "plus").font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.appBG).frame(width: 40, height: 40)
                        .background(Color.appFG, in: RoundedRectangle(cornerRadius: 11))
                }.buttonStyle(.plain).accessibilityLabel("Add activity")
            }
            Button(action: openPlan) {
                HStack(spacing: 10) {
                    Image(systemName: "moon")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.appWarn)
                    Text("Your Day in Review")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Text("›").font(.system(size: 15)).foregroundStyle(Color.appMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [Color(hex: 0x392F59), Color(hex: 0x214856)], startPoint: .leading, endPoint: .trailing)
                )
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 11)
    }

    // MARK: Today's activities

    private var activitiesCard: some View {
        Panel {
            CardHead(title: "Today's activities", trailing: "⤢")

            NavigationLink(value: Route.sleepAnalysis) {
                HStack(spacing: 11) {
                    HStack(spacing: 7) {
                        Image(systemName: "moon.fill").font(.system(size: 12))
                        Text(demo ? SampleData.lastNightSleep : lastNightText)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: 0x0D1219))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.appSleep))

                    Text("SLEEP")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(0.8)
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Text(demo ? "00:26\n07:33" : sleepTimesText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.appMuted)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.appRaised))
            }
            .buttonStyle(.plain)
            .contextMenu {
                if !demo, latestSleepPeriod != nil {
                    Button("Edit sleep time") { openHomeSleepEditor() }
                }
            }
            .padding(.bottom, 4)
            VStack(spacing: 8) {
                if demo {
                    activityRow(icon: "figure.run", name: "Run", detail: "42 min · Z2")
                    activityRow(icon: "figure.walk", name: "Walk", detail: "28 min · errands")
                    activityRow(icon: "dumbbell.fill", name: "Gym workout", detail: "55 min · push")
                    activityRow(icon: "clock", name: "Rest session", detail: "15 min · measured")
                } else {
                    ForEach(timedRows, id: \.id) { row in
                        HStack(spacing: 6) {
                            activityRow(icon: row.icon, name: row.name, detail: row.detail)
                            if row.id.hasPrefix("band-") {
                                Button {
                                    editingDetectedID = row.id
                                    correctedKind = ActivityKind(rawValue: correctedLabels[row.id] ?? "") ?? .other
                                } label: {
                                    Image(systemName: "pencil.circle")
                                        .font(.system(size: 19))
                                        .foregroundStyle(Color.appAccent)
                                }
                                .accessibilityLabel("Edit activity")
                                .buttonStyle(.plain)
                            }
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
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
                            .font(.system(size: 11))
                            .foregroundStyle(Color.appMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.bottom, 10)

        }
    }

    // MARK: Activity rows

    private func openHomeSleepEditor() {
        guard let period = latestSleepPeriod else { return }
        let session = store.band.latestSleepSession
        let times = SleepCorrectionStore.times(for: period, overrides: sleepCorrections)
        correctedSleepStart = Date(timeIntervalSince1970: TimeInterval(session?.startUnix ?? times?.first ?? period.startUnix))
        correctedSleepEnd = Date(timeIntervalSince1970: TimeInterval(session?.endUnix ?? times?.last ?? (period.endUnix + 1)))
        showSleepEditor = true
    }

    private struct ActivityRowModel: Identifiable {
        let id: String
        let icon: String
        let name: String
        let detail: String
        let startUnix: Int?
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
        return "\(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(start))))–\(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(end))))"
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
            let key = "band-\(session.startUnix)"
            let corrected = correctedLabels[key].flatMap(ActivityKind.init(rawValue:))
            return ActivityRowModel(
                id: key,
                icon: corrected?.icon ?? Self.icon(forDetected: session.kind),
                name: "\(corrected?.label ?? session.kind.capitalized) · band",
                detail: "\(Self.clockRange(session.startUnix, session.endUnix)) · \(minutes) min\(steps)\(heart)\(kcal)",
                startUnix: session.startUnix
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
                detail: "\(Self.clockRange(record.startedUnix, record.endedUnix)) · \(minutes) min\(heart)\(kcal)",
                startUnix: record.startedUnix
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

    private static func icon(forDetected kind: String) -> String {
        switch kind {
        case "run": return "figure.run"
        case "walk": return "figure.walk"
        case "workout": return "dumbbell.fill"
        case "cardio": return "heart.fill"
        default: return "figure.mixed.cardio"
        }
    }

    private func activityRow(icon: String, name: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 25, weight: .medium))
                .foregroundStyle(Color.appFG).frame(width: 64, height: 48)
                .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 9))
            Text(name.uppercased()).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.appFG)
            Spacer(minLength: 8)
            Text(detail).font(.system(size: 10.5)).foregroundStyle(Color.appMuted)
                .multilineTextAlignment(.trailing).frame(maxWidth: 140)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appRaised))
    }

    private func activityButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
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
        Panel {
            HStack {
                Text("TONIGHT'S SLEEP")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Color.appFG)
                Spacer()
                NavigationLink(value: Route.sleepCoach) {
                    Text("›")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.appMuted)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.bottom, 6)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(demo ? SampleData.bedtime : CoachFormat.clock(bedtimeRecommendation.bedtimeMinutes))
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text("RECOMMENDED\nBEDTIME")
                        .font(.system(size: 9.5))
                        .tracking(0.7)
                        .foregroundStyle(Color.appMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle().fill(Color.appLine).frame(width: 26, height: 1)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(demo ? SampleData.latestAlarm : CoachFormat.clock(store.settings.wakeTimeMinutes))
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text("ALARM ON\nEXACT TIME")
                        .font(.system(size: 9.5))
                        .tracking(0.7)
                        .foregroundStyle(Color.appMuted)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            NavigationLink(value: Route.sleepCoach) {
                Label("EDIT ALARM", systemImage: "pencil")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.appFG)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.appRaised, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain).padding(.top, 14)
            Text(WakeAlarm.isEnabled ? "PHONE ALARM ON" : "PHONE ALARM OFF")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WakeAlarm.isEnabled ? Color.appGood : Color.appMuted).padding(.top, 7)
            DisclosureGroup("How bedtime is calculated") {
                Text("Your wake time, stated sleep need, tomorrow's intent and recorded sleep debt determine this recommendation. The alarm is a phone notification.")
                    .font(.system(size: 11)).foregroundStyle(Color.appMuted)
            }.font(.system(size: 10)).tint(Color.appMuted).padding(.top, 8)
        }
    }

    private var bedtimeRecommendation: SleepRecommendation {
        SleepCoach.recommendation(
            baseNeedHours: store.settings.sleepNeedHours,
            intent: store.settings.sleepIntent,
            debtHours: SleepCoach.sleepDebt(nights: store.recordedNights),
            wakeMinutes: store.settings.wakeTimeMinutes
        )
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
        if let session = store.band.latestSleepSession {
            return "\(Self.sleepClock(session.startUnix, includeDay: true))\n\(Self.sleepClock(session.endUnix, includeDay: false))"
        }
        if store.band.isAnalyzingHistory { return "Updating…" }
        guard let period = latestSleepPeriod else { return "wear it\ntonight" }
        let times = SleepCorrectionStore.times(for: period, overrides: sleepCorrections)
        return "\(Self.sleepClock(times?.first ?? period.startUnix, includeDay: true))\n\(Self.sleepClock(times?.last ?? (period.endUnix + 1), includeDay: false))"
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
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Color.appFG)
                Spacer()
                NavigationLink(value: Route.journal) {
                    Text("✎ FILL OUT")
                        .font(.system(size: 10, weight: .medium))
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
                                .font(.system(size: 9, weight: .semibold))
                            Image(systemName: store.journalEntries[key] == nil ? "circle" : "checkmark.circle.fill")
                                .font(.system(size: 20, weight: .light))
                        }.foregroundStyle(store.journalEntries[key] == nil ? Color.appMuted : Color.appGood)
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }
            }.padding(.vertical, 14)
            NavigationLink(value: Route.journal) {
                Label("BEHAVIOR INSIGHTS", systemImage: "lightbulb")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.appFG)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.appRaised, in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain)
            Text(journalStateText)
                .font(.system(size: 11))
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
                        .font(StrapTypography.body(11, weight: .semibold))
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
        HStack(spacing: 16) {
            compactRing("SLEEP", route: .sleepAnalysis, progress: sleepPercent.map { Double($0) / 100 }, color: .appSleep)
            compactRing("RECOVERY", route: .recovery, progress: recoveryScore.map { $0 / 100 }, color: DetailMetric.recovery.color(recoveryScore))
            compactRing("STRAIN", route: .strain, progress: strain.map { $0 / 21 }, color: .appAccent)
        }.padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactRing(_ title: String, route: Route, progress: Double?, color: Color) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 6) {
                RingView(progress: progress, color: color, lineWidth: 2, size: 20, centerText: "")
                Text(title).font(.system(size: 9, weight: .bold)).tracking(0.5)
            }.foregroundStyle(Color.appFG)
        }.buttonStyle(.plain)
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Plan").font(StrapTypography.body(24, weight: .bold))
            Button(action: openPlan) {
                Panel {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Build Your Best Self").font(StrapTypography.body(18, weight: .bold))
                            Text("Set goals, track progress, and build a consistent routine.").font(.system(size: 12)).foregroundStyle(Color.appMuted)
                            Label("EXPLORE PLANS", systemImage: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.appAccent)
                        }
                        PlanOrbitView().frame(width: 90, height: 96)
                    }.foregroundStyle(Color.appFG)
                }
            }.buttonStyle(.plain)
        }.padding(.top, 10)
    }

    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Discover More").font(.system(size: 23, weight: .semibold))
            NavigationLink(value: Route.health) {
                Panel { discoveryRow("Understand your health", detail: "Explore recorded measurements and their quality.", icon: "heart.text.square") }
            }.buttonStyle(.plain)
            NavigationLink(value: Route.settings) {
                Panel { discoveryRow("Your band & data", detail: "Manage history sync, your profile and recorded sources.", icon: "applewatch") }
            }.buttonStyle(.plain)
            NavigationLink(value: Route.sleepAnalysis) {
                Panel { discoveryRow("Explore your sleep data", detail: "Review a night and export its recorded sensor channels.", icon: "moon.stars") }
            }.buttonStyle(.plain)
        }.padding(.top, 12)
    }

    private func discoveryRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 36, weight: .light)).foregroundStyle(Color.appAccent).frame(width: 54)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.appFG)
                Text(detail).font(.system(size: 12)).foregroundStyle(Color.appMuted)
                Label("EXPLORE", systemImage: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.appAccent)
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

private struct HomeHeroPosition: PreferenceKey {
    static var defaultValue: CGFloat = 200
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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
