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
    @State private var capturedChartPoints: [HeartRateChartPoint] = []

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
        .onAppear(perform: refreshCapturedChartPoints)
        .onChange(of: store.band.summary?.lastUnix) { _, _ in refreshCapturedChartPoints() }
        .onChange(of: store.band.lastHistoryRecordCount) { _, _ in refreshCapturedChartPoints() }
        .task {
            // A one-second timer invalidated the entire health screen, including charts and\n            // the diagnostics panel. BLE updates still publish live HR independently;\n            // check staleness at a lower cadence to reduce main-thread rendering.
            while !Task.isCancelled {
                clock = Date()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var hrPanel: some View {
        Panel {
            SectionTitle("Heart rate")
            HStack(alignment: .bottom, spacing: 10) {
                Text(displayedHR.map { "\($0)" } ?? "—")
                    .font(StrapTypography.metric(36, weight: .regular))
                    .foregroundStyle(Color.appFG)
                VStack(alignment: .leading, spacing: 2) {
                    Text(demo ? "bpm · sample"
                         : freshLiveHR != nil ? "bpm · live"
                         : displayedHR != nil ? "bpm · last reading"
                         : "bpm · waiting for live")
                        .font(StrapTypography.body(11))
                        .foregroundStyle(Color.appMuted)
                    Text(zoneText)
                        .font(StrapTypography.body(11))
                        .foregroundStyle(Color.appMuted)
                }
                .padding(.bottom, 4)
                Spacer()
            }
            .padding(.bottom, 6)

            if !chartPoints.isEmpty {
                HeartRateChart(
                    points: chartPoints,
                    source: demo ? "Sample" : usingLiveSeries ? "Live" : "Recorded"
                )
            } else {
                EmptyState(
                    title: displayedHR == nil ? "No heart-rate readings" : "Chart unavailable",
                    detail: displayedHR == nil
                        ? "Waiting for live heart-rate readings from the band."
                        : "A timestamped series is not available for this saved reading."
                )
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.appRaised))
            }

            Hint(chartHint)
        }
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

    // Use the same validated overnight HRV source as the Home dashboard.
    // A daytime capture must not overwrite the night's recovery metric.
    private var displayedNight: DayMetrics? {
        guard let session = store.band.latestSleepSession else { return nil }
        let key = JournalStore.dayKey(for: Date(timeIntervalSince1970: TimeInterval(session.endUnix - 1)))
        return store.band.days.first { $0.dateKey == key && $0.state == "sleep" }
    }

    private var latestNightHRV: Double? {
        guard let lnRMSSD = displayedNight?.lnRMSSD, lnRMSSD.isFinite else { return nil }
        return exp(lnRMSSD)
    }

    private var displayedNightRHR: Double? { displayedNight?.restingHR }


    private var freshLiveHR: Int? {
        guard store.band.isConnected,
              let last = store.band.lastLiveHRAt,
              isFreshLiveTimestamp(last),
              let sample = store.band.recentLiveHR.last,
              isFreshLiveTimestamp(Date(timeIntervalSince1970: TimeInterval(sample.unix))) else { return nil }
        return store.band.liveHeartRate
    }

    private func isFreshLiveTimestamp(_ timestamp: Date) -> Bool {
        let age = max(clock, Date()).timeIntervalSince(timestamp)
        return (0...8).contains(age)
    }

    private var lastHR: Int? { freshLiveHR }

    private var displayedHR: Int? {
        if demo { return SampleData.hrSeries.last.map { Int($0.rounded()) } }
        return freshLiveHR ?? capturedChartPoints.last?.bpm ?? summary?.lastHeartRate
    }

    private var chartPoints: [HeartRateChartPoint] {
        if demo {
            let values = SampleData.hrSeries
            let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600 + 13 * 60)
            let span: TimeInterval = 48 * 60
            return normalizedHeartRatePoints(values.enumerated().map { index, value in
                let fraction = Double(index) / Double(max(1, values.count - 1))
                return HeartRateChartPoint(
                    unix: Int(start.timeIntervalSince1970 + span * fraction),
                    bpm: Int(value.rounded())
                )
            })
        }

        if usingLiveSeries {
            return normalizedHeartRatePoints(store.band.recentLiveHR.map {
                HeartRateChartPoint(unix: $0.unix, bpm: $0.heartRate)
            })
        }

        return capturedChartPoints
    }

    private var usingLiveSeries: Bool {
        freshLiveHR != nil && !store.band.recentLiveHR.isEmpty
    }

    private func refreshCapturedChartPoints() {
        capturedChartPoints = normalizedHeartRatePoints(store.band.capturedHeartRateReadings.map {
            HeartRateChartPoint(unix: $0.unix, bpm: $0.bpm)
        })
    }

    private var chartHint: String {
        if demo { return "Sample series — not measured data." }
        guard let first = chartPoints.first, let last = chartPoints.last else {
            return displayedHR == nil
                ? "No recorded HR series yet — connect the band to stream live readings."
                : "A timestamped series is unavailable for this saved reading."
        }
        if usingLiveSeries {
            return "Live readings through \(Self.timestampLabel(last.unix)). Gaps indicate intervals without a received sample."
        }
        return "Recorded readings \(Self.timestampLabel(first.unix))–\(Self.timestampLabel(last.unix)). Gaps indicate missing recorded samples."
    }

    private static func timestampLabel(_ unix: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(unix))
            .formatted(date: .abbreviated, time: .shortened)
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
        guard let hr = lastHR else {
            return "zone needs live HR"
        }
        guard let zones = store.liveZones else {
            return "zone needs resting + max HR"
        }
        if let zone = zones.first(where: {
            Double(hr) >= $0.lowerBPM && Double(hr) < $0.upperBPM
        }) {
            return zone.name
        }
        return "below Z1"
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

}

