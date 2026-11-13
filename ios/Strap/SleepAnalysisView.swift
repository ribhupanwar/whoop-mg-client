import SwiftUI

/// Sleep Analysis — every live value below comes from the last stored capture:
/// the detector's sleep periods, the capture HR series and the recorded nights.
/// The hypnogram is a labelled four-class estimate, never a PSG reading.
struct SleepAnalysisView: View {
    @EnvironmentObject private var store: AppStore
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

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                performancePanel
                componentsPanel
                lastNightPanel
                stagingPanel
                needPanel
                consistencyPanel
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
                        .font(.footnote)
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
            Text("End this sleep session at the selected Wake Time? You can edit the time later.")
        }
        .navigationTitle("Sleep analysis")
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
        UserDefaults.standard.set(corrections, forKey: "strap.sleep.time.corrections.v1")
        store.band.notifySleepCorrectionChanged()
        showSleepEditor = false
    }

    // MARK: Performance ring

    private var performancePct: Double? {
        demo ? Double(SampleData.sleepPerformance) : analysis?.performancePct
    }

    private var performancePanel: some View {
        Panel {
            SectionTitle("Sleep performance")
            RingView(
                progress: performancePct.map { min(max($0 / 100.0, 0), 1) },
                color: .appSleep,
                lineWidth: 12,
                size: 170,
                centerText: performancePct.map { "\(Int($0.rounded()))%" } ?? "—",
                centerFont: 40
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Text(performanceCaption)
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
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
            SectionTitle("Components")
            componentRow(
                title: "Hours vs. needed",
                percent: demo ? Double(SampleData.hoursVsNeeded) : reconciledHoursVsNeededPct,
                waiting: "needs an overnight capture"
            )
            componentRow(
                title: "Sleep consistency",
                percent: demo ? Double(SampleData.sleepConsistency) : analysis?.consistencyPct,
                waiting: "needs 2+ nights with both bed and wake detected"
            )
            componentRow(
                title: "Sleep efficiency",
                percent: demo ? Double(SampleData.sleepEfficiency) : reconciledEfficiencyPct,
                waiting: "needs an overnight capture"
            )
            componentRow(
                title: "High sleep stress",
                percent: demo ? Double(SampleData.highSleepStress) : analysis?.stress.highPct,
                waiting: analysis?.stress.reason ?? "needs 7 sleep nights",
                color: .appWarn
            )
        }
    }

    private func componentRow(title: String, percent: Double?, waiting: String, color: Color = .appSleep) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appFG)
                Spacer()
                Text(percent.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(percent == nil ? Color.appMuted : Color.appFG)
            }
            MiniProgress(fraction: percent.map { min(max($0 / 100.0, 0), 1) }, color: color)
            if !demo && percent == nil {
                Text(waiting)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.appMuted)
            }
        }
        .padding(.vertical, 7)
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
        let corrections = UserDefaults.standard.dictionary(forKey: "strap.sleep.time.corrections.v1") as? [String: [Int]] ?? [:]
        let times = SleepCorrectionStore.times(for: period, overrides: corrections)
        correctedSleepStart = Date(timeIntervalSince1970: TimeInterval(session?.startUnix ?? times?.first ?? period.startUnix))
        correctedSleepEnd = Date(timeIntervalSince1970: TimeInterval(session?.endUnix ?? times?.last ?? (period.endUnix + 1)))
        showSleepEditor = true
    }

    private var lastNightPanel: some View {
        Panel {
            HStack {
                Text("Last night's sleep")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.appFG)
                Spacer()
                if !demo, editablePeriod != nil {
                    Button(action: openSleepEditor) {
                        Label("EDIT", systemImage: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.appAccent)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(demo ? SampleData.sleepHours : lastNightHours.map(CoachFormat.duration) ?? "—")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.appFG)
                Text("HOURS OF SLEEP")
                    .font(.system(size: 9.5))
                    .tracking(0.7)
                    .foregroundStyle(Color.appMuted)
                Spacer()
            }
            .padding(.bottom, 8)

            if demo {
                LineChart(
                    values: SampleData.sleepHRSeries,
                    color: .appAccent,
                    minY: 45,
                    maxY: 75,
                    height: 120,
                    yLabels: ["75", "60", "45"],
                    xLabels: ["00:26", "07:33"]
                )
                .padding(.bottom, 4)
            } else if let session, !session.heartRate.isEmpty {
                SleepHeartRateChart(session: session)
                    .padding(.bottom, 4)
                Text("Per-minute HR within this sleep window. Gaps mean missing data.")
                    .font(.system(size: 10.5))
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
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
                .padding(.bottom, 8)
                if let reason = session.durationReason { Hint(reason + " Missing time is not awake time.") }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Movement bouts")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text("not verified awakenings")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.appMuted)
                }
                Spacer()
                Text(demo ? "\(SampleData.wakeEvents)" : wakeEventText)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.appFG)
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.appFG)
            Text(label)
                .font(.system(size: 10))
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
        Panel {
            CardHead(title: "Sleep stages", trailing: stagingTrailing)
            if demo {
                SplitBar(segments: splitSegments(demoStageMinutes))
                    .padding(.bottom, 10)
                stageValues(demoStageMinutes)
                Hint("Sample stages, not a reading. Live captures stage 30-second epochs from on-wrist heart rate, its 5- and 11-minute variability, wrist movement and R-R breathing regularity.")
            } else if let staging, !staging.segments.isEmpty {
                if session?.isEdited == true {
                    Hint("Recalculated from retained sensor data for your edited bed/wake times.")
                }
                SplitBar(segments: segments(for: staging))
                    .padding(.bottom, 10)
                stageValues(stagingMinutes(staging))
                if let session {
                    HStack(alignment: .top, spacing: 8) {
                        StageHypnogram(
                            segments: staging.segments,
                            startUnix: session.startUnix,
                            endUnix: session.endUnix
                        )
                    }
                    .padding(.vertical, 12)
                }
                if let session {
                    Hint("Window \(clock(session.startUnix))–\(clock(session.endUnix)). \(staging.epochs) estimated epochs; \(Int((staging.hrCoverage * 100).rounded()))% valid HR seconds. Blank intervals are unclassified. An approximation, not PSG-validated or WHOOP's staging.")
                }
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

    // WHOOP-style stacked stage distribution, rather than four compressed columns.
    private func stageValues(_ minutes: [SleepStage: Double]) -> some View {
        let total = max(1.0, session.map { $0.timeInBedHours * 60 } ?? minutes.values.reduce(0, +))
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("DURATION")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Color.appMuted)
                Spacer()
                Text(CoachFormat.duration(total / 60.0))
                    .font(.system(size: 16, weight: .semibold))
            }
            ForEach([SleepStage.wake, .light, .deep, .rem]) { stage in
                let value = minutes[stage] ?? 0
                let fraction = min(1.0, max(0.0, value / total))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Circle()
                            .strokeBorder(stage.color, lineWidth: 2)
                            .frame(width: 19, height: 19)
                        Text(stage == .deep ? "SWS (DEEP)" : stage.title.uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(0.5)
                        Text(String(format: "%.0f%%", fraction * 100))
                            .font(.system(size: 11))
                            .foregroundStyle(stage.color)
                        Spacer()
                        Text(CoachFormat.duration(value / 60.0))
                            .font(.system(size: 17, weight: .semibold))
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.appRaised)
                            Capsule().fill(stage.color)
                                .frame(width: max(0, geometry.size.width * fraction))
                        }
                    }
                    .frame(height: 12)
                }
            }
            if let session, session.unclassifiedHours > 0 {
                HStack {
                    Text("UNCLASSIFIED")
                        .foregroundStyle(Color.appMuted)
                    Spacer()
                    Text(CoachFormat.duration(session.unclassifiedHours))
                }
                .font(.system(size: 12, weight: .medium))
            }
            let restorative = (minutes[.deep] ?? 0) + (minutes[.rem] ?? 0)
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(SleepStage.deep.color)
                    .frame(width: 10, height: 10)
                Text("RESTORATIVE SLEEP")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                Spacer()
                Text(CoachFormat.duration(restorative / 60.0))
                    .font(.system(size: 17, weight: .semibold))
            }
            .padding(.top, 4)
        }
        .padding(.bottom, 8)
    }

    // MARK: Hours vs. needed detail

    private var needPanel: some View {
        Panel {
            CardHead(
                title: "Hours vs. needed",
                trailing: (demo ? Double(SampleData.hoursVsNeeded) : reconciledHoursVsNeededPct)
                    .map { String(format: "%.0f%%", $0) } ?? "—"
            )
            SectionTitle("Hours of sleep")
            SplitBar(segments: [
                SplitBar.Segment(fraction: hoursVsNeededFraction, color: .appSleep)
            ])
            .padding(.bottom, 8)
            HStack {
                splitValue(
                    demo ? SampleData.sleepHours : asleepHours.map(CoachFormat.duration) ?? "—",
                    label: "asleep"
                )
                VStack(alignment: .trailing, spacing: 2) {
                    Text(demo ? SampleData.needTotal : analysis.map { CoachFormat.duration($0.needHours) } ?? "—")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text("needed").font(.system(size: 10)).foregroundStyle(Color.appMuted)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.bottom, 10)
            SectionTitle("Next night's plan — separate from last night's score")
            needRow("Base need", demo: SampleData.needBase, live: CoachFormat.duration(store.settings.sleepNeedHours))
            needRow("Debt allowance (max 2 h)", demo: SampleData.needDebt, live: debt.map { "+" + CoachFormat.duration(min($0, SleepCoach.debtCapHours)) } ?? "—")
            needRow("Tomorrow's plan", demo: SampleData.needTomorrow, live: "+" + CoachFormat.duration(store.settings.sleepIntent.extraHours))
            needRow("Next-night target", demo: SampleData.needTotal, live: CoachFormat.duration(
                SleepCoach.recommendation(
                    baseNeedHours: store.settings.sleepNeedHours, intent: store.settings.sleepIntent,
                    debtHours: debt, wakeMinutes: store.settings.wakeTimeMinutes
                ).needHours
            ))
            Hint("The score above compares last night's estimated asleep time with your base need. The future target adds a capped debt allowance and tomorrow's plan; incomplete nights never create debt.")
        }
    }

    private var hoursVsNeededFraction: Double {
        let pct = demo ? Double(SampleData.hoursVsNeeded) : reconciledHoursVsNeededPct
        return min(max((pct ?? 0) / 100.0, 0), 1)
    }

    private func needRow(_ title: String, demo: String, live: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).foregroundStyle(Color.appMuted)
            Spacer()
            Text(self.demo ? demo : live)
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.appFG)
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
            CardHead(
                title: "Sleep consistency",
                trailing: (demo ? Double(SampleData.sleepConsistency) : analysis?.consistencyPct)
                    .map { String(format: "%.0f%%", $0) } ?? "—"
            )
            if demo {
                BedWakeChart(
                    spans: Array(SampleData.weeklyBedWake.suffix(5)),
                    labels: Array(SampleData.weekDays.suffix(5)),
                    height: 140
                )
                Hint("Dashed lines mark the grid; a night counts when both bed and wake sit within ±60 min of your medians.")
            } else if liveBedWake.count >= 2 {
                BedWakeChart(
                    spans: liveBedWake,
                    labels: liveNights.map { weekdayLabel(forUnix: $0.startUnix) },
                    axisMax: 960,
                    height: 140
                )
                Hint("Bars run from 18:00; a night counts when both bed and wake sit within ±60 min of your circular medians.")
            } else {
                EmptyState(title: "Needs 2+ recorded nights",
                           detail: "Your median bedtime and wake time appear once two nights are stored.")
            }
        }
    }

    // MARK: Sleep stress detail

    private var stressDetailPanel: some View {
        Panel {
            CardHead(
                title: "Sleep stress",
                trailing: demo ? "\(SampleData.highSleepStress)% high" : highSleepStressText
            )
            if demo {
                LineChart(
                    values: SampleData.sleepStressSeries,
                    color: .appGood,
                    minY: 0, maxY: 3,
                    height: 110,
                    yLabels: ["3.0", "1.5", "0.0"],
                    xLabels: ["1:28 AM", "8:22 AM"]
                )
                .padding(.bottom, 8)
                HStack(spacing: 8) {
                    stressSplit("0:00", "high · 0%", color: .appHigh)
                    stressSplit("0:19", "medium · 5%", color: .appWarn)
                    stressSplit("6:34", "low · 95%", color: .appGood)
                }
            } else if let stress = analysis?.stress, stress.lowPct != nil {
                SplitBar(segments: stressSegments(stress))
                    .padding(.bottom, 10)
                HStack(spacing: 8) {
                    stressSplit(percentText(stress.highPct), "high", color: .appHigh)
                    stressSplit(percentText(stress.mediumPct), "medium", color: .appWarn)
                    stressSplit(percentText(stress.lowPct), "low", color: .appGood)
                }
                Hint("\(stress.windows) five-minute sleep windows scored against your own sleep baseline.")
            } else {
                EmptyState(
                    title: "Needs 7 sleep nights of baseline",
                    detail: analysis?.stress.reason
                        ?? "Each 5-minute window's lnRMSSD is scored against your own sleep norm — never the awake one."
                )
            }
        }
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
            Text(value).font(.system(size: 15, weight: .medium)).foregroundStyle(color)
            Text(label).font(.system(size: 10)).foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Weekly trends

    private var weeklyPanel: some View {
        Panel {
            SectionTitle("Weekly trends")
            if demo {
                trendBlock("Sleep performance", "%") {
                    BarChart(values: SampleData.weeklySleepPerformance, labels: SampleData.weekDays,
                             maxValue: 100, color: .appSleep, height: 110)
                }
                trendBlock("Hours vs. needed", "hours") {
                    ZStack {
                        LineChart(values: SampleData.weeklyHoursNeeded, color: .appMuted,
                                  minY: 0, maxY: 12, height: 110)
                        LineChart(values: SampleData.weeklyHoursSleep, color: .appSleep,
                                  minY: 0, maxY: 12, height: 110,
                                  yLabels: ["12h", "8h", "4h"], xLabels: SampleData.weekDays)
                    }
                    ChartLegend(items: [("asleep", .appSleep), ("needed", .appMuted)])
                }
                trendBlock("Hours vs. needed", "%") {
                    BarChart(values: SampleData.weeklyHoursVsNeeded, labels: SampleData.weekDays,
                             maxValue: 100, color: .appSleep, height: 100)
                }
                trendBlock("Consistency", "% within ±60 min") {
                    BarChart(values: SampleData.weeklyConsistency, labels: SampleData.weekDays,
                             maxValue: 100, color: .appSleep, height: 100)
                }
                trendBlock("Time in bed", "bed → wake") {
                    BedWakeChart(spans: SampleData.weeklyBedWake, labels: SampleData.weekDays, height: 150)
                }
                trendBlock("Efficiency", "% quiet in bed") {
                    LineChart(values: SampleData.weeklyEfficiency, color: .appSleep,
                              minY: 80, maxY: 100, height: 110,
                              yLabels: ["100%", "90%", "80%"], xLabels: SampleData.weekDays)
                }
                trendBlock("Sleep debt", "running shortfall") {
                    BarChart(values: SampleData.weeklyDebtMinutes, labels: SampleData.weekDays,
                             maxValue: 150, color: .appWarn, height: 100)
                }
                trendBlock("Sleep stress", "share of night") {
                    StackedBarChart(bars: SampleData.weeklyStressSegments,
                                    colors: [.appHigh, .appWarn, .appGood],
                                    labels: SampleData.weekDays, maxValue: 100, height: 110)
                    ChartLegend(items: [("low", .appGood), ("medium", .appWarn), ("high", .appHigh)])
                }
                Hint("Every series here comes from our own local rules. The stage estimate above is a 30-second approximation, not a PSG reading.")
            } else if nights.count >= 2 {
                trendBlock("Hours vs. needed", "% of need") {
                    BarChart(
                        values: recentNights.map { night in
                            min(100, 100.0 * night.actualHours / max(night.neededHours, 0.1))
                        },
                        labels: recentNights.map { weekdayLabel(forDayKey: $0.dateKey) },
                        maxValue: 100, color: .appSleep, height: 110
                    )
                }
                trendBlock("Sleep debt", "running shortfall") {
                    BarChart(
                        values: liveDebtMinutes,
                        labels: recentNights.map { weekdayLabel(forDayKey: $0.dateKey) },
                        maxValue: max(60, (liveDebtMinutes.max() ?? 0) * 1.25),
                        color: .appWarn, height: 100
                    )
                }
                Hint("Both charts come from your recorded nights: hours vs. need, and the capped running shortfall our coach uses. The night's stage estimate and hypnogram sit above.")
            } else {
                EmptyState(title: "needs more nights",
                           detail: "The trends fill in as overnight captures accumulate; nothing is back-filled with guesses.")
            }
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
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.appFG)
                Spacer()
                Text(unit).font(.system(size: 10.5)).foregroundStyle(Color.appMuted)
            }
            content()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Color.appLine).frame(height: 1) }
    }

    private var coachButton: some View {
        NavigationLink(value: Route.sleepCoach) {
            Text("OPEN SLEEP COACH ›")
                .font(.system(size: 11, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Color.appFG)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.appRaised))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private extension SleepStage {
    var color: Color {
        switch self {
        case .wake: return Color(red: 0.78, green: 0.79, blue: 0.80)
        case .light: return Color(red: 0.65, green: 0.61, blue: 0.92)
        case .deep: return Color(red: 0.93, green: 0.39, blue: 0.86)
        case .rem: return Color(red: 0.65, green: 0.28, blue: 0.87)
        }
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
                        .font(.system(size: 8.5))
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
