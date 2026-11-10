import Foundation
import SwiftUI

/// Health detail — live HR, the capture series and the recoverable-metric grid.
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
                Text(lastHR.map { "\($0)" } ?? "—")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.appFG)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.band.liveHeartRate != nil ? "bpm · live" : "bpm · last capture")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.appMuted)
                    Text(zoneText)
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
            } else if series.count >= 2 {
                LineChart(
                    values: series,
                    color: .appAccent,
                    minY: (series.min() ?? 0) - 4,
                    maxY: (series.max() ?? 0) + 4,
                    height: 140,
                    yLabels: yLabels,
                    xLabels: xLabels
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
                 : series.isEmpty
                    ? "No HR series yet — wear the band and run a capture."
                    : "Per-minute means from the last capture, newest at the right.")
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
            MetricTile(
                label: "HRV · RMSSD",
                value: demo ? String(format: "%.0f", SampleData.hrvMS)
                             : ActivityFormat.whole(summary?.hrv.rmssdMS) ?? "—",
                unit: (demo || summary?.hrv.rmssdMS != nil) ? "ms" : nil,
                chip: demo ? "within 41–48 · sample" : baselineChip,
                chipGood: demo || store.hasRecoveryBaseline
            )
            MetricTile(
                label: "Resting HR",
                value: demo ? String(format: "%.0f", SampleData.rhr)
                             : ActivityFormat.whole(store.measuredRestingHR) ?? "—",
                unit: (demo || store.measuredRestingHR != nil) ? "bpm" : nil,
                chip: demo ? "within 56–60 · sample" : baselineChip,
                chipGood: demo || store.hasRecoveryBaseline
            )
            MetricTile(
                label: "HR range",
                value: demo ? "\(SampleData.hrRangeLow)–\(SampleData.hrRangeHigh)" : hrRangeText,
                unit: (demo || summary?.heartRateMin != nil) ? "bpm" : nil,
                chip: demo ? "today · sample" : captureChip,
                chipGood: false
            )
            MetricTile(
                label: "Steps",
                value: demo ? SampleData.steps.formatted() : stepsText,
                chip: demo ? "today · sample" : "band counter · this capture",
                chipGood: false
            )
            MetricTile(
                label: "VO₂ max",
                value: demo ? String(format: "%.1f", SampleData.vo2) : vo2Text,
                unit: (demo || store.vo2Estimate != nil) ? "ml/kg/min" : nil,
                chip: demo ? "Uth 2004 · sample" : store.vo2Basis ?? "needs a resting HR",
                chipGood: false
            )
            MetricTile(
                label: "Respiratory rate",
                value: demo ? String(format: "%.0f", SampleData.respRate)
                             : ActivityFormat.whole(summary?.respiration.breathsPerMinute) ?? "—",
                unit: (demo || summary?.respiration.available == true) ? "br/min" : nil,
                chip: demo ? "RSA estimate · sample" : respirationChip,
                chipGood: false
            )
            MetricTile(
                label: "SpO₂ candidate",
                value: demo ? "\(SampleData.spo2Candidate)%"
                             : summary?.spo2.pct.map { String(format: "%.0f%%", $0) } ?? "—",
                unit: nil,
                chip: demo ? "unvalidated · sample" : spo2Chip,
                chipGood: false
            )
            MetricTile(
                label: "Skin temperature",
                value: demo ? "33.4" : ActivityFormat.whole(summary?.skinTempMean) ?? "—",
                unit: (demo || summary?.skinTempMean != nil) ? "°C" : nil,
                chip: demo ? "absolute · sample" : skinChip,
                chipGood: false
            )
        }
    }

    // MARK: Live values

    private var summary: CaptureSummary? { store.band.summary }

    private var lastHR: Int? { store.band.liveHeartRate ?? summary?.lastHeartRate }

    private var series: [Double] { summary?.heartRateSeries ?? [] }

    private var baselineChip: String {
        store.hasRecoveryBaseline
            ? "vs personal norm"
            : "baseline \(store.recordedDayCount)/7 days"
    }

    private var captureChip: String {
        guard let summary, summary.sampleCount > 0 else { return "needs a capture" }
        return "last capture · \(summary.sampleCount) s"
    }

    private var hrRangeText: String {
        guard let summary, let low = summary.heartRateMin, let high = summary.heartRateMax else {
            return "—"
        }
        return "\(low)–\(high)"
    }

    private var stepsText: String {
        guard let steps = summary?.steps else { return "—" }
        return steps.formatted()
    }

    private var vo2Text: String {
        store.vo2Estimate.map { String(format: "%.1f", $0) } ?? "—"
    }

    private var zoneText: String {
        guard let hr = lastHR, let zones = store.liveZones else {
            return "zone needs resting + max HR"
        }
        if let zone = zones.first(where: {
            Double(hr) >= $0.lowerBPM && Double(hr) < $0.upperBPM
        }) {
            return zone.name
        }
        return "below Z1"
    }

    private var yLabels: [String] {
        guard let low = series.min(), let high = series.max() else { return [] }
        return [String(format: "%.0f", high), String(format: "%.0f", (high + low) / 2), String(format: "%.0f", low)]
    }

    private var xLabels: [String] {
        guard let summary, let first = summary.firstUnix, let last = summary.lastUnix else {
            return []
        }
        return [Self.clock(first), Self.clock(last)]
    }

    private var respirationChip: String {
        guard let respiration = summary?.respiration else { return "needs a still R-R window" }
        if respiration.available { return "RSA · \(respiration.windows) windows" }
        return respiration.reason ?? "needs a still R-R window"
    }

    private var spo2Chip: String {
        guard let spo2 = summary?.spo2 else { return "sleep capture only" }
        if spo2.pct != nil { return "unvalidated · \(spo2.readings) readings" }
        return spo2.reason ?? "no in-band candidate"
    }

    private var skinChip: String {
        guard let summary, let low = summary.skinTempMin, let high = summary.skinTempMax else {
            return "needs a capture"
        }
        return String(format: "absolute · %.1f–%.1f", low, high)
    }

    private static func clock(_ unix: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
    }
}