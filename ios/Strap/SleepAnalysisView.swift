import SwiftUI

/// Sleep Analysis — every live value below comes from the last stored capture:
/// the detector's sleep periods, the capture HR series and the recorded nights.
/// The hypnogram is a labelled four-class estimate, never a PSG reading.
struct SleepAnalysisView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showMetricInfo = false
    @State private var showNeedInfo = false
    @State private var coachExpanded = false
    @State private var historyWeekOffset = 0
    @State private var sleepExportURL: URL?
    @State private var sleepExportError: String?
    @State private var preparingSleepExport = false
    @State private var showSleepEditor = false
    @State private var confirmEndSleep = false
    @State private var correctedSleepStart = Date()
    @State private var correctedSleepEnd = Date()

    private var demo: Bool { store.isPreview }

    private var analysis: SleepAnalysis? {
        demo ? nil : store.band.lastSleepAnalysis
    }

    private var session: SleepSession? { demo ? nil : store.band.latestSleepSession }

    private var periods: [SleepPeriod] {
        demo ? [] : (store.band.summary?.sleepPeriods ?? [])
    }

    private var nights: [RecordedNight] {
        demo ? [] : store.recordedNights
    }

    private var debt: Double? {
        demo ? nil : SleepCoach.sleepDebt(nights: nights)
    }

    private var typicalRestorativeMinutes: Double {
        if nights.count >= 3 {
            let avgSleepMinutes = nights.map { $0.actualHours * 60 }.reduce(0, +) / Double(nights.count)
            return avgSleepMinutes * 0.43
        }
        // Baseline 3h 36m (216 min) matching WHOOP reference
        return 216.0
    }

    private var typicalHoursVsNeededPct: Double {
        let ratios = nights.compactMap { $0.neededHours > 0 ? ($0.actualHours / $0.neededHours * 100.0) : nil }
        if ratios.count >= 3 {
            return (ratios.reduce(0, +) / Double(ratios.count)).rounded()
        }
        // Baseline 67% matching WHOOP reference
        return 67.0
    }

    private func typicalRange(for stage: SleepStage) -> ClosedRange<Double> {
        // Standard WHOOP reference ranges matching typical sleep architecture
        switch stage {
        case .wake: return 0.07...0.15
        case .light: return 0.35...0.47
        case .deep: return 0.20...0.30
        case .rem: return 0.21...0.31
        }
    }

    private var coachSummaryText: String {
        let name = "Ribhu"
        if let staging, staging.deepMinutes > 0, staging.remMinutes > 0 {
            let total = max(1.0, staging.deepMinutes + staging.lightMinutes + staging.remMinutes + staging.wakeMinutes)
            let deepPct = staging.deepMinutes / total
            let remPct = staging.remMinutes / total
            if deepPct >= 0.20 && remPct >= 0.20 {
                return "Hi \(name) — your deep and REM sleep both outpaced your usual pattern last night 🧩 Your restorative rest was well above baseline."
            }
        }
        if let pct = reconciledHoursVsNeededPct, pct >= 80 {
            return "Hi \(name) — great sleep performance last night set you up with solid restorative rest 🔋"
        }
        if let debt = debt, debt > 1.0 {
            return "Hi \(name) — you logged solid time in bed, but accumulated sleep debt can be repaid over upcoming nights 🌙"
        }
        return "Hi \(name) — your deep and REM sleep both outpaced your usual pattern last night 🧩 Your restorative rest was solid."
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                performancePanel
                componentsPanel
                lastNightPanel
                consistencyPanel
                efficiencyPanel
                stressDetailPanel
                weeklyPanel
                coachButton
            }
        }
        .sheet(isPresented: $showSleepEditor) {
            NavigationStack {
                Form {
                    DatePicker("Bed Time", selection: $correctedSleepStart)
                    DatePicker("Wake Time", selection: $correctedSleepEnd)
                    Button("End Sleep") {
                        confirmEndSleep = true
                    }
                    .disabled(correctedSleepEnd <= correctedSleepStart || editablePeriod == nil)
                    .accessibilityHint("Confirm the selected wake-up time as the end of this sleep session")
                    Text("Sleep duration and its Recovery input update; HRV/RHR require overnight sensor data.")
                        .font(StrapTypography.body(11))
                }
                .navigationTitle("Edit time in bed")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showSleepEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveSleepCorrection()
                        }
                        .disabled(correctedSleepEnd <= correctedSleepStart || correctedSleepEnd.timeIntervalSince(correctedSleepStart) > 86400)
                    }
                }
            }
        }
        .alert("End Sleep?", isPresented: $confirmEndSleep) {
            Button("Cancel", role: .cancel) {}
            Button("End Sleep") { saveSleepCorrection() }
        } message: {
            Text("Set the sleep end to the selected time? This updates the sleep window and recalculates available metrics. You can edit it later.")
        }
        .navigationTitle("TODAY")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMetricInfo = true } label: {
                    Image(systemName: "info.circle").foregroundStyle(Color.appMuted)
                }.accessibilityLabel("About sleep metrics")
            }
        }
        .sheet(isPresented: $showMetricInfo) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Sleep estimates").font(StrapTypography.body(24, weight: .bold))
                        Text(performanceCaption)
                        Text("Sleep stages use recorded heart rate, R-R intervals and movement. They are local estimates, not PSG-validated measurements. Missing intervals remain unclassified. Personal typical ranges require enough recorded nights.")
                        Text("Consistency compares recorded bed and wake times. Sleep stress needs seven nights of baseline. Empty chart days have no recorded reading.")
                    }.font(StrapTypography.body(16)).padding(24)
                }.navigationTitle("About sleep")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showMetricInfo = false } } }
            }
        }
        .sheet(isPresented: $showNeedInfo) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Hours vs. Needed").font(StrapTypography.body(24, weight: .bold))
                        Text("Your sleep need is calculated from your baseline physiological requirement, plus any sleep debt from previous nights and adjustments for your sleep goal.")
                        Text("The percentage compares total hours asleep to your overall sleep needed.")
                    }.font(StrapTypography.body(16)).padding(24)
                }.navigationTitle("Sleep Need")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showNeedInfo = false } } }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveSleepCorrection() {
        guard let period = editablePeriod, correctedSleepEnd > correctedSleepStart,
              correctedSleepEnd.timeIntervalSince(correctedSleepStart) <= 86400 else { return }
        let oldCorrections = UserDefaults.standard.dictionary(forKey: SleepCorrectionStore.defaultsKey) as? [String: [Int]] ?? [:]
        let corrections = SleepCorrectionStore.saving([
            Int(correctedSleepStart.timeIntervalSince1970),
            Int(correctedSleepEnd.timeIntervalSince1970)
        ], for: period, overrides: oldCorrections)
        UserDefaults.standard.set(corrections, forKey: SleepCorrectionStore.defaultsKey)
        store.band.notifySleepCorrectionChanged()
        showSleepEditor = false
    }

    // MARK: Performance ring

    private var performancePct: Double? {
        demo ? Double(SampleData.sleepPerformance) : analysis?.performancePct
    }

    private var performancePanel: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width - 110, 180.0)
            ZStack {
                Circle().stroke(Color.appRaised, lineWidth: 12)
                Circle().trim(from: 0, to: CGFloat(min(1, max(0, (performancePct ?? 0) / 100))))
                    .stroke(Color.appSleep, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text("STRAP").font(StrapTypography.body(14, weight: .light)).tracking(3)
                        .foregroundStyle(Color.appMuted)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(performancePct.map { "\(Int($0.rounded()))" } ?? "—")
                            .font(StrapTypography.metric(48, weight: .bold))
                        if performancePct != nil { Text("%").font(StrapTypography.metric(28, weight: .bold)) }
                    }
                    Text("SLEEP\nPERFORMANCE")
                        .font(StrapTypography.body(11, weight: .bold)).tracking(0.8)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { index in
                            Rectangle().fill(index == 1 ? Color.appMuted : Color.appRaised)
                                .frame(width: 14, height: 3)
                        }
                    }.padding(.top, 4)
                }.foregroundStyle(Color.appFG)
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 210)
        .padding(.bottom, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep performance, \(percentText(performancePct)). \(performanceCaption)")
    }

    private var performanceCaption: String {
        if demo {
            return "Sample: 66% of your needed sleep last night."
        }
        if store.band.isAnalyzingHistory { return "Recalculating the saved night…" }
        guard let analysis else {
            return session?.durationReason ?? "needs an overnight capture"
        }
        return "\(CoachFormat.duration(analysis.hours)) estimated asleep of \(CoachFormat.duration(analysis.needHours)) base need. Local score, not WHOOP's score."
    }

    // MARK: Components

    private var componentsPanel: some View {
        Panel {
            componentRow(title: "Hours vs. needed", symbol: "moon.zzz", percent: demo ? Double(SampleData.hoursVsNeeded) : reconciledHoursVsNeededPct)
            Divider().overlay(Color.appLine)
            componentRow(title: "Sleep consistency", symbol: "moon", percent: demo ? Double(SampleData.sleepConsistency) : analysis?.consistencyPct)
            Divider().overlay(Color.appLine)
            componentRow(title: "Sleep efficiency", symbol: "chart.bar", percent: demo ? Double(SampleData.sleepEfficiency) : reconciledEfficiencyPct)
            Divider().overlay(Color.appLine)
            componentRow(title: "High sleep stress", symbol: "gauge.with.needle", percent: demo ? Double(SampleData.highSleepStress) : analysis?.stress.highPct, lowerIsBetter: true)
            HStack(spacing: 12) {
                legendKey("Poor", .appWarn)
                legendKey("Sufficient", .appMuted)
                legendKey("Optimal", .appGood)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func legendKey(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 11, height: 3)
            Text(title).font(StrapTypography.body(10)).foregroundStyle(Color.appMuted)
        }
    }

    private func componentRow(title: String, symbol: String, percent: Double?, lowerIsBetter: Bool = false) -> some View {
        let level = percent.map { lowerIsBetter ? ($0 <= 5 ? 2 : $0 <= 15 ? 1 : 0) : ($0 >= 80 ? 2 : $0 >= 70 ? 1 : 0) }
        return HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 16, weight: .light))
                .foregroundStyle(Color.appMuted).frame(width: 21)
            Text(title.uppercased()).font(StrapTypography.body(10, weight: .bold)).tracking(0.7)
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Rectangle().fill(level == index ? (index == 0 ? Color.appWarn : index == 1 ? Color.appMuted : Color.appGood) : Color.appRaised)
                        .frame(width: 18, height: 4)
                }
            }
            Text(percentText(percent)).font(StrapTypography.metric(20))
                .frame(width: 46, alignment: .trailing)
        }
        .foregroundStyle(Color.appFG)
        .frame(minHeight: 58)
    }

    // MARK: Last night

    private var lastNightHours: Double? { session?.asleepHours }
    private var asleepHours: Double? { session?.asleepHours }
    private var awakeHours: Double? { session?.awakeHours }
    private var reconciledHoursVsNeededPct: Double? { analysis?.hoursVsNeededPct }
    private var reconciledEfficiencyPct: Double? { session?.efficiencyPct }

    private var editablePeriod: SleepPeriod? {
        guard !store.band.isAnalyzingHistory else { return nil }
        // A corrected session may replace several detector fragments; edit its source, not the last fragment.
        if let session {
            return periods.first { $0.startUnix == session.sourceStartUnix } ?? session.sourcePeriod
        }
        return periods.max(by: { $0.endUnix < $1.endUnix })
    }

    private func openSleepEditor() {
        guard let period = editablePeriod else { return }
        let corrections = UserDefaults.standard.dictionary(forKey: SleepCorrectionStore.defaultsKey) as? [String: [Int]] ?? [:]
        let times = SleepCorrectionStore.times(for: period, overrides: corrections)
        correctedSleepStart = Date(timeIntervalSince1970: TimeInterval(times?.first ?? session?.startUnix ?? period.startUnix))
        correctedSleepEnd = Date(timeIntervalSince1970: TimeInterval(times?.last ?? session?.endUnix ?? (period.endUnix + 1)))
        showSleepEditor = true
    }

    private var canEndSleepNow: Bool {
        guard let period = editablePeriod else { return false }
        // A manually finalized night must never offer an action that silently
        // extends its saved end back to the current clock time.
        if session?.isEdited == true { return false }
        let corrections = UserDefaults.standard.dictionary(forKey: SleepCorrectionStore.defaultsKey) as? [String: [Int]] ?? [:]
        if SleepCorrectionStore.times(for: period, overrides: corrections) != nil { return false }
        let now = Date().timeIntervalSince1970
        // End Now is for an active/recently detected window only. Older nights must be edited explicitly.
        return now >= Double(period.startUnix) && now - Double(period.endUnix) <= 15 * 60
            && now - Double(period.startUnix) <= 86400
    }

    private func requestEndSleepNow() {
        guard canEndSleepNow, let period = editablePeriod else { return }
        let now = Date()
        let start = Date(timeIntervalSince1970: TimeInterval(session?.startUnix ?? period.startUnix))
        guard now > start, now.timeIntervalSince(start) <= 86400 else {
            openSleepEditor()
            return
        }
        correctedSleepStart = start
        correctedSleepEnd = now
        confirmEndSleep = true
    }

    private var lastNightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Last Night's Sleep")
                    .font(StrapTypography.body(20, weight: .bold))
                    .foregroundStyle(Color.appFG)
                Spacer()
                if !demo, editablePeriod != nil {
                    Button(action: openSleepEditor) {
                        Label("EDIT", systemImage: "pencil")
                            .font(StrapTypography.body(12, weight: .bold))
                    }
                    .foregroundStyle(Color.appFG)
                }
            }
            Text("Today vs. prior 30 days")
                .font(StrapTypography.body(12)).foregroundStyle(Color.appMuted)
                .padding(.top, 4).padding(.bottom, 16)
            Panel {
            CardHead(title: "Hours of sleep")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(demo ? SampleData.sleepHours : lastNightHours.map(CoachFormat.duration) ?? "—")
                    .font(StrapTypography.metric(34, weight: .bold))
                    .foregroundStyle(Color.appFG)
                Spacer()
            }
            .padding(.bottom, 8)

            if !demo, canEndSleepNow {
                Button(action: requestEndSleepNow) {
                    Label("END SLEEP NOW", systemImage: "stop.circle")
                        .font(StrapTypography.body(12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(Color.appSleep)
                .accessibilityHint("Confirm ending the current sleep at the present time")
                .padding(.bottom, 12)
            }

            if demo {
                LineChart(
                    values: SampleData.sleepHRSeries,
                    color: .appSleep,
                    minY: 30,
                    maxY: 110,
                    height: 160,
                    yLabels: ["110", "90", "70", "50", "30"],
                    xLabels: ["00:26", "07:33"]
                )
                .padding(.bottom, 4)
            } else if let session, !session.heartRate.isEmpty {
                SleepHeartRateChart(session: session)
                    .padding(.bottom, 4)
                Text("Per-minute HR within this sleep window. Gaps mean missing data.")
                    .font(StrapTypography.body(10.5))
                    .foregroundStyle(Color.appMuted)
                    .padding(.bottom, 8)
            } else {
                EmptyState(
                    title: "wear it overnight",
                    detail: "Heart rate through the night appears once a capture covers it."
                )
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.appRaised))
                .padding(.bottom, 8)
            }

            Divider()
                .overlay(Color.appLine)
                .padding(.vertical, 14)

            stagingPanel

            needPanel
                .padding(.top, 14)

            coachInsightCard

            diagnosticDisclosures
                .padding(.top, 14)
            }
        }
    }

    private var wakeEventText: String {
        session.map { "\($0.movementBouts)" } ?? "—"
    }

    private var lastNightSegments: [SplitBar.Segment] {
        if demo {
            let total = SampleData.asleepMinutes + SampleData.awakeMinutes
            return [
                SplitBar.Segment(fraction: SampleData.asleepMinutes / total, color: .appSleep),
                SplitBar.Segment(fraction: SampleData.awakeMinutes / total, color: .appWarn)
            ]
        }
        if let session, session.timeInBedHours > 0 {
            return [
                SplitBar.Segment(fraction: session.classifiedAsleepHours / session.timeInBedHours, color: .appSleep),
                SplitBar.Segment(fraction: session.classifiedAwakeHours / session.timeInBedHours, color: .appWarn),
                SplitBar.Segment(fraction: session.unclassifiedHours / session.timeInBedHours, color: .appRaised)
            ]
        }
        return [SplitBar.Segment(fraction: 1.0, color: .appRaised)]
    }

    private func clock(_ unix: Int) -> String {
        // UNIX timestamps are UTC instants; display them in the user's local
        // timezone rather than interpreting UTC minutes as wall-clock time.
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
    }

    private func splitValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(StrapTypography.body(15, weight: .medium))
                .foregroundStyle(Color.appFG)
            Text(label)
                .font(StrapTypography.body(10))
                .foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Sleep stages

    private var staging: SleepStaging? {
        session?.staging
    }

    private var demoStageMinutes: [SleepStage: Double] {
        [.deep: 75, .light: 190, .rem: 84, .wake: 67]
    }

    private var stagingPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if demo {
                stageValues(demoStageMinutes)
            } else if let staging, !staging.segments.isEmpty {
                if session?.isEdited == true {
                    Hint("Recalculated from retained sensor data for your edited bed/wake times.")
                }
                stageValues(stagingMinutes(staging))
                if let reason = staging.reason {
                    Hint("Partial stages only. \(reason). Missing intervals remain unclassified; the full-night sleep score is withheld.")
                }
            } else if let staging, let reason = staging.reason {
                EmptyState(title: "Stages unavailable", detail: reason + ". Missing data is not assigned a sleep stage.")
            } else if let summary = store.band.summary, !summary.sleepPeriods.isEmpty {
                EmptyState(
                    title: "not staged yet",
                    detail: store.band.isAnalyzingHistory ? "Recalculating retained sensor data…" : "No retained sensor data is available for this window."
                )
            } else {
                EmptyState(
                    title: "needs an overnight capture",
                    detail: "Stages appear once a capture covers a detected sleep window long enough to score."
                )
            }
        }
        .onChange(of: session?.startUnix) { _, _ in sleepExportURL = nil }
        .onChange(of: session?.endUnix) { _, _ in sleepExportURL = nil }
    }

    private var diagnosticDisclosures: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let staging, !staging.segments.isEmpty, let session {
                DisclosureGroup("Sleep timeline") {
                    StageHypnogram(
                        segments: staging.segments,
                        startUnix: session.startUnix,
                        endUnix: session.endUnix
                    )
                }
                .font(StrapTypography.body(12, weight: .medium))
                .tint(Color.appMuted)
                .padding(.top, 4)

                DisclosureGroup("About estimated stages") {
                    Hint("Window \(clock(session.startUnix))–\(clock(session.endUnix)). \(staging.epochs) estimated epochs; \(Int((staging.hrCoverage * 100).rounded()))% valid HR seconds. Blank intervals are unclassified. An approximation, not PSG-validated or WHOOP's staging.")
                }
                .font(StrapTypography.body(11))
                .tint(Color.appMuted)
            }

            if !demo, let session, !session.isComplete {
                Button {
                    if store.band.isConnected { store.band.readHistory() }
                    else { store.connectBand() }
                } label: {
                    Label(store.band.status == .draining ? "Syncing sleep history…" : "Sync sleep history",
                          systemImage: "arrow.clockwise")
                }
                .disabled(store.band.status == .draining || store.band.status == .authenticating)
                .padding(.top, 4)
                Hint("Keep the strap nearby while syncing. Saved raw captures are recovered automatically when the app opens. Time the strap did not record cannot be reconstructed.")
            }

            if !demo, session != nil {
                Button {
                    preparingSleepExport = true
                    sleepExportError = nil
                    Task {
                        do { sleepExportURL = try await store.band.exportSleepDiagnostics() }
                        catch { sleepExportError = error.localizedDescription }
                        preparingSleepExport = false
                    }
                } label: {
                    Label(preparingSleepExport ? "Preparing sleep export…" : "Export sleep sensor data",
                          systemImage: "square.and.arrow.up")
                }
                .disabled(preparingSleepExport || store.band.isAnalyzingHistory)
                .padding(.top, 4)
                if let sleepExportURL {
                    ShareLink("Share sleep CSV", item: sleepExportURL)
                        .padding(.top, 6)
                    Hint("Contains this night's recorded heart rate, R-R intervals, movement and estimated labels. Share only when you choose.")
                }
                if let sleepExportError { Hint(sleepExportError) }
            }

            DisclosureGroup("Sleep details") {
                SplitBar(segments: lastNightSegments)
                    .padding(.bottom, 8)

                HStack(spacing: 8) {
                    splitValue(demo ? "5:49" : asleepHours.map(CoachFormat.duration) ?? "—", label: "asleep")
                    splitValue(demo ? "1:07" : awakeHours.map(CoachFormat.duration) ?? "—", label: "awake")
                }
                .padding(.bottom, 10)
                if !demo, let session {
                    HStack {
                        Text("Time in bed \(CoachFormat.duration(session.timeInBedHours))")
                        Spacer()
                        if session.unclassifiedHours > 0 {
                            Text("Unknown \(CoachFormat.duration(session.unclassifiedHours))")
                        }
                    }
                    .font(StrapTypography.body(11))
                    .foregroundStyle(Color.appMuted)
                    .padding(.bottom, 8)
                    if let reason = session.durationReason { Hint(reason + " Missing time is not awake time.") }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Movement bouts")
                            .font(StrapTypography.body(12, weight: .medium))
                            .foregroundStyle(Color.appFG)
                        Text("not verified awakenings")
                            .font(StrapTypography.body(10.5))
                            .foregroundStyle(Color.appMuted)
                    }
                    Spacer()
                    Text(demo ? "\(SampleData.wakeEvents)" : wakeEventText)
                        .font(StrapTypography.metric(22, weight: .bold))
                        .foregroundStyle(Color.appFG)
                }
            }
            .font(StrapTypography.body(12, weight: .medium))
            .tint(Color.appMuted)
        }
    }

    private var stagingTrailing: String {
        if demo { return "sample" }
        guard let staging, !staging.segments.isEmpty, staging.asleepMinutes > 0 else { return "—" }
        if staging.reason != nil {
            return "Partial · \(Int((staging.hrCoverage * 100).rounded()))% HR"
        }
        let pct = staging.restorativeMinutes / staging.asleepMinutes * 100.0
        return String(format: "%.0f%% restorative", pct)
    }

    private func stagingMinutes(_ staging: SleepStaging) -> [SleepStage: Double] {
        [
            .deep: staging.deepMinutes,
            .light: staging.lightMinutes,
            .rem: staging.remMinutes,
            .wake: staging.wakeMinutes
        ]
    }

    private func segments(for staging: SleepStaging) -> [SplitBar.Segment] {
        splitSegments(stagingMinutes(staging))
    }

    private func splitSegments(_ minutes: [SleepStage: Double]) -> [SplitBar.Segment] {
        let total = max(1, session.map { $0.timeInBedHours * 60 } ?? minutes.values.reduce(0, +))
        var result = [SleepStage.wake, .light, .deep, .rem].map { stage in
            SplitBar.Segment(fraction: (minutes[stage] ?? 0) / total, color: stage.color)
        }
        if let session, session.unclassifiedHours > 0 {
            result.append(SplitBar.Segment(fraction: session.unclassifiedHours * 60 / total, color: .appRaised))
        }
        return result
    }

    // WHOOP-style stacked stage distribution matching official layout and typical ranges
    private func stageValues(_ minutes: [SleepStage: Double]) -> some View {
        let total = max(1.0, session.map { $0.timeInBedHours * 60 } ?? minutes.values.reduce(0, +))
        let displayed = SleepStageDisplay.rounded(stageMinutes: minutes, windowMinutes: total)
        return VStack(alignment: .leading, spacing: 20) {
            HStack {
                HStack(spacing: 6) {
                    TypicalRangeLegendIcon()
                    Text("TYPICAL RANGE")
                        .font(StrapTypography.body(10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.appMuted)
                }
                Spacer()
                HStack(spacing: 5) {
                    Text("DURATION")
                        .font(StrapTypography.body(10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.appMuted)
                    Text(displayed.duration(displayed.window))
                        .font(StrapTypography.metric(16, weight: .bold))
                        .foregroundStyle(Color.appFG)
                }
            }
            ForEach([SleepStage.wake, .light, .deep, .rem]) { stage in
                let value = minutes[stage] ?? 0
                let fraction = min(1.0, max(0.0, value / total))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Circle()
                            .strokeBorder(stage.color, lineWidth: 2)
                            .frame(width: 23, height: 23)
                        Text(stage == .deep ? "SWS (DEEP)" : stage.title.uppercased())
                            .font(StrapTypography.body(12, weight: .bold))
                            .tracking(0.5)
                        Text(String(format: "%.0f%%", fraction * 100))
                            .font(StrapTypography.body(11, weight: .medium))
                            .foregroundStyle(stage.color)
                        Spacer()
                        Text(displayed.duration(displayed.stages[stage] ?? 0))
                            .font(StrapTypography.metric(19, weight: .bold))
                    }
                    SleepStageDistributionBar(fraction: fraction, color: stage.color, typicalRange: typicalRange(for: stage))
                        .frame(height: 15)
                }
            }
            if let session, session.unclassifiedHours > 0 {
                HStack {
                    Text("UNCLASSIFIED")
                        .foregroundStyle(Color.appMuted)
                    Spacer()
                    Text(displayed.duration(displayed.unclassified))
                }
                .font(StrapTypography.body(12, weight: .medium))
            }
            Divider().overlay(Color.appLine).padding(.top, 2)
            HStack(alignment: .center) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.93, green: 0.39, blue: 0.86))
                    .frame(width: 12, height: 12)
                Text("RESTORATIVE SLEEP")
                    .font(StrapTypography.body(12, weight: .bold))
                    .tracking(0.5)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(displayed.duration(displayed.restorative))
                        .font(StrapTypography.metric(19, weight: .bold))
                        .foregroundStyle(Color.appFG)
                    let baseline = typicalRestorativeMinutes
                    HStack(spacing: 3) {
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 6))
                            .rotationEffect(Double(displayed.restorative) >= baseline ? .zero : .degrees(180))
                            .foregroundStyle(Double(displayed.restorative) >= baseline ? Color.appGood : Color.appWarn)
                        Text(CoachFormat.duration(baseline / 60.0))
                            .font(StrapTypography.metric(11, weight: .medium))
                            .foregroundStyle(Color.appMuted)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(.bottom, 8)
    }

    // MARK: Hours vs. needed detail (WHOOP card parity)

    private var needPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("HOURS VS. NEEDED")
                    .font(StrapTypography.body(11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Color.appFG)
                Spacer()
                Button {
                    showNeedInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.appMuted)
                }
                .accessibilityLabel("About hours vs needed")
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(percentText(demo ? Double(SampleData.hoursVsNeeded) : reconciledHoursVsNeededPct))
                        .font(StrapTypography.metric(34, weight: .bold))
                        .foregroundStyle(Color.appFG)
                    if let pct = (demo ? Double(SampleData.hoursVsNeeded) : reconciledHoursVsNeededPct) {
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 9))
                            .rotationEffect(pct >= typicalHoursVsNeededPct ? .zero : .degrees(180))
                            .foregroundStyle(pct >= typicalHoursVsNeededPct ? Color.appGood : Color.appWarn)
                    }
                }
                Text(String(format: "%.0f%%", typicalHoursVsNeededPct))
                    .font(StrapTypography.metric(13, weight: .medium))
                    .foregroundStyle(Color.appMuted)
            }

            VStack(spacing: 6) {
                HStack {
                    Text("HOURS OF SLEEP")
                        .font(StrapTypography.body(10, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Text(demo ? SampleData.sleepHours : asleepHours.map(CoachFormat.duration) ?? "—")
                        .font(StrapTypography.metric(15, weight: .bold))
                        .foregroundStyle(Color.appFG)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0x22262E))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(hex: 0x4B7395), Color(hex: 0x8EBEE0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * CGFloat(hoursVsNeededFraction))
                    }
                }
                .frame(height: 14)
            }

            VStack(spacing: 6) {
                HStack {
                    Text("SLEEP NEEDED")
                        .font(StrapTypography.body(10, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Text(demo ? SampleData.needTotal : analysis.map { CoachFormat.duration($0.needHours) } ?? "—")
                        .font(StrapTypography.metric(15, weight: .bold))
                        .foregroundStyle(Color.appFG)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0x2A2E35))
                        let targetFraction = CGFloat(hoursVsNeededFraction)
                        let markerWidth: CGFloat = 8
                        let markerX = max(0, min(geo.size.width - markerWidth, geo.size.width * targetFraction - markerWidth / 2))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: 0x369BF6))
                            .frame(width: markerWidth, height: 14)
                            .offset(x: markerX)
                    }
                }
                .frame(height: 14)
            }

            DisclosureGroup("Sleep need breakdown") {
                VStack(spacing: 8) {
                    needKey("Healthy minimum", color: .appRaised, value: demo ? SampleData.needBase : CoachFormat.duration(store.settings.sleepNeedHours))
                    needKey("Next-night debt allowance", color: Color(hex: 0xCCCCCC), value: demo ? SampleData.needDebt : debt.map { "+" + CoachFormat.duration(min($0, SleepCoach.debtCapHours)) } ?? "—")
                    needKey("Tomorrow's plan", color: .appAccent, value: demo ? SampleData.needTomorrow : "+" + CoachFormat.duration(store.settings.sleepIntent.extraHours))
                }
                .padding(12)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 6)
            }
            .font(StrapTypography.body(11, weight: .medium))
            .tint(Color.appMuted)
        }
        .padding(16)
        .background(Color(hex: 0x16181D), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(Color.appFG)
    }

    private var coachInsightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().fill(Color(hex: 0x31384D))
                        .frame(width: 28, height: 28)
                    Text("W")
                        .font(StrapTypography.body(13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x8FA4DC))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(coachSummaryText)
                        .font(StrapTypography.body(12, weight: .medium))
                        .foregroundStyle(Color.appFG)
                        .lineLimit(coachExpanded ? nil : 2)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { coachExpanded.toggle() }
                } label: {
                    Image(systemName: coachExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.appMuted)
                }
            }
            if let debt = debt, debt > 0.05 {
                Divider().overlay(Color.white.opacity(0.08))
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.appRaised)
                        .frame(width: 10, height: 10)
                    Text("Sleep Debt")
                        .font(StrapTypography.body(11, weight: .medium))
                        .foregroundStyle(Color.appMuted)
                    Spacer()
                    Text("+" + CoachFormat.duration(min(debt, SleepCoach.debtCapHours)))
                        .font(StrapTypography.metric(13, weight: .bold))
                        .foregroundStyle(Color.appFG)
                }
            }
        }
        .padding(14)
        .background(Color(hex: 0x161A24), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.top, 8)
    }

    private func needKey(_ title: String, color: Color, value: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 11, height: 11)
            Text(title).font(StrapTypography.body(12))
            Spacer()
            Text(value).font(StrapTypography.metric(13))
        }
    }

    private var hoursVsNeededFraction: Double {
        let pct = demo ? Double(SampleData.hoursVsNeeded) : reconciledHoursVsNeededPct
        return min(max((pct ?? 0) / 100.0, 0), 1)
    }

    private func needRow(_ title: String, demo: String, live: String) -> some View {
        HStack {
            Text(title).font(StrapTypography.body(12)).foregroundStyle(Color.appMuted)
            Spacer()
            Text(self.demo ? demo : live)
                .font(StrapTypography.body(13, weight: .medium)).foregroundStyle(Color.appFG)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Rectangle().fill(Color.appLine).frame(height: 1) }
    }

    // MARK: Consistency detail

    private var liveNights: [NightSpan] {
        Array(store.band.recentNights.suffix(5))
    }

    private var liveBedWake: [(Double, Double)] {
        liveNights.map { span in
            let bed = SleepReport.minutesOfDay(span.startUnix)
            let bedOffset = Double((bed - 1080 + 1440) % 1440)
            let duration = Double(span.endUnix - span.startUnix) / 60.0
            return (bedOffset, bedOffset + duration)
        }
    }

    private var consistencyPanel: some View {
        Panel {
            detailHead("Sleep consistency", value: percentText(demo ? Double(SampleData.sleepConsistency) : analysis?.consistencyPct))
            if demo {
                BedWakeChart(
                    spans: Array(SampleData.weeklyBedWake.suffix(5)),
                    labels: Array(SampleData.weekDays.suffix(5)),
                    height: 185
                )
                Hint("Dashed lines mark the grid; a night counts when both bed and wake sit within ±60 min of your medians.")
            } else if liveBedWake.count >= 2 {
                ConsistencyBedWakeChart(
                    nights: liveNights,
                    calendar: .current
                )
                Hint("Each bar shows a recorded bedtime and wake time. Missing nights remain blank. STRAP's local ±60-minute median score is not WHOOP's proprietary consistency score.")
            } else {
                EmptyState(title: "Needs 2+ recorded nights",
                           detail: "Your median bedtime and wake time appear once two nights are stored.")
            }
        }
    }

    private func detailHead(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased()).font(StrapTypography.body(11, weight: .bold)).tracking(0.8)
                Spacer()
                Button { showMetricInfo = true } label: {
                    Image(systemName: "info.circle").foregroundStyle(Color.appMuted)
                }.accessibilityLabel("About \(title)")
            }
            Text(value).font(StrapTypography.metric(24))
        }.foregroundStyle(Color.appFG).padding(.bottom, 12)
    }

    private var efficiencyPanel: some View {
        Panel {
            detailHead("Sleep efficiency", value: percentText(demo ? Double(SampleData.sleepEfficiency) : reconciledEfficiencyPct))
            HStack {
                Text("ASLEEP").font(StrapTypography.body(10, weight: .bold)).tracking(0.7)
                Spacer()
                Text(demo ? SampleData.sleepHours : asleepHours.map(CoachFormat.duration) ?? "—").font(StrapTypography.metric(16))
            }.padding(.bottom, 8)
            if let session {
                SleepEfficiencyTimeline(session: session)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Sleep efficiency timeline, blue intervals asleep, light intervals awake, hatched intervals unclassified")
            }
            else if demo {
                VStack(spacing: 12) {
                    SleepStageDistributionBar(fraction: 0.84, color: .appSleep)
                    SleepStageDistributionBar(fraction: 0.16, color: Color(hex: 0xCCCCCC))
                }.frame(height: 42)
            } else { EmptyState(title: "Needs an overnight capture", detail: "Recorded asleep and awake intervals appear here.") }
            HStack {
                Text("AWAKE").font(StrapTypography.body(10, weight: .bold)).tracking(0.7)
                Spacer()
                Text(demo ? "1:07" : awakeHours.map(CoachFormat.duration) ?? "—").font(StrapTypography.metric(16))
            }.padding(.top, 8)
            Divider().overlay(Color.appLine).padding(.vertical, 20)
            HStack {
                Text("MOVEMENT BOUTS").font(StrapTypography.body(11, weight: .bold)).tracking(0.7)
                Spacer()
                Text(wakeEventText).font(StrapTypography.metric(16))
            }
        }.foregroundStyle(Color.appFG)
    }

    // MARK: Sleep stress detail

    private var stressDetailPanel: some View {
        Panel {
            detailHead("Sleep stress", value: percentText(demo ? Double(SampleData.highSleepStress) : analysis?.stress.highPct))
            if demo {
                LineChart(
                    values: SampleData.sleepStressSeries,
                    color: .appGood,
                    minY: 0, maxY: 3,
                    height: 200,
                    yLabels: ["3.0", "2.0", "1.0", "0.0"],
                    xLabels: ["1:28 AM", "8:22 AM"]
                )
                .padding(.bottom, 8)
                stressDistribution(high: 0, medium: 5, low: 95)
            } else if let stress = analysis?.stress, let low = stress.lowPct {
                stressDistribution(high: stress.highPct ?? 0, medium: stress.mediumPct ?? 0, low: low)
                Hint("\(stress.windows) five-minute sleep windows scored against your own sleep baseline. A timestamped overnight stress curve is not retained.")
            } else {
                EmptyState(
                    title: "Needs 7 sleep nights of baseline",
                    detail: analysis?.stress.reason
                        ?? "Each 5-minute window's lnRMSSD is scored against your own sleep norm — never the awake one."
                )
            }
        }
    }

    private func stressDistribution(high: Double, medium: Double, low: Double) -> some View {
        VStack(spacing: 22) {
            stressDistributionRow("HIGH", percent: high, color: .appWarn)
            stressDistributionRow("MEDIUM", percent: medium, color: .appGood)
            stressDistributionRow("LOW", percent: low, color: Color(hex: 0x65ADE0))
        }.padding(.top, 20)
    }

    private func stressDistributionRow(_ title: String, percent: Double, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(title).font(StrapTypography.body(11, weight: .bold)).tracking(0.7)
                Text(percentText(percent)).font(StrapTypography.metric(11)).foregroundStyle(color)
                Spacer()
            }
            SleepStageDistributionBar(fraction: percent / 100, color: color).frame(height: 15)
        }.foregroundStyle(Color.appFG)
    }

    private var highSleepStressText: String {
        guard let high = analysis?.stress.highPct else { return "—" }
        return String(format: "%.0f%% high", high)
    }

    private func percentText(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0) } ?? "—"
    }

    private func stressSegments(_ stress: StressSplit) -> [SplitBar.Segment] {
        [
            SplitBar.Segment(fraction: (stress.highPct ?? 0) / 100.0, color: .appHigh),
            SplitBar.Segment(fraction: (stress.mediumPct ?? 0) / 100.0, color: .appWarn),
            SplitBar.Segment(fraction: (stress.lowPct ?? 0) / 100.0, color: .appGood)
        ]
    }

    private func stressSplit(_ value: String, _ label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(StrapTypography.body(15, weight: .medium)).foregroundStyle(color)
            Text(label).font(StrapTypography.body(10)).foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Weekly trends

    private var weeklyPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Previous week") { historyWeekOffset -= 1 }
                Spacer()
                Button("Next week") { historyWeekOffset = min(0, historyWeekOffset + 1) }.disabled(historyWeekOffset == 0)
            }.font(StrapTypography.body(12)).padding(.vertical, 10)
            if !store.whoopImportedDays.isEmpty {
                Hint("WHOOP imported sleep fills dates without a local night. Reported stage totals are shown as totals, never as an invented timeline.")
            }
            Text("Weekly Trends").font(StrapTypography.body(20, weight: .semibold))
                .padding(.vertical, 16)
            weeklyCard("Sleep performance") {
                SleepTrendChart(dates: weekDates, values: weekPerformance)
            }
            weeklyCard("Hours vs. needed (hours)") {
                ChartLegend(items: [("HOURS OF SLEEP", .appSleep), ("SLEEP NEEDED", .appGood)])
                SleepTrendChart(dates: weekDates, values: weekSleep, secondary: weekNeed,
                                style: .line, maximum: 12, format: CoachFormat.duration)
            }
            weeklyCard("Hours vs. needed (%)") {
                SleepTrendChart(dates: weekDates, values: zip(weekSleep, weekNeed).map { sleep, need in
                    guard let sleep, let need, need > 0 else { return nil }
                    return min(100, sleep / need * 100)
                })
            }
            weeklyCard("Restorative sleep (hours)") {
                ChartLegend(items: [("DEEP SLEEP", SleepStage.deep.color), ("REM SLEEP", SleepStage.rem.color)])
                SleepTrendChart(dates: weekDates, values: weekStage(.rem), secondary: weekStage(.deep),
                                style: .stacked, maximum: 6, color: SleepStage.rem.color,
                                secondaryColor: SleepStage.deep.color, format: CoachFormat.duration)
            }
            weeklyCard("Sleep consistency") {
                SleepTrendChart(dates: weekDates, values: weekConsistency)
            }
            weeklyCard("Time in bed") {
                SleepTrendChart(dates: weekDates, values: weekBedWake.map { $0?.0 },
                                secondary: weekBedWake.map { $0?.1 }, style: .range,
                                maximum: 960, format: bedClock)
            }
            weeklyCard("Sleep efficiency") {
                SleepTrendChart(dates: weekDates, values: weekEfficiency, style: .line, maximum: 100, minimum: 75)
            }
            weeklyCard("Sleep debt") {
                SleepTrendChart(dates: weekDates, values: weekDebt, maximum: max(180, (weekDebt.compactMap { $0 }.max() ?? 0) * 1.2),
                                format: { CoachFormat.duration($0 / 60) })
            }
            weeklyCard("Sleep stress") {
                ChartLegend(items: [("HIGH", .appWarn), ("MEDIUM", .appGood), ("LOW", Color(hex: 0x65ADE0))])
                if demo {
                    SleepTrendChart(dates: weekDates,
                                    values: SampleData.weeklyStressSegments.map { $0[2] },
                                    secondary: SampleData.weeklyStressSegments.map { $0[1] },
                                    tertiary: SampleData.weeklyStressSegments.map { $0[0] },
                                    style: .stacked, color: Color(hex: 0x65ADE0), format: { _ in "" })
                } else {
                    EmptyState(title: "Nightly stress history unavailable", detail: "The latest night's baseline-based stress split appears above. Historical stress windows have not been retained.")
                }
            }
        }.foregroundStyle(Color.appFG)
    }

    private func weeklyCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Panel {
            CardHead(title: title)
            content()
        }
    }

    private var weekDates: [Date] {
        let end = demo ? Date() : (nights.sorted { $0.dateKey < $1.dateKey }.last.flatMap { night in
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: night.dateKey)
        } ?? Date())
        return (-6...0).compactMap { Calendar.current.date(byAdding: .day, value: $0 + historyWeekOffset * 7, to: Calendar.current.startOfDay(for: end)) }
    }

    private func dayKey(_ date: Date) -> String { JournalStore.dayKey(for: date) }
    private var weekSessions: [SleepSession?] {
        weekDates.map { date in
            (store.band.summary?.sleepSessions ?? []).filter {
                Calendar.current.isDate(Date(timeIntervalSince1970: TimeInterval($0.endUnix)), inSameDayAs: date)
            }.max { $0.timeInBedHours < $1.timeInBedHours }
        }
    }
    private var weekSleep: [Double?] {
        demo ? SampleData.weeklyHoursSleep.map(Optional.some) : weekDates.map { date in
            nights.first { $0.dateKey == dayKey(date) }?.actualHours
        }
    }
    private var weekNeed: [Double?] {
        demo ? SampleData.weeklyHoursNeeded.map(Optional.some) : weekDates.map { date in
            nights.first { $0.dateKey == dayKey(date) }?.neededHours
        }
    }
    private var weekPerformance: [Double?] {
        demo ? SampleData.weeklySleepPerformance.map(Optional.some) : weekDates.map { date in
            store.historyDays.first { $0.dateKey == dayKey(date) }?.sleepPerformancePct
        }
    }
    private var weekEfficiency: [Double?] {
        demo ? SampleData.weeklyEfficiency.map(Optional.some) : weekDates.enumerated().map { index, date in
            if let session = weekSessions[index] { return session.efficiencyPct }
            return store.whoopImportedDays[dayKey(date)]?.efficiency
        }
    }
    private var weekConsistency: [Double?] {
        if demo { return SampleData.weeklyConsistency.map(Optional.some) }
        return weekDates.map { date in
            let spans = (store.band.summary?.sleepSessions ?? []).filter {
                $0.isComplete && $0.endUnix < Int(date.addingTimeInterval(86400).timeIntervalSince1970)
            }.suffix(7).map { NightSpan(startUnix: $0.startUnix, endUnix: $0.endUnix) }
            guard weekSessions[weekDates.firstIndex(of: date) ?? 0] != nil else {
                return store.whoopImportedDays[dayKey(date)]?.consistency
            }
            return SleepReport.consistency(nights: spans).pct
        }
    }
    private func weekStage(_ stage: SleepStage) -> [Double?] {
        if demo {
            let deep = [1.55, 1.77, 1.75, 1.52, 1.67, 1.63, 1.78]
            let rem = [1.25, 1.30, 1.38, 1.15, 1.33, 1.40, 1.55]
            return (stage == .deep ? deep : rem).map(Optional.some)
        }
        return weekDates.enumerated().map { index, date in
            if let session = weekSessions[index] {
                guard session.isComplete else { return nil }
                return (stage == .deep ? session.staging.deepMinutes : session.staging.remMinutes) / 60
            }
            let imported = store.whoopImportedDays[dayKey(date)]
            return (stage == .deep ? imported?.deepMinutes : imported?.remMinutes).map { $0 / 60 }
        }
    }
    private var weekBedWake: [(Double, Double)?] {
        if demo { return SampleData.weeklyBedWake.map { ($0.0 + 180, $0.1 + 180) } }
        return weekDates.enumerated().map { index, date in
            if let session = weekSessions[index] {
                let bed = Double((SleepReport.minutesOfDay(session.startUnix) - 1080 + 1440) % 1440)
                return (bed, bed + session.timeInBedHours * 60)
            }
            guard let imported = store.whoopImportedDays[dayKey(date)], let onset = imported.onsetClockMinutes,
                  let duration = imported.timeInBedMinutes else { return nil }
            let bed = (onset - 1080 + 1440).truncatingRemainder(dividingBy: 1440)
            return (bed, bed + duration)
        }
    }
    private func bedClock(_ minutes: Double) -> String {
        let clock = (Int(minutes) + 1080) % 1440
        return "\(clock / 60 % 12 == 0 ? 12 : clock / 60 % 12):\(String(format: "%02d", clock % 60))"
    }
    private var weekDebt: [Double?] {
        if demo { return SampleData.weeklyDebtMinutes.map(Optional.some) }
        return weekDates.map { date in
            let recorded = nights.filter { $0.dateKey <= dayKey(date) }
            guard recorded.contains(where: { $0.dateKey == dayKey(date) }) else { return nil }
            return SleepCoach.sleepDebt(nights: recorded).map { $0 * 60 }
        }
    }

    private var recentNights: [RecordedNight] {
        Array(nights.sorted { $0.dateKey < $1.dateKey }.suffix(7))
    }

    private var liveDebtMinutes: [Double] {
        let sorted = nights.sorted { $0.dateKey < $1.dateKey }.suffix(SleepCoach.debtWindowNights)
        var balance = 0.0
        var series: [Double] = []
        for night in sorted {
            balance = max(0, balance + night.neededHours - night.actualHours)
            series.append(balance * 60.0)
        }
        return Array(series.suffix(7))
    }

    private func weekdayLabel(forDayKey key: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: key) {
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        }
        return String(key.suffix(2))
    }

    private func weekdayLabel(forUnix unix: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
    }

    private func trendBlock<Content: View>(
        _ title: String, _ unit: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(StrapTypography.body(12.5, weight: .medium)).foregroundStyle(Color.appFG)
                Spacer()
                Text(unit).font(StrapTypography.body(10.5)).foregroundStyle(Color.appMuted)
            }
            content()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Color.appLine).frame(height: 1) }
    }

    private var coachButton: some View {
        NavigationLink(value: Route.sleepCoach) {
            Text("OPEN SLEEP COACH ›")
                .font(StrapTypography.body(11, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Color.appFG)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.appRaised))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private extension SleepStage {
    var color: Color {
        switch self {
        case .wake: return Color(red: 0.82, green: 0.84, blue: 0.86)
        case .light: return Color(red: 0.65, green: 0.61, blue: 0.92)
        case .deep: return Color(red: 0.93, green: 0.39, blue: 0.86)
        case .rem: return Color(red: 0.65, green: 0.28, blue: 0.87)
        }
    }
}

/// Miniature hatched box icon with dashed border indicating the 30-day typical range.
private struct TypicalRangeLegendIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: 0x1E2128))
            Path { path in
                var x: CGFloat = -10
                while x < 20 {
                    path.move(to: CGPoint(x: x, y: 10))
                    path.addLine(to: CGPoint(x: x + 10, y: 0))
                    x += 4
                }
            }
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }
        .frame(width: 16, height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

/// A compact four-row hypnogram. Rows are fixed (wake, REM, light, deep) so
/// the eye reads depth top-to-bottom; every bar is one staged segment.
private struct StageHypnogram: View {
    let segments: [SleepStageSegment]
    let startUnix: Int
    let endUnix: Int

    private let rows: [SleepStage] = [.wake, .rem, .light, .deep]
    private let rowHeight: CGFloat = 18
    private let barHeight: CGFloat = 7

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(rows) { stage in
                    Text(stage.title)
                        .font(StrapTypography.body(8.5))
                        .foregroundStyle(Color.appMuted)
                        .frame(height: rowHeight, alignment: .center)
                }
            }
            GeometryReader { geometry in
                let span = CGFloat(max(1, endUnix - startUnix))
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.appRaised)
                    ForEach(segments) { segment in
                        let x = CGFloat(segment.startUnix - startUnix) / span * geometry.size.width
                        let width = max(1.5, CGFloat(segment.durationS) / span * geometry.size.width)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(segment.stage.color)
                            .frame(width: width, height: barHeight)
                            .offset(
                                x: x,
                                y: CGFloat(rows.firstIndex(of: segment.stage) ?? 0) * rowHeight
                                    + (rowHeight - barHeight) / 2
                            )
                    }
                }
            }
            .frame(height: rowHeight * CGFloat(rows.count))
        }
    }
}


