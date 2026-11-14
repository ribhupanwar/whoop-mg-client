import Foundation
import SwiftUI

/// The My Dashboard metric rows, shared verbatim by Home and the Dashboard tab
/// so the ordering can never drift: HRV, RHR, Steps, HR zones 1–3 weekly,
/// HR zones 4–5 weekly, VO₂ max, Calories, Stress Monitor.
/// No respiratory rate or SpO₂ here: both are Health-detail estimates, and
/// SpO₂ is only an unvalidated band candidate.
///
/// The order and visibility come from `AppSettings.dashboardOrder` /
/// `hiddenDashboardRows`, so the Customize sheet is the only place that decides
/// what this stack shows.
struct DashboardRows: View {
    @EnvironmentObject private var store: AppStore
    @State private var showVO2Detail = false

    private var demo: Bool { store.isPreview }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(store.visibleDashboardRows) { row in
                block(for: row)
            }
            if store.visibleDashboardRows.isEmpty {
                Panel {
                    SectionTitle("No rows shown")
                    Hint("Every dashboard row is hidden. Open Customize to bring rows back.")
                }
                .padding(.bottom, 8)
            }
            Hint("The small number under a metric is your comparison value and stays absent until history exists. VO₂ max and calories are published estimates, never strap measurements.")
        }
    }

    @ViewBuilder
    private func block(for row: DashboardRow) -> some View {
        switch row {
        case .hrv:
            MetricRow(
                icon: "waveform.path.ecg",
                title: "Heart rate variability",
                value: demo ? String(format: "%.0f", SampleData.hrvMS) : hrvText,
                unit: (demo || latestNightHRV != nil) ? "ms" : nil,
                detail: demo ? "\(SampleData.hrvCompare)" : compactComparison(hrvDetail),
                detailColor: .appMuted,
                trendUp: demo ? true : hrvTrendUp,
                trendFavourable: demo ? true : hrvTrendUp
            )
        case .restingHR:
            MetricRow(
                icon: "heart.pulse",
                title: "Resting heart rate",
                value: demo ? String(format: "%.0f", SampleData.rhr) : rhrText,
                detail: demo ? "\(SampleData.rhrCompare)" : compactComparison(rhrDetail),
                detailColor: .appMuted,
                trendUp: demo ? true : rhrTrendUp,
                trendFavourable: demo ? false : rhrTrendUp.map { !$0 }
            )
        case .steps:
            MetricRow(
                icon: "figure.walk",
                title: "Steps",
                value: demo ? SampleData.steps.formatted() : stepsText,
                detail: demo ? SampleData.stepsCompare.formatted() : nil,
                detailColor: demo ? .appWarn : .appMuted
            )
        case .zonesLow:
            MetricRow(
                icon: "heart.pulse",
                title: "HR zones 1–3 · weekly",
                value: demo ? SampleData.zones13 : zoneText(high: false),
                detail: demo ? SampleData.zones13Compare : nil,
                detailColor: demo ? .appGood : .appMuted
            )
        case .zonesHigh:
            MetricRow(
                icon: "heart.pulse",
                title: "HR zones 4–5 · weekly",
                value: demo ? SampleData.zones45 : zoneText(high: true),
                detail: demo ? SampleData.zones45Compare : nil,
                detailColor: demo ? .appWarn : .appMuted
            )
        case .strength:
            MetricRow(icon: "dumbbell", title: "Strength activity time",
                      value: strengthText, detail: nil, detailColor: .appMuted)
        case .vo2Max:
            vo2Block
        case .calories:
            MetricRow(
                icon: "flame",
                title: "Calories",
                value: demo ? SampleData.calories.formatted() : caloriesValue,
                unit: (demo == false && store.captureActiveKcal != nil) ? "kcal" : nil,
                detail: demo ? SampleData.caloriesCompare.formatted() : nil,
                detailColor: demo ? .appWarn : .appMuted
            )
        case .stress:
            stressRow
        }
    }

    // MARK: Live values

    private var summary: CaptureSummary? { store.lastCapture }

    private var latestNightHRV: Double? {
        DailyAnalysis.latestNightHRV(from: store.band.days)
    }

    private var hrvText: String {
        ActivityFormat.whole(latestNightHRV) ?? "—"
    }

    private var hrvDetail: String {
        guard latestNightHRV != nil else { return "needs a validated overnight RR window" }
        if let baseline = store.band.baseline {
            let norm = Int(exp(baseline.lnRMSSDMean).rounded())
            return "\(norm)"
        }
        return "overnight reading"
    }

    /// Compact dashboard uses numerical comparisons only; long provenance stays in detail views.
    private func compactComparison(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return trimmed
    }

    private var hrvTrendUp: Bool? {
        guard latestNightHRV != nil, store.hasRecoveryBaseline,
              let value = latestNightHRV.map({ log($0) }),
              let baseline = store.band.baseline,
              value.isFinite, abs(value - baseline.lnRMSSDMean) >= 0.01 else { return nil }
        return value > baseline.lnRMSSDMean
    }

    private var rhrTrendUp: Bool? {
        guard store.hasRecoveryBaseline,
              let value = store.measuredRestingHR,
              let baseline = store.band.baseline,
              value.isFinite, abs(value - baseline.rhrMean) >= 0.5 else { return nil }
        return value > baseline.rhrMean
    }

    private var rhrText: String { ActivityFormat.whole(store.measuredRestingHR) ?? "—" }

    private var rhrDetail: String {
        guard store.measuredRestingHR != nil else { return "needs a capture" }
        if let baseline = store.band.baseline {
            return String(format: "%.0f", baseline.rhrMean)
        }
        return "resting window"
    }

    private var todayRecordedSteps: Int? {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        return store.band.days.first(where: { $0.dateKey == today })?.steps
    }

    private var stepsText: String {
        todayRecordedSteps.map { $0.formatted() } ?? "—"
    }

    private var stepsDetail: String {
        todayRecordedSteps != nil ? "today · recorded minimum" : "needs band history sync"
    }

    private func zoneText(high: Bool) -> String {
        guard let minutes = store.weeklyZoneMinutes(high: high) else { return "—" }
        return ActivityFormat.clock(minutes: minutes)
    }

    private var zoneDetail: String {
        store.weeklyZoneMinutes(high: false) != nil
            ? "last 7 days · recorded HR"
            : "needs band history or a live session"
    }

    private var strengthText: String {
        if demo { return "0:40" }
        let key = JournalStore.dayKey(for: Date())
        let logs = store.manualActivities(on: key).filter { $0.kind.usesSets }
        guard !logs.isEmpty, logs.allSatisfy({ $0.minutes > 0 }) else { return "—" }
        return ActivityFormat.clock(minutes: logs.reduce(0.0) { $0 + Double($1.minutes) })
    }

    private var vo2Text: String {
        store.vo2Estimate.map { String(format: "%.1f", $0) } ?? "—"
    }

    private var caloriesValue: String {
        store.captureActiveKcal.map { String(format: "%.0f", $0) } ?? "—"
    }

    private var vo2Detail: String {
        if store.settings.maxHROverride == nil {
            return "Max HR comes from 208 − 0.7 × age, so this carries the formula's wide error. Set a max HR you actually reached in a hard session (Settings) for a sharper estimate. A population formula, not a lab test and never a strap reading."
        }
        return "Max HR comes from the override you entered; resting HR is your measured quiet value. A population formula with wide error — not a lab test, and never a strap reading."
    }

    private var stressValue: String {
        guard let index = store.band.stress.index else { return "—" }
        return "\(store.band.stress.band.uppercased()) \(String(format: "%.1f", index))"
    }

    private var stressCaption: String {
        store.band.stress.reason ?? "awake baseline · \(store.recordedDayCount) days"
    }

    // MARK: VO₂ max — published estimate, never a strap reading

    private var vo2Block: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showVO2Detail.toggle()
            } label: {
                HStack(spacing: 11) {
                    DashboardMetricIcon(symbol: "lungs")
                    Text("VO₂ MAX")
                        .font(StrapTypography.body(12.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Text(demo ? String(format: "%.1f", SampleData.vo2) : vo2Text)
                        .font(StrapTypography.metric(26, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.appFG)
                    Text("›")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.appMuted)
                }
                .padding(.horizontal, AppLayout.cardInset)
                .frame(height: 60)
                .background(RoundedRectangle(cornerRadius: AppLayout.metricRadius).fill(LinearGradient.appCard))
                .overlay(RoundedRectangle(cornerRadius: AppLayout.metricRadius).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)

            if showVO2Detail {
                Text(vo2Detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppLayout.cardInset)
                    .padding(.top, 4)
            }
        }
        .padding(.bottom, 10)
    }

    // MARK: Stress monitor row

    private var stressRow: some View {
        NavigationLink(value: Route.stress) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("STRESS MONITOR")
                        .font(StrapTypography.body(12, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Text("›").font(.system(size: 15)).foregroundStyle(Color.appMuted)
                }
                HStack {
                    Text(demo ? "Last updated 11:49 · sample" : stressCaption)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.appMuted)
                    Spacer()
                    Text(demo ? "LOW \(String(format: "%.1f", SampleData.stressHome))" : stressValue)
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.5)
                        .foregroundStyle(demo ? Color.appAccent : Color.appFG)
                }
                if demo {
                    LineChart(values: SampleData.stressMiniSeries, color: .appAccent, minY: 0, maxY: 3,
                              height: 150, yLabels: ["3.0", "2.0", "1.0", "0.0"])
                } else {
                    RecordedStressChart(points: summary?.stressSeries ?? [])
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 13).fill(LinearGradient.appCard))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }
}