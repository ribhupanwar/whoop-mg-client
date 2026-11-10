import SwiftUI

/// Health detail — HR chart placeholder plus the recoverable-metric grid.
/// Respiratory rate is an RSA estimate from R-R timing (v18 carries no
/// respiration ADC) and SpO₂ is only the band's unvalidated candidate byte,
/// never a clinical percentage.
struct HealthView: View {
    @EnvironmentObject private var store: AppStore

    private var demo: Bool { store.isPreview }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                hrPanel
                metricGrid
                Hint("Range chips compare today against your normal, so they cannot appear before a 7-day baseline exists. Respiratory rate is an RSA estimate from R-R; SpO₂ is the band's unvalidated candidate, not a clinical reading.")
            }
        }
        .navigationTitle("Health monitor")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hrPanel: some View {
        Panel {
            SectionTitle("Heart rate")
            HStack(alignment: .bottom, spacing: 10) {
                Text(demo ? "\(SampleData.hrNow)" : "—")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.appFG)
                VStack(alignment: .leading, spacing: 2) {
                    Text("bpm · last reading")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.appMuted)
                    Text(demo ? "Zone 1" : "zone needs your max HR")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.appMuted)
                }
                .padding(.bottom, 4)
                Spacer()
            }
            .padding(.bottom, 6)

            if demo {
                LineChart(
                    values: SampleData.hrSeries,
                    color: .appAccent,
                    minY: 60,
                    maxY: 90,
                    height: 140,
                    yLabels: ["90", "75", "60"],
                    xLabels: ["09:13", "10:01"]
                )
            } else {
                EmptyState(
                    title: "needs a capture",
                    detail: "The heart-rate series appears here after the band streams HR into a capture."
                )
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.appRaised))
            }

            Hint(demo
                 ? "Sample series — not measured data."
                 : "No HR series yet — wear the band and run a capture.")
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
            MetricTile(
                label: "HRV · RMSSD",
                value: demo ? String(format: "%.0f", SampleData.hrvMS) : "—",
                unit: demo ? "ms" : nil,
                chip: demo ? "within 41–48 · sample" : "needs a capture",
                chipGood: demo
            )
            MetricTile(
                label: "Resting HR",
                value: demo ? String(format: "%.0f", SampleData.rhr) : "—",
                unit: demo ? "bpm" : nil,
                chip: demo ? "within 56–60 · sample" : "needs a capture",
                chipGood: demo
            )
            MetricTile(
                label: "HR range",
                value: demo ? "\(SampleData.hrRangeLow)–\(SampleData.hrRangeHigh)" : "—",
                unit: demo ? "bpm" : nil,
                chip: demo ? "today · sample" : "needs a capture",
                chipGood: false
            )
            MetricTile(
                label: "Steps",
                value: demo ? SampleData.steps.formatted() : "—",
                chip: demo ? "today · sample" : "needs a capture",
                chipGood: false
            )
            MetricTile(
                label: "Respiratory rate",
                value: demo ? String(format: "%.0f", SampleData.respRate) : "—",
                unit: demo ? "br/min" : nil,
                chip: demo ? "RSA estimate · sample" : "needs a still R-R window",
                chipGood: false
            )
            MetricTile(
                label: "SpO₂ candidate",
                value: demo ? "\(SampleData.spo2Candidate)%" : "—",
                unit: nil,
                chip: demo ? "unvalidated · sample" : "sleep capture only",
                chipGood: false
            )
        }
    }
}