/// WHOOP-style sleep stage bar: diagonal hatched track, solid stage duration bar,
/// and an overlaid dashed bounding box showing the user's 30-day typical range.
private struct SleepStageDistributionBar: View {
    let fraction: Double
    let color: Color
    var typicalRange: ClosedRange<Double>? = nil

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x1E2128))
                Path { path in
                    var x: CGFloat = -geometry.size.height
                    while x < geometry.size.width {
                        path.move(to: CGPoint(x: x, y: geometry.size.height))
                        path.addLine(to: CGPoint(x: x + geometry.size.height, y: 0))
                        x += 8
                    }
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 1.5)

                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geometry.size.width * CGFloat(min(1, max(0, fraction))))

                if let range = typicalRange {
                    let startX = geometry.size.width * CGFloat(min(1, max(0, range.lowerBound)))
                    let endX = geometry.size.width * CGFloat(min(1, max(0, range.upperBound)))
                    let boxWidth = max(6, endX - startX)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color.white.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        )
                        .frame(width: boxWidth, height: geometry.size.height)
                        .offset(x: startX)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .accessibilityHidden(true)
    }
}


/// Sleep consistency chart: fixed calendar positions preserve gaps between nights.
/// This is an independent visualization of recorded bounds, not WHOOP artwork.
private struct ConsistencyBedWakeChart: View {
    let nights: [NightSpan]
    let calendar: Calendar

