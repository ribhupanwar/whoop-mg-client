import SwiftUI

/// WHOOP-inspired dated trend screen. It displays only saved readings and
/// keeps missing days as gaps in the chart.
struct MetricHistoryView: View {
    @EnvironmentObject private var store: AppStore
    let metric: DetailMetric
    @State private var selectedMetric: DetailMetric
    @State private var window = 30
    @State private var dayOffset = 0
    @State private var showLogger = false
    @State private var learnTopic: String?

    init(metric: DetailMetric) {
        self.metric = metric
        _selectedMetric = State(initialValue: metric)
        _window = State(initialValue: metric.isTime ? 28 : 30)
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
            sleepNeedHours: store.settings.sleepNeedHours,
            maxHR: store.settings.ageConfirmed ? (store.settings.maxHROverride ?? Karvonen.agePredictedMaxHR(age: store.settings.age)) : nil,
            imported: store.whoopImportedDays
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
        return "\(formatter.string(from: first)) - \(formatter.string(from: last)), \(last.formatted(.dateTime.year(.twoDigits)))"
    }
    private var rangeDescription: String {
        guard let average else { return "Wear your band and save readings to see your \(selectedMetric.title.lowercased()) trend here." }
        let period = window == 7 ? "week" : window <= 30 ? "month" : "six-month period"
        switch selectedMetric {
        case .hrv:
            return "Your average HRV this \(period) is \(selectedMetric.text(average)). Wear your band to bed each night to track how your HRV changes over time."
        case .rhr:
            return "Your average RHR this \(period) is \(selectedMetric.text(average)). Wear your band to bed each night to track your sleep and monitor your RHR over time."
        case .zonesLow, .zonesHigh, .strength:
            return "Your average weekly total is \(selectedMetric.text(average)) across this \(period). Only recorded activity duration is included."
        default:
            return "Your average \(selectedMetric.title.lowercased()) this \(period) is \(selectedMetric.text(average)). Missing measurements remain blank."
        }
    }

