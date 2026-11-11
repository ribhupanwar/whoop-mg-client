import Foundation
import SwiftUI

/// Health detail — live HR, the capture series and the recoverable-metric grid.
/// Respiratory rate is an RSA estimate from R-R timing (v18 carries no
/// respiration ADC) and SpO₂ is only the band's unvalidated candidate byte,
/// never a clinical percentage.
struct HealthView: View {
    @EnvironmentObject private var store: AppStore

    private var demo: Bool { store.isPreview }
    @State private var clock = Date()

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                hrPanel
                if !demo { rrDiagnosticPanel }
                metricGrid
                Hint("Range chips compare today against your normal, so they cannot appear before a 7-day baseline exists. Respiratory rate is an RSA estimate from R-R; SpO₂ is the band's unvalidated candidate, not a clinical reading.")
            }
        }
        .navigationTitle("Health monitor")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Force freshness evaluation even when no new BLE packet arrives.
            while !Task.isCancelled {
                clock = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var hrPanel: some View {
        Panel {
            SectionTitle("Heart rate")
            HStack(alignment: .bottom, spacing: 10) {
                Text(lastHR.map { "\($0)" } ?? "—")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.appFG)
                VStack(alignment: .leading, spacing: 2) {
                    Text(freshLiveHR != nil ? "bpm · live" : "bpm · waiting for live")
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
            if !demo {
                Text(liveHRDiagnostic)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
                    .padding(.bottom, 8)
            }

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
                    detail: "Waiting for live heart-rate readings from the band."
                )
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.appRaised))
            }

            Hint(demo
                 ? "Sample series — not measured data."
                 : series.isEmpty
                    ? "No HR series yet — connect the band to stream live readings."
                    : "Heart-rate graph — live while connected, otherwise last capture.")
        }
    }

    private var rrDiagnosticPanel: some View {
        Panel {
            SectionTitle("R–R signal diagnostics")
            if let capture = summary {
                Text("R–R source packets · Type-40: \(store.band.type40RRPackets) · BLE 2A37: \(store.band.standardRRPackets) · history: \(store.band.historyRRRecords)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appMuted)
                Text("History R–R declared: \(store.band.historyRRDeclared) · accepted: \(store.band.historyRRAccepted) · rejected: \(store.band.historyRRRejected)\n                History frames undecodable: \(store.band.historyUndecodableFrames) · versions: \(store.band.historyVersionCounts.sorted { $0.key < $1.key }.map { "v\($0.key):\($0.value)" }.joined(separator: ", "))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appMuted)
                Text("Live R–R beats buffered: \(store.band.liveRRIntervalsMS.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appMuted)
                Text("Historical samples: \(capture.sampleCount) · HRV quiet window: \(capture.hrvWindowSeconds)s")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appFG)
                Text("Clean R–R beats: \(capture.hrv.nnBeats) / \(capture.hrv.beats) · respiratory beats: \(capture.respiration.beats)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appMuted)
                if capture.sampleCount < 60 {
                    Hint("Only \(capture.sampleCount) historical records captured. The HRV algorithm requires at least 60 consecutive quiet seconds with valid motion data; 0/0 here does not mean the band sent zero R–R beats. Check source counters above and complete the overnight history sync.")
                } else if capture.hrv.nnBeats == 0 {
                    Hint("No decoded R–R beats in the qualifying quiet window. Check historical offload, v18 R–R offset and signal quality; live BPM alone does not provide beat intervals.")
                } else if capture.hrvWindowSeconds < 300 {
                    Hint("R–R data exists but a continuous 5-minute quiet window is not yet available for the overnight metric.")
                }
            } else {
                Hint("Read stored history to inspect R–R coverage.")
            }
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
            MetricTile(
                label: "HRV · RMSSD",
                value: demo ? String(format: "%.0f", SampleData.hrvMS)
                             : ActivityFormat.whole(latestNightHRV) ?? "—",
                unit: (demo || latestNightHRV != nil) ? "ms" : nil,
                chip: demo ? "↑ favourable · sample" : hrvTrendChip,
                chipGood: demo || hrvFavourable
            )
            MetricTile(
                label: "Resting HR",
                value: demo ? String(format: "%.0f", SampleData.rhr)
                             : ActivityFormat.whole(store.measuredRestingHR) ?? "—",
                unit: (demo || store.measuredRestingHR != nil) ? "bpm" : nil,
                chip: demo ? "↓ favourable · sample" : rhrTrendChip,
                chipGood: demo || rhrFavourable
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
                chip: demo ? "today · sample" : "today · recorded minimum",
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
                label: "Band skin temperature",
                value: demo ? "33.4" : ActivityFormat.whole(summary?.skinTempMean) ?? "—",
                unit: (demo || summary?.skinTempMean != nil) ? "°C" : nil,
                chip: demo ? "absolute · sample" : skinChip,
                chipGood: false
            )
        }
    }

    // MARK: Live values

    private var summary: CaptureSummary? { store.band.summary }

    // Use the same validated overnight HRV source as the Home dashboard.
    // A daytime capture must not overwrite the night's recovery metric.
    private var latestNightHRV: Double? {
        guard let day = store.band.days
            .filter({ $0.sleepHours >= 3 && $0.hrvWindowSeconds >= 300 && $0.lnRMSSD != nil })
            .sorted(by: { $0.dateKey > $1.dateKey })
            .first,
              let ln = day.lnRMSSD else { return nil }
        let rmssd = exp(ln)
        return rmssd.isFinite && (5...300).contains(rmssd) ? rmssd : nil
    }


    private var freshLiveHR: Int? {
        guard store.band.isConnected,
              let last = store.band.lastLiveHRAt,
              clock.timeIntervalSince(last) <= 8 else { return nil }
        return store.band.liveHeartRate
    }

    private var lastHR: Int? { freshLiveHR }

    private var liveHRDiagnostic: String {
        guard store.band.isConnected else { return "Strap disconnected · connect to stream live HR" }
        let count = store.band.liveHRNotificationCount
        guard let last = store.band.lastLiveHRAt else {
            return "HR packets: 0 · \(store.band.hrConnectionDiagnostic)"
        }
        let seconds = max(0, Int(clock.timeIntervalSince(last)))
        return "HR packets: \(count) · last packet \(seconds)s ago"
    }

    private var usingLiveSeries: Bool {
        guard let last = store.band.recentLiveHR.last else { return false }
        return store.band.isConnected && clock.timeIntervalSince1970 - Double(last.unix) <= 15
            && store.band.recentLiveHR.count >= 2
    }

    private var series: [Double] {
        if usingLiveSeries { return store.band.recentLiveHR.map { Double($0.heartRate) } }
        return summary?.heartRateSeries ?? []
    }

    private var baselineChip: String {
        store.hasRecoveryBaseline
            ? "vs personal norm"
            : "baseline \(store.recordedDayCount)/7 days"
    }

    // A favourable trend means better than the person's own baseline, not
    // that the reading is clinically normal. No arrows without evidence.
    private var hrvFavourable: Bool {
        guard store.hasRecoveryBaseline,
              let baseline = store.band.baseline,
              let current = latestNightHRV.map({ log($0) }),
              current.isFinite else { return false }
        return current > baseline.lnRMSSDMean
    }

    private var rhrFavourable: Bool {
        guard store.hasRecoveryBaseline,
              let baseline = store.band.baseline,
              let current = store.measuredRestingHR,
              current.isFinite else { return false }
        return current < baseline.rhrMean
    }

    private var hrvTrendChip: String {
        guard store.hasRecoveryBaseline,
              let baseline = store.band.baseline,
              let current = latestNightHRV.map({ log($0) }),
              current.isFinite else { return baselineChip }
        let difference = (exp(current) / exp(baseline.lnRMSSDMean) - 1) * 100
        guard difference.isFinite else { return baselineChip }
        if abs(difference) < 1 { return "→ near personal norm" }
        return String(format: "%@ %.0f%% vs baseline%@",
                      difference > 0 ? "↑" : "↓", abs(difference),
                      difference > 0 ? " · favourable" : "")
    }

    private var rhrTrendChip: String {
        guard store.hasRecoveryBaseline,
              let baseline = store.band.baseline,
              let current = store.measuredRestingHR,
              current.isFinite else { return baselineChip }
        let difference = current - baseline.rhrMean
        if abs(difference) < 0.5 { return "→ near personal norm" }
        return String(format: "%@ %.0f bpm vs baseline%@",
                      difference < 0 ? "↓" : "↑", abs(difference),
                      difference < 0 ? " · favourable" : "")
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
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        guard let steps = store.band.days.first(where: { $0.dateKey == today })?.steps else {
            return "—"
        }
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
        if usingLiveSeries, let first = store.band.recentLiveHR.first,
           let last = store.band.recentLiveHR.last {
            return [Self.clock(first.unix), Self.clock(last.unix)]
        }
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