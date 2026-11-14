import SwiftUI

/// WHOOP-inspired dated trend screen. It displays only saved readings and
/// keeps missing days as gaps in the chart.
struct MetricHistoryView: View {
    @EnvironmentObject private var store: AppStore
    let metric: DetailMetric
    @State private var selectedMetric: DetailMetric
    @State private var window = 30
    @State private var dayOffset = 0

    init(metric: DetailMetric) {
        self.metric = metric
        _selectedMetric = State(initialValue: metric)
    }

    private var ending: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }

    private var energy: [String: Double] {
        var values: [String: Double] = [:]
        for record in store.liveActivities {
            guard let kcal = store.activeKcal(for: record) else { continue }
            values[record.dateKey, default: 0] += kcal
        }
        for session in store.detectedBandActivities {
            guard !store.liveActivities.contains(where: {
                $0.startedUnix <= session.endUnix && session.startUnix < $0.endedUnix
            }), let kcal = store.activeKcal(for: session) else { continue }
            let key = JournalStore.dayKey(for: Date(timeIntervalSince1970: TimeInterval(session.startUnix)))
            values[key, default: 0] += kcal
        }
        return values
    }

    private var points: [MetricDay] {
        if store.isPreview {
            return MetricTimeline.preview(ending: ending, count: window)
        }
        return MetricTimeline.make(
            days: store.band.days,
            live: store.liveActivities,
            manual: store.manualActivities,
            caloriesByDay: energy,
            ending: ending,
            count: window,
            sleepNeedHours: store.settings.sleepNeedHours
        )
    }

    private var selectedKey: String { JournalStore.dayKey(for: ending) }
    private var eligiblePoints: [MetricDay] {
        points.filter { dayOffset != 0 || $0.key < selectedKey }
    }
    private var readings: [Double] { eligiblePoints.compactMap { $0.value(selectedMetric) } }
    private var average: Double? {
        guard !readings.isEmpty else { return nil }
        if selectedMetric.isTime {
            // Normalize to the selected calendar range, including an unrecorded
            // current day. This avoids inflating a partial week into a full one.
            return MetricTimeline.averageWeeklyDuration(readings, calendarDayCount: window)
        }
        return Stats.mean(readings)
    }
    private var rangeTitle: String {
        guard let first = points.first?.date, let last = points.last?.date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: first)) - \(formatter.string(from: last))"
    }
    private var rangeDescription: String {
        switch selectedMetric {
        case .hrv: return "Your average HRV is shown from recorded overnight readings."
        case .rhr: return "Your average resting heart rate is shown from saved daily measurements."
        case .respiration: return "Only dated respiratory-rate readings are included."
        case .calories: return "Calories are local activity estimates from recorded sessions."
        case .zonesLow, .zonesHigh: return "Zone time is derived from recorded heart-rate samples and logged activities."
        case .recovery: return "Recovery is a local estimate based on the available recorded inputs."
        case .sleepPerformance: return "Sleep performance is estimated from recorded sleep and configured sleep need."
        default: return "The chart uses saved daily readings; missing days remain blank."
        }
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                Panel {
                    Menu {
                        ForEach(DetailMetric.allCases) { item in
                            Button(item.title) { selectedMetric = item }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedMetric.icon)
                                .font(.system(size: 19, weight: .light))
                                .foregroundStyle(Color.appMuted)
                            Text(selectedMetric.title.uppercased())
                                .font(StrapTypography.body(14, weight: .semibold))
                                .tracking(0.7)
                                .foregroundStyle(Color.appFG)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.appFG)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.appRaised))

                    HStack(alignment: .bottom, spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(selectedMetric.isTime ? "AVG. WEEKLY TOTAL" : "AVERAGE")
                                .font(StrapTypography.body(10, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(Color.appMuted)
                            Text(selectedMetric.text(average))
                                .font(StrapTypography.metric(34, weight: .bold))
                                .foregroundStyle(Color.appFG)
                                .contentTransition(.numericText())
                            if selectedMetric.isTime {
                                Text("\(readings.count)/\(eligiblePoints.count) days with recorded duration")
                                    .font(StrapTypography.body(10))
                                    .foregroundStyle(Color.appMuted)
                            }
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 3) {
                            periodButton("W", days: 7)
                            periodButton("M", days: 30)
                            periodButton("6M", days: 180)
                        }
                        .padding(4)
                        .background(Color.appBG, in: Capsule())
                    }
                    .padding(.top, 18)

                    HStack(spacing: 12) {
                        Button { dayOffset -= window } label: {
                            Image(systemName: "chevron.left").frame(width: 30, height: 32)
                        }
                        Spacer()
                        Text(rangeTitle.uppercased())
                            .font(StrapTypography.body(11, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(Color.appFG)
                        Spacer()
                        Button { dayOffset = min(0, dayOffset + window) } label: {
                            Image(systemName: "chevron.right").frame(width: 30, height: 32)
                        }
                        .disabled(dayOffset == 0)
                    }
                    .font(StrapTypography.body(12, weight: .medium))
                    .foregroundStyle(dayOffset == 0 ? Color.appMuted : Color.appFG)
                    .padding(.top, 10)

                    Text(rangeDescription)
                        .font(StrapTypography.body(13, weight: .medium))
                        .foregroundStyle(Color.appFG)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)

                    TrendMetricChart(
                        metric: selectedMetric,
                        points: points,
                        selectedKey: dayOffset == 0 ? nil : selectedKey,
                        average: chartAverage
                    )
                    .padding(.top, 16)

                    Text(dayOffset == 0 ? "Average excludes today. Missing measurements are not filled in." : "Only saved measurements are included. Missing days remain blank.")
                        .font(StrapTypography.body(10))
                        .foregroundStyle(Color.appMuted)
                        .padding(.top, 4)
                }

                Panel {
                    SectionTitle("Daily history")
                    ForEach(points.reversed()) { day in
                        HStack {
                            Text(day.date.formatted(date: .abbreviated, time: .omitted))
                                .font(StrapTypography.body(13, weight: .medium))
                                .foregroundStyle(Color.appFG)
                            Spacer()
                            Text(selectedMetric.text(day.value(selectedMetric)))
                                .font(StrapTypography.metric(15, weight: .regular))
                                .foregroundStyle(Color.appFG)
                        }
                        .padding(.vertical, 9)
                        Divider().overlay(Color.appLine)
                    }
                    Hint(historyNote)
                }
            }
        }
        .navigationTitle("TREND VIEW")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func periodButton(_ title: String, days: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { window = days }
        } label: {
            Text(title)
                .font(StrapTypography.body(11, weight: window == days ? .semibold : .medium))
                .foregroundStyle(window == days ? Color.appFG : Color.appMuted)
                .frame(width: title == "6M" ? 47 : 38, height: 34)
                .background {
                    if window == days { RoundedRectangle(cornerRadius: 10).fill(Color.appRaised) }
                }
        }
        .buttonStyle(.plain)
    }

    /// The graph is plotted per day. Time-metric headline values are weekly
    /// totals, so keep the dashed reference on the same daily scale as its bars.
    private var chartAverage: Double? {
        guard !readings.isEmpty else { return nil }
        return Stats.mean(readings)
    }

    private var historyNote: String {
        switch selectedMetric {
        case .calories:
            return "Activity calories are local estimates based on recorded heart rate and profile data; they are not a full-day total."
        case .strength:
            return "Strength duration comes from saved activity logs. No duration is inferred when the log has no recorded time."
        case .zonesLow, .zonesHigh:
            return "Heart-rate zone time uses recorded heart-rate samples and saved activity sessions."
        case .recovery:
            return "Recovery is a local estimate using available recorded inputs and baseline days."
        case .sleepPerformance:
            return "Sleep performance is estimated from recorded sleep and configured sleep need."
        case .respiration:
            return "Respiratory rate is shown only when a dated validated value exists."
        default:
            return "This chart uses saved daily values for this metric. Missing readings are not substituted."
        }
    }
}

