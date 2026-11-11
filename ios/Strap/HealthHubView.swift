import Foundation
import SwiftUI

/// Health tab landing — an overview hub, matching the approved layout.
/// The vitals detail (HealthView) is a drill-in opened only from a Health
/// Monitor card (here and on Home), never the tab itself.
/// Only metrics this client actually measures are shown; blood pressure is
/// absent, respiratory rate is an RSA estimate from R-R, and SpO₂ is the
/// band's labelled candidate rather than a clinical percentage.
struct HealthHubView: View {
    @EnvironmentObject private var store: AppStore

    private var demo: Bool { store.isPreview }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                baselinePanel
                fitnessAgePanel
                healthMonitorCard
                stressMonitorCard
                notMeasuredPanel
                Hint("Health monitor and stress monitor are local estimates, not medical devices, and cannot diagnose or manage conditions. Consult your doctor for health concerns.")
            }
        }
        .navigationTitle("Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Baseline progress

    private var baselinePanel: some View {
        Panel {
            CardHead(title: "Personal baseline",
                     trailing: demo ? "\(SampleData.baselineDaysDone)/\(SampleData.baselineDaysTarget)"
                                    : "\(min(store.recordedDayCount, SampleData.baselineDaysTarget))/\(SampleData.baselineDaysTarget)")
            MiniProgress(fraction: demo
                         ? Double(SampleData.baselineDaysDone) / Double(SampleData.baselineDaysTarget)
                         : min(Double(store.recordedDayCount) / Double(SampleData.baselineDaysTarget), 1.0))
            Hint(demo
                 ? "Sample: \(SampleData.baselineDaysTarget - SampleData.baselineDaysDone) more days to unlock your personal baseline and recovery score."
                 : store.hasRecoveryBaseline
                    ? "Baseline ready — recovery and stress compare today against your own \(store.recordedDayCount) recorded days."
                    : "\(max(0, SampleData.baselineDaysTarget - store.recordedDayCount)) more recorded days unlock recovery and stress. Each history capture adds its days.")
        }
    }

    // MARK: Independent fitness-age comparison

    private var fitnessSnapshot: FitnessAgeSnapshot? {
        FitnessAgeModel.snapshot(
            age: store.settings.age,
            sex: store.settings.sex,
            ageConfirmed: store.settings.ageConfirmed,
            days: store.band.days,
            detected: store.detectedBandActivities,
            live: store.liveActivities
        )
    }

    private var fitnessAgePanel: some View {
        Panel {
            SectionTitle("Fitness age · experimental")
            if let estimate = fitnessSnapshot {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(String(format: "%.0f", estimate.years))
                        .font(.system(size: 31, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Text("years")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appMuted)
                    Spacer()
                    Text("Actual age: \(estimate.chronologicalYears)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.appMuted)
                }
                Hint("7-day median resting HR: \(String(format: "%.0f", estimate.restingHeartRate)) bpm · \(estimate.restingNights) nights")
                Hint("Activity: \(estimate.exerciseDays) recorded days · estimated HUNT-like index \(String(format: "%.1f", estimate.physicalActivityIndex))")
                Hint(estimate.confidenceNote)
            } else {
                Text("—")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.appMuted)
                Hint("To unlock: confirm your age and sex in Settings; capture at least 4 resting-HR nights, 4 days with measured steps, and a recorded workout within 7 days.")
            }
            Hint("This is an independent fitness comparison inspired by the published Nes/HUNT model, not Aura's private model, WHOOP Age, biological age or a medical measurement. Activity-index inputs are estimates.")
        }
        .padding(.bottom, 11)
    }

    // MARK: Health Monitor card (drill-in)

    private var healthMonitorCard: some View {
        NavigationLink(value: Route.health) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("HEALTH MONITOR")
                        .font(.system(size: 10.5, weight: .medium)).tracking(0.8)
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Text("›").font(.system(size: 15)).foregroundStyle(Color.appMuted)
                }
                HStack(spacing: 6) {
                    monitorCheck("HRV", present: demo || store.lastCapture?.hrv.rmssdMS != nil)
                    monitorCheck("RHR", present: demo || store.measuredRestingHR != nil)
                    monitorCheck("HR", present: demo || store.band.liveHeartRate != nil || store.lastCapture?.lastHeartRate != nil)
                    monitorCheck("STEPS", present: demo || store.lastCapture?.steps != nil)
                }
                Text(demo ? "✓ 4/4 metrics within range · sample"
                          : monitorSummary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(demo ? Color.appGood : Color.appMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.appRaised))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.appSurface))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.appLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 11)
    }

    private var monitorSummary: String {
        guard let summary = store.lastCapture else {
            return "needs a capture — tap to see what is measured"
        }
        let parts = [
            summary.hrv.rmssdMS.map { _ in "HRV" },
            store.measuredRestingHR.map { _ in "RHR" },
            summary.lastHeartRate.map { _ in "HR" },
            summary.steps.map { _ in "steps" }
        ].compactMap { $0 }
        return "\(parts.count)/4 metrics from the last capture (\(summary.sampleCount) s)"
    }

    private func monitorCheck(_ label: String, present: Bool) -> some View {
        VStack(spacing: 5) {
            Text(present ? "✓" : "—")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(present ? Color.appGood : Color.appMuted)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.appRaised))
            Text(label)
                .font(.system(size: 9.5, weight: .medium)).tracking(0.5)
                .foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Stress Monitor card (drill-in)

    private var stressMonitorCard: some View {
        NavigationLink(value: Route.stress) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("STRESS MONITOR")
                        .font(.system(size: 10.5, weight: .medium)).tracking(0.8)
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Text("›").font(.system(size: 15)).foregroundStyle(Color.appMuted)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TODAY'S STRESS INDEX")
                            .font(.system(size: 9.5)).tracking(0.6)
                            .foregroundStyle(Color.appMuted)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(demo ? SampleData.highStressToday : stressText)
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(Color.appFG)
                            Text(demo ? "hrs" : "SD")
                                .font(.system(size: 11)).foregroundStyle(Color.appMuted)
                        }
                    }
                    Spacer()
                    if demo {
                        LineChart(values: SampleData.stressMiniSeries, color: .appGood,
                                  minY: 0, maxY: 3, height: 60)
                            .frame(width: 150)
                    }
                }
                if !demo {
                    Text(stressDetail)
                        .font(.system(size: 11)).foregroundStyle(Color.appMuted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.appSurface))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.appLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 11)
    }

    private var stressText: String {
        guard let index = store.band.stress.index else { return "—" }
        return String(format: "%.1f", index)
    }

    private var stressDetail: String {
        if let reason = store.band.stress.reason { return reason }
        return "\(store.band.stress.band) — SD of lnRMSSD below your awake norm."
    }

    // MARK: Honest limitations

    private var notMeasuredPanel: some View {
        Panel {
            CardHead(title: "Not measured by this client")
            Text("Blood pressure is not produced here. Respiratory rate is an RSA estimate from R-R timing, not a chest-band measurement. SpO₂ is only the strap's unvalidated candidate byte and is never a clinical reading. Skin temperature is shown as an absolute reading on the detail screen only.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.appMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}