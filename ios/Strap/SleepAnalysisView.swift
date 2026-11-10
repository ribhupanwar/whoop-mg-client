import SwiftUI

/// Sleep Analysis — every live value below comes from the last stored capture:
/// the detector's sleep periods, the capture HR series and the recorded nights.
/// Quiet-vs-movement only: no light/deep/REM staging.
struct SleepAnalysisView: View {
    @EnvironmentObject private var store: AppStore

    private var demo: Bool { store.isPreview }

    private var analysis: SleepAnalysis? {
        demo ? nil : store.band.lastSleepAnalysis
    }

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
                stagingNote
                needPanel
                consistencyPanel
                stressDetailPanel
                weeklyPanel
                coachButton
            }
        }
        .navigationTitle("Sleep analysis")
        .navigationBarTitleDisplayMode(.inline)
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
        guard let analysis else {
            return "needs an overnight capture"
        }
        return "\(String(format: "%.1f", analysis.hours)) h of \(String(format: "%.1f", analysis.needHours)) h needed, from the last stored capture."
    }

    // MARK: Components

    private var componentsPanel: some View {
        Panel {
            SectionTitle("Components")
            componentRow(
                title: "Hours vs. needed",
                percent: demo ? Double(SampleData.hoursVsNeeded) : analysis?.hoursVsNeededPct,
                waiting: "needs an overnight capture"
            )
            componentRow(
                title: "Sleep consistency",
                percent: demo ? Double(SampleData.sleepConsistency) : analysis?.consistencyPct,
                waiting: "needs 2+ nights with both bed and wake detected"
            )
            componentRow(
                title: "Sleep efficiency",
                percent: demo ? Double(SampleData.sleepEfficiency) : analysis?.efficiencyPct,
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

    private var lastNightHours: Double? {
        demo ? nil : analysis?.hours
    }

    private var asleepHours: Double? {
        guard let analysis else { return nil }
        return analysis.hours * analysis.efficiencyPct / 100.0
    }

    private var awakeHours: Double? {
        guard let analysis, let asleepHours else { return nil }
        return max(0, analysis.hours - asleepHours)
    }

    private var lastNightPanel: some View {
        Panel {
            CardHead(title: "Last night's sleep")

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
            } else if let series = store.band.summary?.heartRateSeries, series.count >= 2 {
                LineChart(
                    values: series,
                    color: .appAccent,
                    minY: series.min().map { floor($0) - 2 },
                    maxY: series.max().map { ceil($0) + 2 },
                    height: 120,
                    yLabels: seriesLabels(series),
                    xLabels: captureLabels
                )
                .padding(.bottom, 4)
                Text("Per-minute means across the stored capture.")
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

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wake events")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text("movement events")
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
        guard !periods.isEmpty else { return "—" }
        return "\(periods.reduce(0) { $0 + $1.wakeEvents })"
    }

    private var lastNightSegments: [SplitBar.Segment] {
        if demo {
            let total = SampleData.asleepMinutes + SampleData.awakeMinutes
            return [
                SplitBar.Segment(fraction: SampleData.asleepMinutes / total, color: .appSleep),
                SplitBar.Segment(fraction: SampleData.awakeMinutes / total, color: .appWarn)
            ]
        }
        if let analysis, analysis.hours > 0 {
            let fraction = min(max(analysis.efficiencyPct / 100.0, 0), 1)
            return [
                SplitBar.Segment(fraction: fraction, color: .appSleep),
                SplitBar.Segment(fraction: 1.0 - fraction, color: .appWarn)
            ]
        }
        return [SplitBar.Segment(fraction: 1.0, color: .appRaised)]
    }

    private var captureLabels: [String] {
        guard let summary = store.band.summary,
              let first = summary.firstUnix, let last = summary.lastUnix else { return [] }
        return [clock(first), clock(last)]
    }

    private func seriesLabels(_ values: [Double]) -> [String] {
        guard let max = values.max(), let min = values.min() else { return [] }
        let top = ceil(max) + 2
        let bottom = floor(min) - 2
        return [
            "\(Int(top))",
            "\(Int((top + bottom) / 2))",
            "\(Int(bottom))"
        ]
    }

    private func clock(_ unix: Int) -> String {
        CoachFormat.clock((unix / 60 % 1440 + 1440) % 1440)
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

    // MARK: Staging disclaimer

    private var stagingNote: some View {
        Text("Light/deep/REM staging is not implemented — it needs a validated model; we report quiet-vs-movement only. Restorative sleep (deep + REM) is therefore absent too.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.appFG)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.appSurface))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appWarn.opacity(0.6), lineWidth: 1))
            .padding(.bottom, 11)
    }

    // MARK: Hours vs. needed detail

    private var needPanel: some View {
        Panel {
            CardHead(
                title: "Hours vs. needed",
                trailing: (demo ? Double(SampleData.hoursVsNeeded) : analysis?.hoursVsNeededPct)
                    .map { String(format: "%.0f%%", $0) } ?? "—"
            )
            SectionTitle("Hours of sleep")
            SplitBar(segments: [
                SplitBar.Segment(fraction: hoursVsNeededFraction, color: .appSleep)
            ])
            .padding(.bottom, 8)
            HStack {
                splitValue(
                    demo ? SampleData.sleepHours : analysis.map { CoachFormat.duration($0.hours) } ?? "—",
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
            SectionTitle("Where the need comes from")
            needRow("Base need", demo: SampleData.needBase, live: CoachFormat.duration(store.settings.sleepNeedHours))
            needRow("Sleep debt", demo: SampleData.needDebt, live: debt.map { "+" + CoachFormat.duration($0) } ?? "—")
            needRow("Tomorrow's plan", demo: SampleData.needTomorrow, live: "+" + CoachFormat.duration(store.settings.sleepIntent.extraHours))
            Hint("Our local need model: base + running debt (capped at 2 h) + tomorrow's allowance. Debt starts counting from your first recorded night.")
        }
    }

    private var hoursVsNeededFraction: Double {
        let pct = demo ? Double(SampleData.hoursVsNeeded) : analysis?.hoursVsNeededPct
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
                Hint("Restorative sleep (deep + REM) is not charted — staging needs a validated model we don't have. Every series here comes from our own local rules.")
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
                Hint("Both charts come from your recorded nights: hours vs. need, and the capped running shortfall our coach uses. Staging stays absent.")
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