    private var days: [Date] {
        guard let latest = nights.map({ Date(timeIntervalSince1970: Double($0.endUnix)) }).max() else { return [] }
        let last = calendar.startOfDay(for: latest)
        return (-4...0).compactMap { calendar.date(byAdding: .day, value: $0, to: last) }
    }

    private func matching(_ day: Date) -> NightSpan? {
        nights.filter { calendar.isDate(Date(timeIntervalSince1970: Double($0.endUnix)), inSameDayAs: day) }
            .max { ($0.endUnix - $0.startUnix) < ($1.endUnix - $1.startUnix) }
    }

    private func minutesFromEightPM(_ unix: Int) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: Double(unix)))
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return Double((minute - 1200 + 1440) % 1440)
    }

    private func timeLabel(_ unix: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date(timeIntervalSince1970: Double(unix)))
    }

    var body: some View {
        GeometryReader { geo in
            let labelWidth: CGFloat = 43
            let plotWidth = max(1, geo.size.width - labelWidth)
            let plotHeight = max(1, geo.size.height - 30)
            let slot = plotWidth / 5
            let axisMinutes = 960.0 // 8 PM through noon
            ZStack(alignment: .topLeading) {
                ForEach(0..<5, id: \.self) { tick in
                    let y = plotHeight * CGFloat(tick) / 4
                    Path { path in
                        path.move(to: CGPoint(x: labelWidth, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.appLine.opacity(0.8), lineWidth: 0.7)
                    Text(["8PM", "12AM", "4AM", "8AM", "12PM"][tick])
                        .font(StrapTypography.body(9))
                        .foregroundStyle(Color.appMuted)
                        .position(x: 20, y: y)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let x = labelWidth + slot * (CGFloat(index) + 0.5)
                    if let night = matching(day) {
                        let start = minutesFromEightPM(night.startUnix)
                        let duration = Double(night.endUnix - night.startUnix) / 60
                        let top = plotHeight * CGFloat(min(max(start / axisMinutes, 0), 1))
                        let bottom = plotHeight * CGFloat(min(max((start + duration) / axisMinutes, 0), 1))
                        let selected = index == 4
                        RoundedRectangle(cornerRadius: 3)
                            .fill(selected ? Color.appSleep : Color(hex: 0x777D81).opacity(0.8))
                            .frame(width: min(slot * 0.38, 26), height: max(2, bottom - top))
                            .position(x: x, y: (top + bottom) / 2)
                        if selected {
                            Text(timeLabel(night.startUnix))
                                .position(x: min(geo.size.width - 42, max(labelWidth + 42, x)), y: max(9, top - 12))
                            Text(timeLabel(night.endUnix))
                                .position(x: min(geo.size.width - 42, max(labelWidth + 42, x)), y: min(plotHeight - 8, bottom + 12))
                        }
                    }
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(StrapTypography.body(10, weight: index == 4 ? .bold : .regular))
                        .foregroundStyle(index == 4 ? Color.appFG : Color.appMuted)
                        .position(x: x, y: geo.size.height - 10)
                }
            }
            .font(StrapTypography.body(10, weight: .bold))
            .foregroundStyle(Color.appSleep)
        }
        .frame(height: 260)
        .accessibilityLabel("Bedtime and wake time for five calendar days; blank days have no recorded sleep")
    }
}