/// Compact long-range chart with sparse date labels and honest gaps.
private struct TrendMetricChart: View {
    let metric: DetailMetric
    let points: [MetricDay]
    let selectedKey: String?
    let average: Double?

    private var bounds: (low: Double, high: Double) {
        let values = points.compactMap { $0.value(metric) }
        if metric == .recovery || metric == .sleepPerformance { return (0, 100) }
        if metric == .strain { return (0, 21) }
        if metric.isLine, let low = values.min(), let high = values.max() {
            let pad = max(metric == .respiration ? 0.5 : 2, (high - low) * 0.3)
            return (max(0, low - pad), high + pad)
        }
        return (0, max(1, (values.max() ?? 0) * 1.2))
    }

    var body: some View {
        GeometryReader { geometry in
            let left: CGFloat = 34
            let right: CGFloat = 4
            let top: CGFloat = 14
            let bottom: CGFloat = 34
            let plotWidth = max(1, geometry.size.width - left - right)
            let plotHeight = max(1, geometry.size.height - top - bottom)
            let low = bounds.low
            let high = bounds.high
            let range = max(0.001, high - low)
            ZStack(alignment: .topLeading) {
                ForEach(0..<5, id: \.self) { index in
                    let fraction = CGFloat(index) / 4
                    let y = top + plotHeight * fraction
                    Path { path in
                        path.move(to: CGPoint(x: left, y: y))
                        path.addLine(to: CGPoint(x: left + plotWidth, y: y))
                    }.stroke(Color.appLine, lineWidth: 1)
                    Text(yLabel(value: high - Double(fraction) * range))
                        .font(StrapTypography.body(9))
                        .foregroundStyle(Color.appMuted)
                        .position(x: left / 2, y: y)
                }

                if let average {
                    let y = top + plotHeight * CGFloat(1 - (average - low) / range)
                    Path { path in
                        path.move(to: CGPoint(x: left, y: y))
                        path.addLine(to: CGPoint(x: left + plotWidth, y: y))
                    }.stroke(Color.appMuted.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                if let selectedKey, let index = points.firstIndex(where: { $0.key == selectedKey }) {
                    let x = left + plotWidth * (CGFloat(index) + 0.5) / CGFloat(max(1, points.count))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.appFG.opacity(0.07))
                        .frame(width: plotWidth / CGFloat(max(1, points.count)) * 0.82, height: plotHeight + bottom)
                        .position(x: x, y: top + plotHeight / 2 + bottom / 2)
                }

                if metric.isLine {
                    chartLine(left: left, top: top, width: plotWidth, height: plotHeight, low: low, range: range)
                        .stroke(metric.color(nil), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    ForEach(MetricTimeline.isolatedLineIndices(points.map { $0.value(metric) }), id: \.self) { index in
                        if let value = points[index].value(metric) {
                            let x = left + plotWidth * (CGFloat(index) + 0.5) / CGFloat(max(1, points.count))
                            let y = top + plotHeight * CGFloat(1 - (value - low) / range)
                            Circle()
                                .fill(metric.color(nil))
                                .frame(width: 6, height: 6)
                                .position(x: x, y: y)
                        }
                    }
                } else {
                    ForEach(Array(points.enumerated()), id: \.element.key) { index, day in
                        if let value = day.value(metric), value > 0 {
                            let slot = plotWidth / CGFloat(max(1, points.count))
                            let barHeight = plotHeight * CGFloat(min(1, max(0, value - low) / range))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(metric.color(value))
                                .frame(width: min(12, slot * 0.62), height: max(1, barHeight))
                                .position(x: left + slot * (CGFloat(index) + 0.5), y: top + plotHeight - barHeight / 2)
                        }
                    }
                }

                ForEach(axisIndices, id: \.self) { index in
                    if points.indices.contains(index) {
                        Text(axisLabel(points[index].date))
                            .font(StrapTypography.body(9))
                            .foregroundStyle(Color.appMuted)
                            .lineLimit(1)
                            .position(x: left + plotWidth * (CGFloat(index) + 0.5) / CGFloat(max(1, points.count)),
                                      y: top + plotHeight + 18)
                    }
                }
            }
        }
        .frame(height: 238)
        .accessibilityLabel(metric.title + " trend chart, with gaps for days without readings")
    }

    private var axisIndices: [Int] {
        guard !points.isEmpty else { return [] }
        let n = min(5, points.count)
        return (0..<n).map { n == 1 ? 0 : Int((Double($0) * Double(points.count - 1) / Double(n - 1)).rounded()) }
    }

    private func chartLine(left: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat,
                           low: Double, range: Double) -> Path {
        Path { path in
            var connected = false
            for (index, day) in points.enumerated() {
                guard let value = day.value(metric) else { connected = false; continue }
                let x = left + width * (CGFloat(index) + 0.5) / CGFloat(max(1, points.count))
                let y = top + height * CGFloat(1 - (value - low) / range)
                if connected { path.addLine(to: CGPoint(x: x, y: y)) } else { path.move(to: CGPoint(x: x, y: y)) }
                connected = true
            }
        }
    }

    private func yLabel(value: Double) -> String {
        metric.isTime ? ActivityFormat.clock(minutes: value) : metric.text(value)
    }

    private func axisLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
