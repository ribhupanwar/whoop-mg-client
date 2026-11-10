import SwiftUI

/// Health tab landing — an overview hub, matching the approved layout.
/// The vitals detail (HealthView) is a drill-in opened only from a Health
/// Monitor card (here and on Home), never the tab itself.
/// Only metrics this client actually measures are shown; blood pressure,
/// respiratory rate and validated SpO₂ are explicitly absent, never guessed.
struct HealthHubView: View {
    @EnvironmentObject private var store: AppStore

    private var demo: Bool { store.isPreview }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                baselinePanel
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
                                    : "0/\(SampleData.baselineDaysTarget)")
            MiniProgress(fraction: demo
                         ? Double(SampleData.baselineDaysDone) / Double(SampleData.baselineDaysTarget)
                         : nil)
            Hint(demo
                 ? "Sample: \(SampleData.baselineDaysTarget - SampleData.baselineDaysDone) more days to unlock your personal baseline and recovery score."
                 : "Waiting for your first capture. Recovery and range chips unlock after 7 recorded days.")
        }
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
                    monitorCheck("HRV")
                    monitorCheck("RHR")
                    monitorCheck("HR")
                    monitorCheck("STEPS")
                }
                Text(demo ? "✓ 4/4 metrics within range · sample"
                          : "needs a capture — tap to see what is measured")
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

    private func monitorCheck(_ label: String) -> some View {
        VStack(spacing: 5) {
            Text(demo ? "✓" : "—")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(demo ? Color.appGood : Color.appMuted)
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
                        Text("TODAY'S HIGH STRESS")
                            .font(.system(size: 9.5)).tracking(0.6)
                            .foregroundStyle(Color.appMuted)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(demo ? SampleData.highStressToday : "—")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(Color.appFG)
                            Text("hrs").font(.system(size: 11)).foregroundStyle(Color.appMuted)
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
                    Text("Unlocks after a 7-day awake baseline.")
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

    // MARK: Honest limitations

    private var notMeasuredPanel: some View {
        Panel {
            CardHead(title: "Not measured by this client")
            Text("Blood pressure, respiratory rate and validated SpO₂ are not produced here — the strap's raw candidates are unvalidated and this client never guesses medical-looking numbers. Skin temperature is shown only as an absolute reading on the detail screen, never as a diagnosis.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.appMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}