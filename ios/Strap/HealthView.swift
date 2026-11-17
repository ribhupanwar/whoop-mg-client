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
                connectionBanner
                hrPanel
                fiveMetricGrid
                if !demo { rrDiagnosticPanel }
                Hint("Personal ranges use at least seven qualifying prior sleep nights. Respiratory rate is an RSA estimate; SpO₂ and skin temperature remain unvalidated sensor candidates. Recorded personal ranges are not clinical limits.")
            }
        }
        .navigationTitle("HEALTH MONITOR")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // A one-second timer invalidated the entire health screen, including charts and\n            // the diagnostics panel. BLE updates still publish live HR independently;\n            // check staleness at a lower cadence to reduce main-thread rendering.
            while !Task.isCancelled {
                clock = Date()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var connectionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "applewatch")
                .font(.system(size: 20))
                .foregroundStyle(Color.appMuted)
            Text(store.band.isConnected ? "CONNECTED" : "DISCONNECTED")
                .font(StrapTypography.body(12, weight: .bold))
                .tracking(1.2)
            Spacer()
            Image(systemName: store.band.isConnected ? "link" : "xmark")
                .foregroundStyle(store.band.isConnected ? Color.appSleep : Color.appMuted)
                .font(.system(size: 19, weight: .bold))
        }
        .padding(19)
        .background(RoundedRectangle(cornerRadius: 15).fill(Color.black.opacity(0.72)))
        .padding(.bottom, 18)
    }

    private var fiveMetricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            healthMetric("RESPIRATORY RATE", symbol: "lungs", value: demo ? "18.4" : monitor[.respiration].value.map { String(format: "%.1f", $0) } ?? "—",
                         unit: "rpm", reading: monitor[.respiration])
            healthMetric("BLOOD OXYGEN (SpO₂)", symbol: "drop", value: demo ? "95" : ActivityFormat.whole(monitor[.oxygen].value) ?? "—",
                         unit: "%", reading: monitor[.oxygen])
            healthMetric("RHR", symbol: "heart", value: demo ? "62" : ActivityFormat.whole(monitor[.rhr].value) ?? "—",
                         unit: "bpm", reading: monitor[.rhr])
            healthMetric("HRV", symbol: "waveform.path.ecg", value: demo ? "58" : ActivityFormat.whole(monitor[.hrv].value) ?? "—",
                         unit: "ms", reading: monitor[.hrv])
            healthMetric("SKIN TEMP (FROM BASELINE)", symbol: "thermometer.medium",
                         value: demo ? "+0.2" : monitor[.temperature].value.map { String(format: "%+.1f", $0) } ?? "—",
                         unit: "°C", reading: monitor[.temperature])
        }
        .padding(.bottom, 18)
    }

    private func healthMetric(_ title: String, symbol: String, value: String,
                              unit: String, reading: HealthReading) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(Color.appMuted)
                    .frame(width: 20)
                Text(title)
                    .font(StrapTypography.body(10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.appMuted)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(StrapTypography.metric(31, weight: .bold))
                    .foregroundStyle(Color.appFG)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text(value == "—" ? "" : unit)
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appFG)
            }
            HStack(spacing: 4) {
                Image(systemName: reading.verifiedWithinRange ? "checkmark.circle.fill" : "circle")
                Text(demo ? "SAMPLE" : reading.statusText)
            }
                .font(StrapTypography.body(10, weight: .semibold))
                .foregroundStyle(reading.verifiedWithinRange ? Color.appGood :
                    (reading.status == .outsideRange || reading.status == .candidate ? Color.appWarn : Color.appMuted))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(demo ? "Design preview" : reading.referenceText)
                .font(StrapTypography.body(10)).foregroundStyle(Color.appMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 144, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 15).fill(LinearGradient.appCard))
    }

    // WHOOP-inspired full-bleed presentation, retaining STRAP's measured HR.
    private var hrPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HEART RATE")
                .font(StrapTypography.body(17, weight: .bold))
                .tracking(1.6)
                .padding(.bottom, 16)
            Image(systemName: "heart.fill")
                .font(.system(size: 27))
                .foregroundStyle(Color(hex: 0x159EF0))
                .padding(.bottom, 12)
            Text(lastHR.map(String.init) ?? "—")
                .font(StrapTypography.metric(58, weight: .bold))
                .monospacedDigit()
                .accessibilityIdentifier("health.live.bpm")
                .foregroundStyle(Color.appFG)
            Text("BPM")
                .font(StrapTypography.body(17, weight: .bold))
                .foregroundStyle(Color.appMuted)
                .padding(.top, 1)
            Text(zoneText)
                .font(StrapTypography.body(17, weight: .semibold))
                .foregroundStyle(Color.appMuted)
                .padding(.top, 18)
            // Keep the live monitor distinct from the historical HR trace.
            // A connected band with stale packets must never look live.
            liveHeartRateChart
                .padding(.top, -195)
                .allowsHitTesting(false)
            if !demo {
                Text(liveHRDiagnostic)
                    .font(StrapTypography.body(10))
                    .foregroundStyle(Color.appMuted)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBG)
    }

    private var liveHeartRateChart: some View {
        // This is an instantaneous indicator, not a historical time-series.
        // Use a stable physiological display scale so the line moves vertically
        // when the latest fresh HR changes; never substitute archived samples.
        let current = lastHR
        return GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let bpm = Double(current ?? 82)
            let fraction = LiveHeartRateState.indicatorFraction(bpm: Int(bpm))
            let y = 6 + max(0, height - 12) * CGFloat(1.0 - fraction)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let spacing: CGFloat = 24
                    var grid = Path()
                    for x in stride(from: CGFloat(0), through: size.width, by: spacing) {
                        grid.move(to: CGPoint(x: x, y: 0))
                        grid.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for row in stride(from: CGFloat(0), through: size.height, by: spacing) {
                        grid.move(to: CGPoint(x: 0, y: row))
                        grid.addLine(to: CGPoint(x: size.width, y: row))
                    }
                    context.stroke(grid, with: .color(Color.white.opacity(0.055)), lineWidth: 0.65)
                }
                if current != nil {
                    Path { path in
                        path.move(to: CGPoint(x: width * 0.32, y: y))
                        path.addLine(to: CGPoint(x: width - 7, y: y))
                    }
                    .stroke(Color(hex: 0x22AFFF), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .shadow(color: Color(hex: 0x18A6F5).opacity(0.7), radius: 6)
                    Path { path in
                        path.move(to: CGPoint(x: width - 7, y: 0))
                        path.addLine(to: CGPoint(x: width - 7, y: height))
                    }
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    Circle().fill(.white).frame(width: 12, height: 12)
                        .shadow(color: .white.opacity(0.7), radius: 6)
                        .position(x: width - 7, y: y)
                }
            }
        }
        .frame(height: 195)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("health.live.indicator")
        .accessibilityValue(current.map { String(format: "%.3f", LiveHeartRateState.indicatorFraction(bpm: $0)) } ?? "unavailable")
        .accessibilityLabel(current.map { "Current heart rate, \($0) beats per minute" } ?? "Live heart rate unavailable")
    }

    private var rrDiagnosticPanel: some View {
        Panel {
            SectionTitle("R–R signal diagnostics")
            if let capture = summary {
                Text("R–R source packets · Type-40: \(store.band.type40RRPackets) · BLE 2A37: \(store.band.standardRRPackets) · history: \(store.band.historyRRRecords)")
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appMuted)
                Text("History R–R declared: \(store.band.historyRRDeclared) · accepted: \(store.band.historyRRAccepted) · rejected: \(store.band.historyRRRejected)\n                History frames undecodable: \(store.band.historyUndecodableFrames) · versions: \(store.band.historyVersionCounts.sorted { $0.key < $1.key }.map { "v\($0.key):\($0.value)" }.joined(separator: ", "))")
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appMuted)
                Text(store.band.liveRRQualityDiagnostic)
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appMuted)
                Text("Live R–R beats buffered: \(store.band.liveRRIntervalsMS.count)")
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appMuted)
                Text("Historical samples: \(capture.sampleCount) · HRV quiet window: \(capture.hrvWindowSeconds)s")
                Text(store.band.historicalRestQualityReason)
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appFG)
                Text("Clean R–R beats: \(capture.hrv.nnBeats) / \(capture.hrv.beats) · respiratory beats: \(capture.respiration.beats)")
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appMuted)
                if capture.sampleCount < 60 {
                    Hint("Only \(capture.sampleCount) historical records captured. The HRV algorithm requires at least 60 consecutive quiet seconds with valid motion data; 0/0 here does not mean the band sent zero R–R beats. Check source counters above and complete the overnight history sync.")
                } else if capture.hrv.nnBeats == 0 {
                    Hint("No decoded R–R beats in the qualifying quiet window. Check historical offload, v18 R–R offset and signal quality; live BPM alone does not provide beat intervals.")
                } else if capture.hrvWindowSeconds < 300 {
                    Hint("R–R data exists but a continuous 5-minute quiet window is not yet available for the overnight metric.")
                }
            } else {
                Text(store.band.liveRRQualityDiagnostic)
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appMuted)
                Text(store.band.historicalRestQualityReason)
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appMuted)
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
                             : ActivityFormat.whole(displayedNightRHR) ?? "—",
                unit: (demo || displayedNightRHR != nil) ? "bpm" : nil,
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
    private var monitor: HealthMonitorSnapshot { store.healthMonitor }

    // Use the same validated overnight HRV source as the Home dashboard.
    // A daytime capture must not overwrite the night's recovery metric.
    private var displayedNight: DayMetrics? {
        guard !store.band.isAnalyzingHistory, let session = store.band.latestSleepSession else { return nil }
        let key = JournalStore.dayKey(for: Date(timeIntervalSince1970: TimeInterval(session.endUnix - 1)))
        return store.band.days.first { $0.dateKey == key && $0.state == "sleep"
            && $0.sleepStartUnix == session.startUnix && $0.sleepEndUnix == session.endUnix - 1 }
    }

    private var latestNightHRV: Double? {
        guard let night = displayedNight, night.hrvWindowSeconds >= 300,
              let lnRMSSD = night.lnRMSSD, lnRMSSD.isFinite else { return nil }
        return exp(lnRMSSD)
    }

    private var displayedNightRHR: Double? { displayedNight?.restingHR }


    private var freshLiveHR: Int? {
        LiveHeartRateState.fresh(store.band.liveHeartRate, receivedAt: store.band.lastLiveHRAt,
                                 connected: store.band.isConnected, now: max(clock, Date()))
    }

    private var lastHR: Int? {
        guard demo else { return freshLiveHR }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--preview-hr-stale") { return nil }
        if let argument = args.first(where: { $0.hasPrefix("--preview-live-bpm=") }),
           let bpm = Int(argument.dropFirst("--preview-live-bpm=".count)) {
            return (25...230).contains(bpm) ? bpm : nil
        }
        #endif
        return 82
    }

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
              let current = displayedNightRHR,
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
              let current = displayedNightRHR,
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
        guard let hr = lastHR else { return "Waiting for live HR" }
        guard let zones = store.liveZones else {
            return "zone needs resting + max HR"
        }
        guard let zone = Karvonen.zoneIndex(heartRate: Double(hr), zones: zones) else { return "Above configured max HR" }
        return "ZONE \(zone)"
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