private struct HeartRateChartPoint: Identifiable {
    let unix: Int
    let bpm: Int
    var id: Int { unix }
}

private func normalizedHeartRatePoints(_ points: [HeartRateChartPoint]) -> [HeartRateChartPoint] {
    let ordered = points.enumerated().sorted {
        if $0.element.unix == $1.element.unix {
            return $0.offset < $1.offset
        }
        return $0.element.unix < $1.element.unix
    }

    var result: [HeartRateChartPoint] = []
    for item in ordered {
        if result.last?.unix == item.element.unix {
            result[result.count - 1] = item.element
        } else {
            result.append(item.element)
        }
    }
    return result
}

private struct HeartRateChart: View {
    let points: [HeartRateChartPoint]
    let source: String

    private var sortedPoints: [HeartRateChartPoint] {
        normalizedHeartRatePoints(points)
    }

    // Both live capture and v18 history retain one reading per whole Unix second.
    // A 1.5-second limit keeps consecutive seconds together and splits a missing second.
    private static let sampleCadenceSeconds = 1.0
    private static let maxContinuousIntervalSeconds = sampleCadenceSeconds * 1.5

    private func segments(for points: [HeartRateChartPoint]) -> [[HeartRateChartPoint]] {
        var result: [[HeartRateChartPoint]] = []
        for point in points {
            guard let previous = result.last?.last else {
                result.append([point])
                continue
            }
            if Double(point.unix - previous.unix) > Self.maxContinuousIntervalSeconds {
                result.append([point])
            } else {
                result[result.count - 1].append(point)
            }
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let ordered = sortedPoints
            let contiguousSegments = segments(for: ordered)
            let leftInset: CGFloat = 30
            let topInset: CGFloat = 8
            let bottomInset: CGFloat = 27
            let plot = CGRect(
                x: leftInset,
                y: topInset,
                width: max(1, geometry.size.width - leftInset - 4),
                height: max(1, geometry.size.height - topInset - bottomInset)
            )
            let bounds = Self.bpmBounds(for: ordered)
            let firstUnix = ordered.first?.unix ?? 0
            let lastUnix = ordered.last?.unix ?? firstUnix
            let line = chartPath(
                segments: contiguousSegments, in: plot, bounds: bounds,
                firstUnix: firstUnix, lastUnix: lastUnix, closingAtBottom: false
            )
            let area = chartPath(
                segments: contiguousSegments, in: plot, bounds: bounds,
                firstUnix: firstUnix, lastUnix: lastUnix, closingAtBottom: true
            )
            let last = ordered.last

            ZStack(alignment: .topLeading) {
                area
                    .fill(LinearGradient(
                        colors: [Color.appAccent.opacity(0.24), Color.appAccent.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                ForEach(0..<3, id: \.self) { index in
                    let fraction = CGFloat(index) / 2
                    let y = plot.minY + plot.height * fraction
                    Path { path in
                        path.move(to: CGPoint(x: plot.minX, y: y))
                        path.addLine(to: CGPoint(x: plot.maxX, y: y))
                    }
                    .stroke(Color.appLine, lineWidth: 1)

                    Text(axisValue(at: index, bounds: bounds))
                        .font(StrapTypography.body(9))
                        .foregroundStyle(Color.appMuted)
                        .frame(width: leftInset - 5, alignment: .trailing)
                        .position(x: (leftInset - 5) / 2, y: y)
                }
                line
                    .stroke(Color.appAccent, style: StrokeStyle(
                        lineWidth: 1.7,
                        lineCap: .round,
                        lineJoin: .round
                    ))
                    .shadow(color: Color.appAccent.opacity(0.25), radius: 3)

                ForEach(Array(contiguousSegments.enumerated()), id: \.offset) { entry in
                    if entry.element.count == 1, let point = entry.element.first {
                        Circle()
                            .fill(Color.appAccent)
                            .frame(width: 4, height: 4)
                            .position(location(
                                for: point, in: plot, bounds: bounds,
                                firstUnix: firstUnix, lastUnix: lastUnix
                            ))
                    }
                }
                if let last {
                    Circle()
                        .fill(Color.appAccent)
                        .frame(width: 7, height: 7)
                        .position(location(
                            for: last, in: plot, bounds: bounds,
                            firstUnix: firstUnix, lastUnix: lastUnix
                        ))
                }

                HStack {
                    if let first = ordered.first, let last {
                        Text(Self.clock(first.unix))
                        Spacer()
                        if first.unix != last.unix {
                            Text(Self.clock(last.unix))
                        }
                    }
                }
                .font(StrapTypography.body(9))
                .foregroundStyle(Color.appMuted)
                .frame(width: plot.width)
                .position(x: plot.midX, y: plot.maxY + bottomInset / 2)
            }
        }
        .frame(height: 150)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        guard let first = sortedPoints.first, let last = sortedPoints.last,
              let low = sortedPoints.map(\.bpm).min(),
              let high = sortedPoints.map(\.bpm).max() else {
            return "Heart-rate chart has no readings"
        }
        return "\(source) heart rate from \(Self.timestampLabel(first.unix)) to \(Self.timestampLabel(last.unix)), \(low) to \(high) beats per minute, \(sortedPoints.count) readings. Missing intervals are gaps."
    }

    private func chartPath(
        segments: [[HeartRateChartPoint]],
        in rect: CGRect,
        bounds: (lower: Double, upper: Double),
        firstUnix: Int,
        lastUnix: Int,
        closingAtBottom: Bool
    ) -> Path {
        Path { path in
            for segment in segments where segment.count > 1 {
                let locations = segment.map {
                    location(for: $0, in: rect, bounds: bounds, firstUnix: firstUnix, lastUnix: lastUnix)
                }
                guard let first = locations.first, let last = locations.last else { continue }
                if closingAtBottom {
                    path.move(to: CGPoint(x: first.x, y: rect.maxY))
                    path.addLine(to: first)
                } else {
                    path.move(to: first)
                }

                for index in 0..<(locations.count - 1) {
                    let start = locations[index]
                    let end = locations[index + 1]
                    let previous = index > 0 ? locations[index - 1] : start
                    let next = index + 2 < locations.count ? locations[index + 2] : end
                    let control1 = CGPoint(
                        x: start.x + (end.x - previous.x) / 6,
                        y: start.y + (end.y - previous.y) / 6
                    )
                    let control2 = CGPoint(
                        x: end.x - (next.x - start.x) / 6,
                        y: end.y - (next.y - start.y) / 6
                    )
                    path.addCurve(to: end, control1: control1, control2: control2)
                }

                if closingAtBottom {
                    path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
                    path.closeSubpath()
                }
            }
        }
    }

    private static func bpmBounds(for points: [HeartRateChartPoint]) -> (lower: Double, upper: Double) {
        let values = points.map { Double($0.bpm) }
        let lower = floor(max(0, (values.min() ?? 0) - 5) / 5) * 5
        let upper = ceil(((values.max() ?? 10) + 5) / 5) * 5
        return (lower, max(lower + 10, upper))
    }

    private func location(
        for point: HeartRateChartPoint,
        in rect: CGRect,
        bounds: (lower: Double, upper: Double),
        firstUnix: Int,
        lastUnix: Int
    ) -> CGPoint {
        let x = firstUnix == lastUnix
            ? rect.midX
            : rect.minX + rect.width * CGFloat(Double(point.unix - firstUnix) / Double(lastUnix - firstUnix))
        let fraction = (bounds.upper - Double(point.bpm)) / (bounds.upper - bounds.lower)
        return CGPoint(x: x, y: rect.minY + rect.height * CGFloat(fraction))
    }

    private func axisValue(at index: Int, bounds: (lower: Double, upper: Double)) -> String {
        let fraction = Double(index) / 2
        return String(format: "%.0f", bounds.upper - (bounds.upper - bounds.lower) * fraction)
    }

    private static func clock(_ unix: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
    }

    private static func timestampLabel(_ unix: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(unix))
            .formatted(date: .abbreviated, time: .shortened)
    }
}