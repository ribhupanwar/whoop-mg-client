import Foundation
import SwiftUI

/// The My Dashboard metric rows, shared verbatim by Home and the Dashboard tab
/// so the ordering can never drift: HRV, RHR, Steps, HR zones 1–3 weekly,
/// HR zones 4–5 weekly, VO₂ max, Calories, Stress Monitor.
/// No respiratory rate or SpO₂ here: both are Health-detail estimates, and
/// SpO₂ is only an unvalidated band candidate.
struct DashboardRows: View {
    @EnvironmentObject private var store: AppStore
    @State private var showVO2Detail = false

    private var demo: Bool { store.isPreview }

    var body: some View {
        VStack(spacing: 0) {
            MetricRow(
                icon: "waveform.path.ecg",
                title: "Heart rate variability",
                value: demo ? String(format: "%.0f", SampleData.hrvMS) : hrvText,
                unit: (demo || store.lastCapture?.hrv.rmssdMS != nil) ? "ms" : nil,
                detail: demo ? "▲ \(SampleData.hrvCompare) · sample" : hrvDetail,
                detailColor: demo ? .appGood : .appMuted
            )
            MetricRow(
                icon: "heart.fill",
                title: "Resting heart rate",
                value: demo ? String(format: "%.0f", SampleData.rhr) : rhrText,
                detail: demo ? "▲ \(SampleData.rhrCompare) · sample" : rhrDetail,
                detailColor: demo ? .appWarn : .appMuted
            )
            MetricRow(
                icon: "figure.walk",
                title: "Steps",
                value: demo ? SampleData.steps.formatted() : stepsText,
                detail: demo ? "▼ \(SampleData.stepsCompare.formatted()) · sample" : stepsDetail,
                detailColor: demo ? .appWarn : .appMuted
            )
            MetricRow(
                icon: "clock",
                title: "HR zones 1–3 · weekly",
                value: demo ? SampleData.zones13 : zoneText(high: false),
                detail: demo ? "▲ \(SampleData.zones13Compare) · sample" : zoneDetail,
                detailColor: demo ? .appGood : .appMuted
            )
            MetricRow(
                icon: "bolt.fill",
                title: "HR zones 4–5 · weekly",
                value: demo ? SampleData.zones45 : zoneText(high: true),
                detail: demo ? "▼ \(SampleData.zones45Compare) · sample" : zoneDetail,
                detailColor: demo ? .appWarn : .appMuted
            )
            vo2Block
            MetricRow(
                icon: "flame.fill",
                title: "Calories",
                value: demo ? SampleData.calories.formatted() : "—",
                detail: demo
                    ? "▼ \(SampleData.caloriesCompare.formatted()) · sample"
                    : "estimate via Keytel 2005 — needs weight + age",
                detailColor: demo ? .appWarn : .appMuted
            )
            stressRow
            Hint("The small number under a metric is your comparison value and stays absent until history exists. VO₂ max and calories are published estimates, never strap measurements.")
        }
    }

    // MARK: Live values

    private var summary: CaptureSummary? { store.lastCapture }

    private var hrvText: String { ActivityFormat.whole(summary?.hrv.rmssdMS) ?? "—" }

    private var hrvDetail: String {
        guard let summary, summary.hrv.rmssdMS != nil else { return "needs a capture" }
        if let baseline = store.band.baseline {
            let norm = Int(exp(baseline.lnRMSSDMean).rounded())
            return "norm \(norm) ms · \(baseline.days) days"
        }
        return "resting window \(summary.hrvWindowSeconds) s"
    }

    private var rhrText: String { ActivityFormat.whole(store.measuredRestingHR) ?? "—" }

    private var rhrDetail: String {
        guard store.measuredRestingHR != nil else { return "needs a capture" }
        if let baseline = store.band.baseline {
            return String(format: "norm %.0f · %d days", baseline.rhrMean, baseline.days)
        }
        return "resting window"
    }

    private var stepsText: String {
        guard let steps = summary?.steps else { return "—" }
        return steps.formatted()
    }

    private var stepsDetail: String {
        summary?.steps != nil ? "band step counter · last capture" : "needs a capture"
    }

    private func zoneText(high: Bool) -> String {
        guard let minutes = store.weeklyZoneMinutes(high: high) else { return "—" }
        return ActivityFormat.clock(minutes: minutes)
    }

    private var zoneDetail: String {
        let hasZones = !store.liveActivities.isEmpty
            && store.liveActivities.contains { !$0.zoneSeconds.isEmpty }
        return hasZones ? "last 7 days · measured sessions" : "run a live session"
    }

    private var vo2Text: String {
        store.vo2Estimate.map { String(format: "%.1f", $0) } ?? "—"
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
                    Image(systemName: "drop.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.appMuted)
                        .frame(width: 22)
                    Text("VO₂ MAX")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.7)
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Text(demo ? "—" : vo2Text)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text("›")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.appMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 13).fill(Color.appSurface))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.appLine, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Text("estimate via Uth 2004 (15.3 × HRmax/HRrest) — needs measured max HR")
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.top, 4)

            if showVO2Detail {
                Text("A population formula with wide error — not a lab test, and never a strap reading. Enter a max HR you have actually measured in a hard session.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: Stress monitor row

    private var stressRow: some View {
        NavigationLink(value: Route.stress) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("STRESS MONITOR")
                        .font(.system(size: 10.5, weight: .medium))
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
                LineChart(
                    values: demo ? SampleData.stressMiniSeries : [],
                    color: .appAccent,
                    minY: 0,
                    maxY: 3,
                    height: 46,
                    yLabels: ["3.0", "0.0"]
                )
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 13).fill(Color.appSurface))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.appLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }
}