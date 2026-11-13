import SwiftUI

/// Home — ports the approved mockup's structure and ordering.
/// Live mode: every unmeasured metric is "—"; waiting states say what is needed.
/// Demo mode: labelled sample values behind the persistent banner.
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    let openPlan: () -> Void

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
    @State private var sleepCorrections: [String: [Int]] =
        UserDefaults.standard.dictionary(forKey: "strap.sleep.time.corrections.v1") as? [String: [Int]] ?? [:]

    private var demo: Bool { store.isPreview }

    var body: some View {
        Screen {
            // Avoid eagerly evaluating the full dashboard and all of its
            // computed metric cards on every BLE-published SwiftUI update.
            LazyVStack(alignment: .leading, spacing: 0) {
                topBar
                titleBlock
                ringTrio
                insightCard
                monitorDuo
                myDayOutlook
                activitiesCard
                tonightCard
                journalCard
                dashboardSection
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
                               let period = latestSleepPeriod {
                                sleepCorrections[String(period.startUnix)] = [
                                    Int(correctedSleepStart.timeIntervalSince1970),
                                    Int(correctedSleepEnd.timeIntervalSince1970)
                                ]
                                UserDefaults.standard.set(sleepCorrections, forKey: "strap.sleep.time.corrections.v1")
                                store.band.notifySleepCorrectionChanged()
                            }
                            showSleepEditor = false
                        }
                        .disabled(correctedSleepEnd <= correctedSleepStart)
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
            ZStack {
                Circle().strokeBorder(Color.appMuted, lineWidth: 1.5)
                Image(systemName: "person.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appMuted)
            }
            .frame(width: 30, height: 30)

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
                Image(systemName: "battery.100")
                    .font(.system(size: 14))
                    .foregroundStyle(demo ? Color.appGood : Color.appMuted)
            }

            NavigationLink(value: Route.settings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.appMuted)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.bottom, 10)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Home")
                .font(.system(size: 24, weight: .medium))
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
                    color: .appGood
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
            if !demo {
                Hint(trioHint)
            }
        }
        .padding(.bottom, 12)
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
        guard let hours = store.band.lastNightHours else { return nil }
        let need = store.settings.sleepNeedHours
        guard need > 0 else { return nil }
        return Int((min(hours / need, 1.0) * 100).rounded())
    }

    private var recoveryScore: Double? { store.band.recovery.score }

    private var strain: Double? {
        // Keep the Home ring consistent with the daily Strain History bar.
        let today = JournalStore.dayKey(for: Date())
        // Never substitute a capture-wide score for today's day score:
        // it may include a different date or an invalid sleep exclusion.
        return store.band.days.first(where: { $0.dateKey == today })?.strain
    }

    private var batteryText: String {
        guard let battery = store.band.batteryPercent else { return "—" }
        return "\(battery)%"
    }

    private func trioItem(label: String, text: String, progress: Double?, color: Color) -> some View {
        VStack(spacing: 8) {
            RingView(progress: progress, color: color, lineWidth: 8, size: 96, centerText: text)
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
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine, lineWidth: 1))
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
        if let sleep = store.band.lastSleepAnalysis {
            return "Last night: \(CoachFormat.duration(sleep.hours)) of sleep, \(Int(sleep.hoursVsNeededPct.rounded()))% of need. \(sleep.wakeEvents) movement bursts ended inside it."
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
                    .font(.system(size: 10.5, weight: .medium))
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
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.appLine, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(state)
                        .font(.system(size: 11, weight: .medium))
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
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.appSurface))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.appLine, lineWidth: 1))
    }

    // MARK: My Day

    private var myDayOutlook: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("My Day")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color.appFG)
            Button(action: openPlan) {
                HStack(spacing: 10) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.appWarn)
                    Text("Your Daily Outlook")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Text("›").font(.system(size: 15)).foregroundStyle(Color.appMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [Color.appRaised, Color.appSurface], startPoint: .leading, endPoint: .trailing)
                )
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 11)
    }

    // MARK: Today's activities

    private var activitiesCard: some View {
        Panel {
            CardHead(title: "Today's activities", trailing: "›")

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
                        .font(.system(size: 11, weight: .medium))
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
            .padding(.bottom, 4)
            if !demo, latestSleepPeriod != nil {
                HStack {
                    Spacer()
                    Button("Edit sleep time") {
                        guard let period = latestSleepPeriod else { return }
                        let times = sleepCorrections[String(period.startUnix)]
                        correctedSleepStart = Date(timeIntervalSince1970: TimeInterval(times?.first ?? period.startUnix))
                        correctedSleepEnd = Date(timeIntervalSince1970: TimeInterval(times?.last ?? period.endUnix))
                        showSleepEditor = true
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appAccent)
                }
                .padding(.bottom, 8)
            }

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
                    }
                    // Manual entries have a date but no recorded start time.
                    // Keep them separate rather than inventing a clock time.
                    ForEach(manualRows, id: \.id) { row in
                        activityRow(icon: row.icon, name: row.name, detail: row.detail)
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

            if !demo {
                Text("Run, walk and gym sessions auto-detect from the band's gait readout, step counter and heart rate — anything sustained 5+ minutes appears here after each capture and stays in the log. Lifting load has to be entered by hand; the band never sees it.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
            }

            HStack(spacing: 9) {
                activityButton("+ ADD ACTIVITY") { showLogger = true }
                activityButton("START ACTIVITY") { showLiveSession = true }
            }
        }
    }

    // MARK: Activity rows

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
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.appMuted)
                .frame(width: 20)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.appFG)
            Spacer()
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.appRaised))
    }

    private func activityButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(Color.appFG)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.appRaised))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.appLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Tonight's sleep

    private var tonightCard: some View {
        Panel {
            HStack {
                Text("TONIGHT'S SLEEP")
                    .font(.system(size: 10.5, weight: .medium))
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
                    Text("LATEST\nALARM")
                        .font(.system(size: 9.5))
                        .tracking(0.7)
                        .foregroundStyle(Color.appMuted)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Hint("Bedtime is worked back from your wake time, sleep need, tomorrow's intent and accumulated sleep debt. Open the coach to change the wake time or intent; debt starts counting from your first recorded night.")
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
        // Use the same measured asleep duration as the Home sleep ring.
        // The edited window length includes awake time and is not sleep.
        guard let hours = store.band.lastNightHours else { return "—" }
        return CoachFormat.duration(hours)
    }

    private var latestSleepPeriod: SleepPeriod? {
        store.lastCapture?.sleepPeriods.max(by: { $0.durationS < $1.durationS })
    }

    private var sleepTimesText: String {
        guard let period = latestSleepPeriod else { return "wear it\ntonight" }
        let times = sleepCorrections[String(period.startUnix)]
        return "\(Self.sleepClock(times?.first ?? period.startUnix, includeDay: true))\n\(Self.sleepClock(times?.last ?? period.endUnix, includeDay: false))"
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
                    .font(.system(size: 10.5, weight: .medium))
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
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine, lineWidth: 1))
                }
            }
            .padding(.bottom, 9)

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
        return "Not filled today — seven yes/no taps, a mood and a soreness pick."
    }

    // MARK: Inline dashboard

    private var dashboardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("My Dashboard")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.appFG)
                Spacer()
                Button {
                    showDashboardCustomize = true
                } label: {
                    Text("CUSTOMIZE ✎")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.7)
                        .foregroundStyle(Color.appAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.appRaised))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.appLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
            .padding(.bottom, 10)

            DashboardRows()
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