    private var unit: String {
        switch selectedMetric {
        case .hrv: return "ms"
        case .rhr: return "bpm"
        case .respiration: return "rpm"
        case .zonesLow, .zonesHigh, .strength: return "hr"
        case .calories: return "kcal"
        case .vo2: return "ml/kg/min"
        default: return ""
        }
    }
    private var buckets: [MetricDurationBucket] {
        MetricTimeline.durationBuckets(points, metric: selectedMetric, daysPerBucket: window == 7 ? 1 : 7)
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                metricMenu
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedMetric.isTime ? "AVG. WEEKLY TOTAL" : "AVERAGE")
                            .font(StrapTypography.body(10, weight: .bold)).tracking(0.8)
                            .foregroundStyle(Color.appMuted)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(selectedMetric.text(average)).font(StrapTypography.metric(32))
                            Text(unit).font(StrapTypography.body(13, weight: .semibold))
                        }.foregroundStyle(Color.appFG)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 14) {
                        HStack(spacing: 0) {
                            periodButton("W", days: 7)
                            periodButton("M", days: selectedMetric.isTime ? 28 : 30)
                            periodButton("6M", days: 180)
                        }.padding(4).background(Color.appBG.opacity(0.8), in: RoundedRectangle(cornerRadius: 11))
                        HStack(spacing: 8) {
                            Button { dayOffset -= window } label: {
                                Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold))
                            }.frame(width: 20, height: 28).accessibilityLabel("Previous period")
                            Text(rangeTitle.uppercased()).font(StrapTypography.body(10, weight: .bold)).tracking(0.7)
                                .foregroundStyle(Color.appFG).lineLimit(1).minimumScaleFactor(0.75)
                            Button { dayOffset = min(0, dayOffset + window) } label: {
                                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold))
                            }.frame(width: 20, height: 28).disabled(dayOffset == 0).accessibilityLabel("Next period")
                        }.foregroundStyle(Color.appMuted)
                    }.frame(width: 178)
                }.padding(.top, 28)

                Text(rangeDescription).font(StrapTypography.body(14, weight: .medium))
                    .foregroundStyle(Color.appFG).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22).padding(.bottom, 24)

                if selectedMetric.isTime {
                    DurationTrendChart(metric: selectedMetric, buckets: buckets,
                                       average: window == 7 ? average.map { $0 / 7 } : average)
                    zoneBreakdown
                    if selectedMetric == .zonesLow || selectedMetric == .zonesHigh {
                        Button { showLogger = true } label: {
                            HStack {
                                Image(systemName: "plus").font(.system(size: 24, weight: .light)).foregroundStyle(Color.appMuted)
                                Text("ADD ACTIVITY").font(StrapTypography.body(12, weight: .bold)).tracking(0.8)
                                Spacer()
                                Image(systemName: "chevron.right")
                            }.foregroundStyle(Color.appFG).padding(18)
                                .background(LinearGradient.appCard, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).padding(.top, 24)
                        NavigationLink { PlanView() } label: {
                            Label("VIEW YOUR WEEKLY PLAN", systemImage: "list.clipboard")
                                .font(StrapTypography.body(11, weight: .bold)).tracking(0.6)
                                .foregroundStyle(Color.appFG).frame(maxWidth: .infinity, alignment: .leading).padding(18)
                                .background(LinearGradient.appCard, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).padding(.top, 12)
                    }
                } else {
                    TrendMetricChart(metric: selectedMetric, points: points,
                                     selectedKey: selectedKey, average: chartAverage)
                    learnMore
                }
                DisclosureGroup("Daily history") {
                    ForEach(points.reversed()) { day in
                        HStack {
                            Text(day.date.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text((day.usesWHOOP(selectedMetric) ? "WHOOP · " : "") + selectedMetric.text(day.value(selectedMetric))).font(StrapTypography.metric(14, weight: .regular))
                        }.font(StrapTypography.body(12)).padding(.vertical, 9)
                        Divider().overlay(Color.appLine)
                    }
                    Hint(historyNote)
                    if points.contains(where: { $0.usesWHOOP(selectedMetric) }) {
                        Hint("WHOOP imported values fill gaps on their original dates; existing local measurements take precedence.")
                    }
                    Hint(dayOffset == 0 ? "Average excludes today. Missing measurements are not filled in." : "Only saved measurements are included.")
                }.font(StrapTypography.body(12)).tint(Color.appMuted).padding(.top, 28)
            }.foregroundStyle(Color.appFG)
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("TREND VIEW").font(StrapTypography.body(12, weight: .bold)).tracking(1)
            }
        }
        .sheet(isPresented: $showLogger) { ActivityLoggerView() }
        .sheet(isPresented: Binding(get: { learnTopic != nil }, set: { if !$0 { learnTopic = nil } })) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(learnTopic ?? selectedMetric.title).font(StrapTypography.body(24, weight: .bold))
                        Text(rangeDescription)
                        Text(historyNote)
                        Text("The typical range is the middle half of the available readings in the selected period. It is shown only when at least five readings are available.")
                    }.font(StrapTypography.body(16)).padding(24)
                }.navigationTitle("Learn more")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { learnTopic = nil } } }
            }
        }
        .onChange(of: selectedMetric) { _, metric in
            if window == 28 || window == 30 { window = metric.isTime ? 28 : 30 }
        }
    }

    private var metricMenu: some View {
        Menu {
            ForEach(DetailMetric.allCases) { item in
                Button(item.title) { selectedMetric = item }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedMetric.icon).font(.system(size: 20, weight: .light)).foregroundStyle(Color.appMuted)
                Text(selectedMetric.title.uppercased()).font(StrapTypography.body(12, weight: .bold)).tracking(0.8)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 16, weight: .bold))
            }.foregroundStyle(Color.appFG).padding(.horizontal, 16).frame(minHeight: 70)
                .background(LinearGradient.appCard, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).padding(.top, 12)
    }

    private var zoneBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Zone time is derived from recorded samples and logged activities", systemImage: "info.circle")
                .font(StrapTypography.body(10)).foregroundStyle(Color.appMuted).padding(.vertical, 16)
            if selectedMetric == .zonesLow || selectedMetric == .zonesHigh {
                let indices = selectedMetric == .zonesHigh ? [3, 4] : [0, 1, 2]
                let known = eligiblePoints.compactMap(\.zones).filter { $0.count == 5 }
                let totals = indices.map { zone in known.reduce(0) { $0 + $1[zone] } / 60 / (Double(window) / 7) }
                Text("HR ZONES BREAKDOWN (AVG. WEEKLY TOTAL)")
                    .font(StrapTypography.body(10, weight: .bold)).tracking(0.7).padding(.bottom, 4)
                if !known.isEmpty {
                    SplitBar(segments: zip(indices, totals).map { zone, total in
                        SplitBar.Segment(fraction: total / max(1, totals.reduce(0, +)), color: zonePalette[zone])
                    })
                    ForEach(Array(indices.enumerated()), id: \.offset) { offset, zone in
                        HStack(spacing: 10) {
                            Rectangle().fill(zonePalette[zone]).frame(width: 8, height: 8)
                            Text(ActivityFormat.clock(minutes: totals[offset])).font(StrapTypography.metric(15))
                            Text("Zone \(zone + 1)").font(StrapTypography.body(14)).foregroundStyle(Color.appMuted)
                        }
                    }
                } else { Hint("Recorded zone time will appear here after an activity is saved.") }
            }
        }
    }

    private var learnMore: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LEARN MORE").font(StrapTypography.body(10, weight: .bold)).tracking(1).foregroundStyle(Color.appMuted)
            HStack(spacing: 10) {
                learningCard("Understanding \(selectedMetric.title)", icon: selectedMetric.icon)
                learningCard("Your recorded range", icon: "chart.xyaxis.line")
            }
        }.padding(.top, 28)
    }
    private func learningCard(_ title: String, icon: String) -> some View {
        Button { learnTopic = title } label: {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: icon).font(.system(size: 42, weight: .ultraLight)).foregroundStyle(recoveryLineBlue)
                    .frame(maxWidth: .infinity, minHeight: 74)
                Text(title).font(StrapTypography.body(13, weight: .semibold)).foregroundStyle(Color.appFG)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(14).frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                .background(LinearGradient.appCard, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private func periodButton(_ title: String, days: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { window = days }
        } label: {
            Text(title)
                .font(StrapTypography.body(11, weight: window == days ? .semibold : .medium))
                .foregroundStyle(window == days ? Color.appFG : Color.appMuted)
                .frame(maxWidth: .infinity, minHeight: 31)
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
        case .vo2:
            return "Uth 2004 estimate reconstructed from saved overnight resting HR and your current confirmed max-HR profile. This is not a measured VO₂ max test. Missing nights remain blank."
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

    private var typicalRange: (Double, Double)? {
        let sorted = points.compactMap { $0.value(metric) }.sorted()
        guard metric.isLine, sorted.count >= 5 else { return nil }
        return (sorted[(sorted.count - 1) / 4], sorted[(sorted.count - 1) * 3 / 4])
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if typicalRange != nil {
                HStack(spacing: 8) {
                    Rectangle().fill(Color.appMuted.opacity(0.18)).frame(width: 8, height: 8)
                    Text("TYPICAL RANGE").font(StrapTypography.body(9, weight: .bold)).tracking(0.7)
                }.foregroundStyle(Color.appMuted)
            }
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

                if let typicalRange {
                    let topY = top + plotHeight * CGFloat(1 - (typicalRange.1 - low) / range)
                    let bottomY = top + plotHeight * CGFloat(1 - (typicalRange.0 - low) / range)
                    Rectangle().fill(Color.appMuted.opacity(0.14))
                        .frame(width: plotWidth, height: max(1, bottomY - topY))
                        .offset(x: left, y: topY)
                }

                if let selectedKey, let index = points.firstIndex(where: { $0.key == selectedKey }) {
                    let x = left + plotWidth * (CGFloat(index) + 0.5) / CGFloat(max(1, points.count))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.appFG.opacity(0.07))
                        .frame(width: plotWidth / CGFloat(max(1, points.count)) * 0.82, height: plotHeight + bottom)
                        .position(x: x, y: top + plotHeight / 2 + bottom / 2)
                }

                if metric.isLine {
                    chartArea(left: left, top: top, width: plotWidth, height: plotHeight, low: low, range: range)
                        .fill(LinearGradient(colors: [recoveryLineBlue.opacity(0.17), .clear], startPoint: .top, endPoint: .bottom))
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

                if metric.isLine, let last = points.last, let value = last.value(metric) {
                    let x = left + plotWidth * (CGFloat(points.count) - 0.5) / CGFloat(max(1, points.count))
                    let y = top + plotHeight * CGFloat(1 - (value - low) / range)
                    Circle().fill(Color.appBG).frame(width: 7, height: 7)
                        .overlay(Circle().stroke(recoveryLineBlue, lineWidth: 1.8)).position(x: x, y: y)
                    Text(metric.text(value)).font(StrapTypography.metric(12)).foregroundStyle(recoveryLineBlue)
                        .position(x: x, y: max(6, y - 13))
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
        }
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

    private func chartArea(left: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat,
                           low: Double, range: Double) -> Path {
        Path { path in
            var last: CGPoint?
            for (index, day) in points.enumerated() {
                guard let value = day.value(metric) else {
                    if let last { path.addLine(to: CGPoint(x: last.x, y: top + height)); path.closeSubpath() }
                    last = nil
                    continue
                }
                let x = left + width * (CGFloat(index) + 0.5) / CGFloat(max(1, points.count))
                let point = CGPoint(x: x, y: top + height * CGFloat(1 - (value - low) / range))
                if last == nil { path.move(to: CGPoint(x: x, y: top + height)) }
                path.addLine(to: point)
                last = point
            }
            if let last { path.addLine(to: CGPoint(x: last.x, y: top + height)); path.closeSubpath() }
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

private struct DurationTrendChart: View {
    let metric: DetailMetric
    let buckets: [MetricDurationBucket]
    let average: Double?
    private var zoneIndices: [Int] { metric == .zonesHigh ? [3, 4] : [0, 1, 2] }
    private var maximum: Double { max(60, ceil((buckets.compactMap(\.minutes).max() ?? 0) / 60) * 60) }
    var body: some View {
        GeometryReader { geometry in
            let left: CGFloat = 38
            let width = max(1, geometry.size.width - left - 4)
            let height: CGFloat = 200
            let slot = width / CGFloat(max(1, buckets.count))
            ZStack(alignment: .topLeading) {
                ForEach(0...4, id: \.self) { tick in
                    let y = height * CGFloat(tick) / 4
                    Path { path in
                        path.move(to: CGPoint(x: left, y: y))
                        path.addLine(to: CGPoint(x: left + width, y: y))
                    }.stroke(Color.appLine, lineWidth: 0.7)
                    Text(ActivityFormat.clock(minutes: maximum * (1 - Double(tick) / 4)))
                        .font(StrapTypography.metric(9, weight: .regular)).foregroundStyle(Color.appMuted)
                        .position(x: 14, y: y)
                }
                ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                    let x = left + slot * (CGFloat(index) + 0.5)
                    if let minutes = bucket.minutes {
                        if let zones = bucket.zoneSeconds, metric == .zonesLow || metric == .zonesHigh {
                            ForEach(zoneIndices, id: \.self) { zone in
                                let before = zoneIndices.filter { $0 < zone }.reduce(0.0) { $0 + zones[$1] / 60 }
                                let segmentHeight = height * CGFloat(zones[zone] / 60 / maximum)
                                Rectangle().fill(zonePalette[zone])
                                    .frame(width: min(58, slot * 0.75), height: max(0, segmentHeight - 1))
                                    .position(x: x, y: height - height * CGFloat(before / maximum) - segmentHeight / 2)
                            }
                        } else {
                            let barHeight = height * CGFloat(minutes / maximum)
                            RoundedRectangle(cornerRadius: 2).fill(strainBlue)
                                .frame(width: min(58, slot * 0.75), height: barHeight)
                                .position(x: x, y: height - barHeight / 2)
                        }
                    }
                    Text(label(bucket)).font(StrapTypography.body(9)).foregroundStyle(Color.appMuted)
                        .position(x: x, y: height + 20)
                }
                if let average {
                    let y = height * CGFloat(1 - min(1, max(0, average / maximum)))
                    Path { path in
                        path.move(to: CGPoint(x: left, y: y)); path.addLine(to: CGPoint(x: left + width, y: y))
                    }.stroke(Color.appFG, style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
                    Text("AVG.").font(StrapTypography.body(9, weight: .bold)).foregroundStyle(Color.appBG)
                        .padding(4).background(Color.appFG, in: RoundedRectangle(cornerRadius: 3)).position(x: 18, y: y)
                }
            }
        }.frame(height: 235).padding(.top, 16)
        .accessibilityLabel(metric.title + " recorded duration by calendar period")
    }
    private func label(_ bucket: MetricDurationBucket) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "MMM d"
        if Calendar.current.isDate(bucket.start, inSameDayAs: bucket.end) { return formatter.string(from: bucket.end) }
        return formatter.string(from: bucket.start) + "–" + bucket.end.formatted(.dateTime.day())
    }
}
