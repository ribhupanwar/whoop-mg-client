import SwiftUI

/// Sleep Analysis — new screen (post-mockup spec). Live mode stays "—" until
/// an overnight capture exists; demo numbers are labelled sample by the banner.
/// Quiet-vs-movement only: no light/deep/REM staging.
struct SleepAnalysisView: View {
    @EnvironmentObject private var store: AppStore

    private var demo: Bool { store.isPreview }

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

    private var performancePanel: some View {
        Panel {
            SectionTitle("Sleep performance")
            RingView(
                progress: demo ? Double(SampleData.sleepPerformance) / 100.0 : nil,
                color: .appSleep,
                lineWidth: 12,
                size: 170,
                centerText: demo ? "\(SampleData.sleepPerformance)%" : "—",
                centerFont: 40
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Text(demo
                 ? "Sample: 66% of your needed sleep last night."
                 : "needs an overnight capture")
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: Components

    private var componentsPanel: some View {
        Panel {
            SectionTitle("Components")
            componentRow(title: "Hours vs. needed", percent: SampleData.hoursVsNeeded, waiting: "needs an overnight capture")
            componentRow(title: "Sleep consistency", percent: SampleData.sleepConsistency, waiting: "needs 2+ nights")
            componentRow(title: "Sleep efficiency", percent: SampleData.sleepEfficiency, waiting: "needs an overnight capture")
            componentRow(title: "High sleep stress", percent: SampleData.highSleepStress, waiting: "needs 7 sleep nights", color: .appWarn)
        }
    }

    private func componentRow(title: String, percent: Int, waiting: String, color: Color = .appSleep) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appFG)
                Spacer()
                Text(demo ? "\(percent)%" : "—")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(demo ? Color.appFG : Color.appMuted)
            }
            MiniProgress(fraction: demo ? Double(percent) / 100.0 : nil, color: color)
            if !demo {
                Text(waiting)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.appMuted)
            }
        }
        .padding(.vertical, 7)
    }

    // MARK: Last night

    private var lastNightPanel: some View {
        Panel {
            CardHead(title: "Last night's sleep")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(demo ? SampleData.sleepHours : "—")
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
                .padding(.bottom, 8)
            } else {
                EmptyState(
                    title: "wear it tonight",
                    detail: "Heart rate through the night appears after an overnight capture."
                )
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.appRaised))
                .padding(.bottom, 8)
            }

            SplitBar(segments: demo
                     ? [
                        SplitBar.Segment(fraction: SampleData.asleepMinutes / (SampleData.asleepMinutes + SampleData.awakeMinutes), color: .appSleep),
                        SplitBar.Segment(fraction: SampleData.awakeMinutes / (SampleData.asleepMinutes + SampleData.awakeMinutes), color: .appWarn)
                     ]
                     : [SplitBar.Segment(fraction: 1.0, color: .appRaised)])
            .padding(.bottom, 8)

            HStack(spacing: 8) {
                splitValue(demo ? "5:49" : "—", label: "asleep")
                splitValue(demo ? "1:07" : "—", label: "awake")
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
                Text(demo ? "\(SampleData.wakeEvents)" : "—")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.appFG)
            }
        }
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
            CardHead(title: "Hours vs. needed", trailing: demo ? "\(SampleData.hoursVsNeeded)%" : "—")
            SectionTitle("Hours of sleep")
            SplitBar(segments: demo
                     ? [SplitBar.Segment(fraction: Double(SampleData.hoursVsNeeded) / 100.0, color: .appSleep)]
                     : [SplitBar.Segment(fraction: 1.0, color: .appRaised)])
            .padding(.bottom, 8)
            HStack {
                splitValue(demo ? SampleData.sleepHours : "—", label: "asleep")
                VStack(alignment: .trailing, spacing: 2) {
                    Text(demo ? SampleData.needTotal : "—")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text("needed").font(.system(size: 10)).foregroundStyle(Color.appMuted)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.bottom, 10)
            SectionTitle("Where the need comes from")
            needRow("Base need", demo: SampleData.needBase, live: SampleData.needBase)
            needRow("Sleep debt", demo: SampleData.needDebt, live: "—")
            needRow("Tomorrow's plan", demo: SampleData.needTomorrow, live: "—")
            Hint("Our local need model: base + running debt (capped at 2 h) + tomorrow's allowance. Debt starts counting from your first recorded night.")
        }
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

    private var consistencyPanel: some View {
        Panel {
            CardHead(title: "Sleep consistency", trailing: demo ? "\(SampleData.sleepConsistency)%" : "—")
            if demo {
                BedWakeChart(
                    spans: Array(SampleData.weeklyBedWake.suffix(5)),
                    labels: Array(SampleData.weekDays.suffix(5)),
                    height: 140
                )
                Hint("Dashed lines mark the grid; a night counts when both bed and wake sit within ±60 min of your medians.")
            } else {
                EmptyState(title: "Needs 2+ recorded nights",
                           detail: "Your median bedtime and wake time appear once two nights are stored.")
            }
        }
    }

    // MARK: Sleep stress detail

    private var stressDetailPanel: some View {
        Panel {
            CardHead(title: "Sleep stress", trailing: demo ? "\(SampleData.highSleepStress)% high" : "—")
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
            } else {
                EmptyState(title: "Needs 7 sleep nights of baseline",
                           detail: "Each 5-minute window's lnRMSSD is scored against your own sleep norm — never the awake one.")
            }
        }
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
            } else {
                EmptyState(title: "needs more nights",
                           detail: "The 7-day trends fill in as overnight captures accumulate; nothing is back-filled with guesses.")
            }
        }
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