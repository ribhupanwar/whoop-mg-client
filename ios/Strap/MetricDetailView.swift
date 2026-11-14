import SwiftUI

private let strainBlue = Color(hex: 0x009FEE)
private let zonePalette: [Color] = [Color(hex: 0xABC5D0), Color(hex: 0x4C9DBB), Color(hex: 0x5CB99C), Color(hex: 0xFFB35B), Color(hex: 0xFF702A)]

extension DetailMetric {
    var title: String {
        switch self {
        case .strain: return "Strain"
        case .recovery: return "Recovery"
        case .hrv: return "Heart rate variability"
        case .rhr: return "Resting heart rate"
        case .respiration: return "Respiratory rate"
        case .sleepPerformance: return "Sleep performance"
        case .zonesLow: return "HR zones 1–3"
        case .zonesHigh: return "HR zones 4–5"
        case .steps: return "Steps"
        case .calories: return "Calories"
        case .strength: return "Strength activity time"
        }
    }
    var icon: String {
        switch self {
        case .hrv: return "waveform.path.ecg"
        case .rhr: return "heart"
        case .respiration: return "lungs"
        case .sleepPerformance: return "moon"
        case .zonesLow, .zonesHigh: return "heart.text.square"
        case .strength: return "dumbbell"
        case .steps: return "figure.walk"
        case .calories: return "flame"
        default: return "chart.bar"
        }
    }
    var isLine: Bool { self == .hrv || self == .rhr || self == .respiration }
    var isTime: Bool { self == .zonesLow || self == .zonesHigh || self == .strength }
    func text(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        if isTime { return ActivityFormat.clock(minutes: value) }
        switch self {
        case .strain, .respiration: return String(format: "%.1f", value)
        case .recovery, .sleepPerformance: return String(format: "%.0f%%", value)
        default: return Int(value.rounded()).formatted()
        }
    }
    func color(_ value: Double?) -> Color {
        if self == .recovery, let value {
            return value >= 67 ? Color(hex: 0x25DE00) : value >= 34 ? Color(hex: 0xF4DD00) : Color(hex: 0xFF0037)
        }
        return self == .sleepPerformance ? .appSleep : strainBlue
    }
}

/// Dedicated daily Recovery/Strain pages, sharing dated inputs and chart slots.
struct MetricDetailView: View {
    @EnvironmentObject private var store: AppStore
    let recoveryMode: Bool
    @State private var dayOffset = 0
    @State private var detail: DetailMetric?
    @State private var showInfo = false
    @State private var expandedInsight = false

    private var endDate: Date { Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date() }
    private var selectedKey: String { JournalStore.dayKey(for: endDate) }
    private var mainMetric: DetailMetric { recoveryMode ? .recovery : .strain }
    private var metrics: [DetailMetric] {
        recoveryMode ? [.recovery, .hrv, .rhr, .respiration, .sleepPerformance]
            : [.strain, .zonesLow, .zonesHigh, .steps, .calories, .strength]
    }
    private var energy: [String: Double] {
        var values: [String: Double] = [:]
        for record in store.liveActivities {
            if let kcal = store.activeKcal(for: record) { values[record.dateKey, default: 0] += kcal }
        }
        for session in store.detectedBandActivities {
            guard !store.liveActivities.contains(where: { $0.startedUnix <= session.endUnix && session.startUnix < $0.endedUnix }) else { continue }
            if let kcal = store.activeKcal(for: session) {
                let key = JournalStore.dayKey(for: Date(timeIntervalSince1970: TimeInterval(session.startUnix)))
                values[key, default: 0] += kcal
            }
        }
        return values
    }
    private var points: [MetricDay] {
        if store.isPreview { return MetricTimeline.preview(ending: endDate) }
        return MetricTimeline.make(days: store.band.days, live: store.liveActivities, manual: store.manualActivities,
                            caloriesByDay: energy, ending: endDate, sleepNeedHours: store.settings.sleepNeedHours)
    }

    var body: some View {
        let history = points
        let current = history.last
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                hero(current, history: history)
                summary(current, history: history)
                if recoveryMode { behaviorCard } else { activities }
                Text("Weekly Trends").font(StrapTypography.body(23, weight: .semibold)).padding(.vertical, 18)
                ForEach(metrics) { metric in
                    Panel {
                        Button { detail = metric } label: {
                            HStack {
                                Text(metric.title.uppercased()).font(StrapTypography.body(12, weight: .semibold)).tracking(0.8)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Color.appMuted)
                            }.foregroundStyle(Color.appFG)
                        }.buttonStyle(.plain).padding(.bottom, 20)
                        WeeklyMetricChart(metric: metric, points: Array(history.suffix(7)), selectedKey: selectedKey)
                        Hint(sourceNote(metric))
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(dayOffset == 0 ? "TODAY" : endDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased())
                    .font(StrapTypography.body(12, weight: .bold)).tracking(1)
                    .contextMenu {
                        Button("Previous day") { dayOffset -= 1 }
                        Button("Next day") { dayOffset = min(0, dayOffset + 1) }.disabled(dayOffset == 0)
                        Button("Today") { dayOffset = 0 }
                    }
            }
            ToolbarItem(placement: .topBarTrailing) { Button { showInfo = true } label: { Image(systemName: "info.circle") } }
        }
        .alert("About these measurements", isPresented: $showInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Recovery and strain are local estimates from your recorded data. The white strain-ring marker is the previous 30-day recorded average. Recovery requires earlier baseline days. Zone time is recorded HR coverage; calories are active session estimates, not a full-day total. Missing data stays blank. The values are not WHOOP's proprietary scores.")
        }
        .sheet(item: $detail) { metric in
            NavigationStack {
                Screen {
                    Panel { WeeklyMetricChart(metric: metric, points: Array(history.suffix(7)), selectedKey: selectedKey) }
                    Panel {
                        Text("Last 30 days").font(.headline).padding(.bottom, 12)
                        ForEach(Array(history.suffix(30).reversed())) { day in
                            HStack {
                                Text(day.date.formatted(date: .abbreviated, time: .omitted))
                                Spacer()
                                Text(metric.text(day.value(metric))).monospacedDigit()
                            }.font(StrapTypography.metric(13, weight: .regular)).padding(.vertical, 9)
                            Divider().overlay(Color.appLine)
                        }
                        Hint(sourceNote(metric))
                    }
                }.navigationTitle(metric.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { detail = nil } } }
            }
        }
        .onAppear {
            #if DEBUG
            if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-chart=") }),
               let metric = DetailMetric(rawValue: String(argument.dropFirst("--preview-chart=".count))) { detail = metric }
            #endif
        }
        .safeAreaInset(edge: .bottom) { insight(current, history: history) }
    }

    private var dateControl: some View {
        HStack {
            Button { dayOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 40) }
            Spacer()
            Text(dayOffset == 0 ? "TODAY" : endDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased())
                .font(StrapTypography.body(12, weight: .bold)).tracking(1)
            Spacer()
            Button { dayOffset = min(0, dayOffset + 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 40) }
                .disabled(dayOffset == 0)
        }.foregroundStyle(Color.appFG)
    }

    private func hero(_ day: MetricDay?, history: [MetricDay]) -> some View {
        let value = day?.value(mainMetric)
        let scale = recoveryMode ? 100.0 : 21.0
        let mean = MetricTimeline.comparison(mainMetric, before: selectedKey, in: history)
        return ZStack {
            Circle().stroke(Color.appRaised, lineWidth: 15)
            if let value {
                Circle().trim(from: 0, to: min(1, max(0, value / scale)))
                    .stroke(mainMetric.color(value), style: StrokeStyle(lineWidth: 15, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if !recoveryMode, let mean {
                Rectangle().fill(Color.appFG).frame(width: 4, height: 15)
                    .offset(y: -118).rotationEffect(.degrees(mean / 21 * 360))
            }
            VStack(spacing: 8) {
                Text("STRAP").font(StrapTypography.body(17, weight: .light)).tracking(3).foregroundStyle(Color.appMuted)
                Text(mainMetric.text(value)).font(StrapTypography.body(57, weight: .bold))
                    .monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                Text(mainMetric.title.uppercased()).font(StrapTypography.body(13, weight: .bold)).tracking(1.4)
            }.padding(24)
        }
        .frame(width: 236, height: 236)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func comparisonIndicator(_ metric: DetailMetric, day: MetricDay?, history: [MetricDay]) -> some View {
        if let value = day?.value(metric),
           let mean = MetricTimeline.comparison(metric, before: selectedKey, in: history) {
            let unchanged = metric.text(value) == metric.text(mean)
            let rises = value > mean
            let favourable = (metric == .rhr || metric == .respiration) ? !rises : rises
            Image(systemName: unchanged ? "circle.fill" : rises ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: unchanged ? 5 : 7))
                .foregroundStyle(unchanged ? Color.appMuted : favourable ? Color.appGood : Color.appWarn)
                .accessibilityLabel(unchanged ? "Same as comparison" : rises ? "Above comparison" : "Below comparison")
        }
    }

    private func summary(_ day: MetricDay?, history: [MetricDay]) -> some View {
        let rows: [DetailMetric] = recoveryMode ? [.hrv, .rhr, .respiration, .sleepPerformance] : [.zonesLow, .zonesHigh, .strength, .steps]
        return Panel {
            ForEach(rows) { metric in
                HStack(spacing: 10) {
                    Image(systemName: metric.icon).font(.system(size: 20)).foregroundStyle(Color.appMuted).frame(width: 24)
                    Text(metric.title.uppercased()).font(StrapTypography.body(11, weight: .semibold)).tracking(0.5)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(metric.text(day?.value(metric))).font(StrapTypography.body(23, weight: .semibold)).monospacedDigit()
                            comparisonIndicator(metric, day: day, history: history)
                        }
                        Text(metric.text(MetricTimeline.comparison(metric, before: selectedKey, in: history)))
                            .font(StrapTypography.body(11)).foregroundStyle(Color.appMuted)
                    }
                }.padding(.vertical, 14)
                if metric != rows.last { Divider().overlay(Color.appLine) }
            }
            Text("Today vs. available readings in the previous 30 days")
                .font(StrapTypography.body(10)).foregroundStyle(Color.appMuted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(Color.appBG, in: RoundedRectangle(cornerRadius: 8)).padding(.top, 12)
        }
    }

    private var behaviorCard: some View {
        NavigationLink(value: Route.journal) {
            Panel {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Behavior insights").font(StrapTypography.body(17, weight: .semibold))
                        Text("Review your daily journal alongside your recovery history.").font(StrapTypography.body(12)).foregroundStyle(Color.appMuted)
                        Label("VIEW JOURNAL", systemImage: "arrow.right").font(StrapTypography.body(10, weight: .bold)).foregroundStyle(strainBlue)
                    }
                    Image(systemName: "checkmark.circle").font(.system(size: 64, weight: .light)).foregroundStyle(Color.appMuted)
                }
            }
        }.buttonStyle(.plain).foregroundStyle(Color.appFG)
    }

    private var activities: some View {
        let live = store.liveActivities(on: selectedKey)
        let detected = store.detectedActivities(on: selectedKey).filter { session in
            !live.contains { $0.startedUnix <= session.endUnix && session.startUnix < $0.endedUnix }
        }
        let manual = store.manualActivities(on: selectedKey)
        return VStack(alignment: .leading, spacing: 10) {
            Text(dayOffset == 0 ? "Today's Activities" : "Activities").font(StrapTypography.body(23, weight: .semibold)).padding(.top, 14)
            if store.isPreview {
                activityRow("Running · sample", icon: "figure.run", detail: "7:40 AM\n8:10 AM")
            }
            ForEach(detected) { session in
                activityRow(session.kind.capitalized, icon: session.kind == "run" ? "figure.run" : "figure.walk", detail: clockRange(session.startUnix, session.endUnix))
                    .contextMenu { Button("Delete Activity", role: .destructive) { store.deleteDetectedActivity(session) } }
            }
            ForEach(live) { record in
                activityRow("Live session", icon: "waveform.path.ecg", detail: clockRange(record.startedUnix, record.endedUnix))
                    .contextMenu { Button("Delete Activity", role: .destructive) { store.deleteLiveActivity(id: record.id) } }
            }
            ForEach(manual) { record in
                activityRow(record.name, icon: record.kind.icon, detail: record.summary)
                    .contextMenu { Button("Delete Activity", role: .destructive) { store.deleteActivity(id: record.id) } }
            }
            if !store.isPreview && live.isEmpty && detected.isEmpty && manual.isEmpty { Hint("No activities logged for this day.") }
        }
    }

    private func activityRow(_ title: String, icon: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 26)).frame(width: 62, height: 48)
                .background(strainBlue, in: RoundedRectangle(cornerRadius: 9))
            Text(title.uppercased()).font(StrapTypography.body(12, weight: .bold))
            Spacer()
            Text(detail).font(StrapTypography.body(11)).foregroundStyle(Color.appMuted).multilineTextAlignment(.trailing)
        }.padding(8).background(LinearGradient.appCard, in: RoundedRectangle(cornerRadius: 15)).contentShape(Rectangle())
    }
    private func clockRange(_ start: Int, _ end: Int) -> String {
        let a = Date(timeIntervalSince1970: TimeInterval(start)).formatted(date: .omitted, time: .shortened)
        let b = Date(timeIntervalSince1970: TimeInterval(end)).formatted(date: .omitted, time: .shortened)
        return a + "\n" + b
    }
    private func sourceNote(_ metric: DetailMetric) -> String {
        switch metric {
        case .calories: return "Active calories estimated for recorded sessions; not a full-day calorie total. Profile data is required."
        case .strength: return "Logged strength-session minutes. Sets without a recorded duration stay unknown."
        case .zonesLow, .zonesHigh: return "Recorded awake HR, with live-session zone time used when band history is unavailable. Missing coverage is not zero time."
        case .recovery: return "Local recovery estimate using earlier baseline days; missing inputs stay blank."
        case .sleepPerformance: return "The same local sleep performance report used by Sleep Analysis."
        case .respiration: return "Night-bound respiratory estimate from recorded R-R intervals."
        default: return "Recorded daily values. Missing days keep their dates and appear as gaps."
        }
    }
    private func insight(_ day: MetricDay?, history: [MetricDay]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expandedInsight.toggle() } label: {
                HStack {
                    Image(systemName: "waveform.path.ecg").foregroundStyle(strainBlue)
                    Text(mainMetric.title + " · " + mainMetric.text(day?.value(mainMetric)))
                        .font(StrapTypography.body(12, weight: .semibold))
                    Spacer()
                    Image(systemName: expandedInsight ? "chevron.down" : "chevron.up")
                }.foregroundStyle(Color.appFG)
            }.buttonStyle(.plain)
            if expandedInsight {
                Text("Previous 30-day comparison: " + mainMetric.text(MetricTimeline.comparison(mainMetric, before: selectedKey, in: history)))
                    .font(StrapTypography.body(12)).foregroundStyle(Color.appMuted)
                Text(sourceNote(mainMetric)).font(StrapTypography.body(11)).foregroundStyle(Color.appMuted)
            }
        }.padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 16).padding(.bottom, 6)
    }
}

struct WeeklyMetricChart: View {
    let metric: DetailMetric
    let points: [MetricDay]
    let selectedKey: String

    private var limits: (low: Double, high: Double) {
        let values = points.compactMap { $0.value(metric) }
        if metric == .recovery || metric == .sleepPerformance { return (0, 100) }
        if metric == .strain { return (0, 21) }
        if metric.isLine, let low = values.min(), let high = values.max() {
            let padding = max(metric == .respiration ? 0.5 : 2, (high - low) * 0.35)
            return (max(0, low - padding), high + padding)
        }
        return (0, max(1, (values.max() ?? 0) * 1.25))
    }
    private var zoneIndices: [Int] { metric == .zonesHigh ? [3, 4] : [0, 1, 2] }

    var body: some View {
        VStack(spacing: 12) {
            if metric == .zonesLow || metric == .zonesHigh {
                HStack(spacing: 12) {
                    Spacer()
                    ForEach(zoneIndices, id: \.self) { zone in
                        HStack(spacing: 4) {
                            Rectangle().fill(zonePalette[zone]).frame(width: 7, height: 7)
                            Text("ZONE \(zone + 1)").font(StrapTypography.body(9, weight: .semibold))
                        }
                    }
                }
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                let height: CGFloat = 190
                let slot = width / CGFloat(max(1, points.count))
                let low = limits.low
                let range = max(0.001, limits.high - low)
                ZStack(alignment: .topLeading) {
                    if metric.isLine {
                        areaPath(width: width, height: height, low: low, range: range)
                            .fill(LinearGradient(colors: [strainBlue.opacity(0.2), strainBlue.opacity(0.01)],
                                                 startPoint: .top, endPoint: .bottom))
                    }
                    Path { path in
                        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                            let y = height * CGFloat(fraction)
                            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: width, y: y))
                        }
                    }.stroke(Color.appLine, lineWidth: 1)
                    ForEach(Array(points.enumerated()), id: \.element.key) { index, day in
                        let x = slot * (CGFloat(index) + 0.5)
                        if day.key == selectedKey {
                            RoundedRectangle(cornerRadius: 5).fill(Color.appFG.opacity(0.08))
                                .frame(width: slot * 0.8, height: height + 50).position(x: x, y: (height + 50) / 2)
                        }
                        if let value = day.value(metric) {
                            let barHeight = height * CGFloat(max(0, value - low) / range)
                            if !metric.isLine {
                                if let zones = day.zones, metric == .zonesLow || metric == .zonesHigh {
                                    ForEach(zoneIndices, id: \.self) { zone in
                                        let preceding = zoneIndices.filter { $0 < zone }.reduce(0.0) { $0 + zones[$1] / 60 }
                                        let part = height * CGFloat(zones[zone] / 60 / range)
                                        Rectangle().fill(zonePalette[zone]).frame(width: min(24, slot * 0.38), height: part)
                                            .position(x: x, y: height - height * CGFloat(preceding / range) - part / 2)
                                    }
                                } else {
                                    RoundedRectangle(cornerRadius: 2).fill(metric.color(value))
                                        .frame(width: min(24, slot * 0.38), height: barHeight)
                                        .position(x: x, y: height - barHeight / 2)
                                }
                            } else {
                                Circle().fill(LinearGradient.appCard).frame(width: 7, height: 7)
                                    .overlay(Circle().stroke(strainBlue, lineWidth: 2)).position(x: x, y: height - barHeight)
                            }
                            Text(metric.text(value)).font(StrapTypography.metric(10, weight: .bold)).monospacedDigit()
                                .foregroundStyle(metric.color(value)).position(x: x, y: max(7, height - barHeight - 12))
                        } else {
                            Text("—").font(StrapTypography.body(10)).foregroundStyle(Color.appMuted).position(x: x, y: height - 12)
                        }
                        VStack(spacing: 3) {
                            Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                            Text(day.date.formatted(.dateTime.day()))
                        }.font(StrapTypography.body(9)).foregroundStyle(day.key == selectedKey ? Color.appFG : Color.appMuted)
                            .position(x: x, y: height + 27)
                    }
                    if metric.isLine {
                        linePath(width: width, height: height, low: low, range: range)
                            .stroke(strainBlue.opacity(0.7), lineWidth: 1.5)
                    }
                }
            }.frame(height: 245)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title + ". " + points.map {
            $0.date.formatted(date: .abbreviated, time: .omitted) + ": " + metric.text($0.value(metric))
        }.joined(separator: ". "))
    }
    private func areaPath(width: CGFloat, height: CGFloat, low: Double, range: Double) -> Path {
        Path { path in
            var last: CGPoint?
            for (index, day) in points.enumerated() {
                guard let value = day.value(metric) else {
                    if let point = last { path.addLine(to: CGPoint(x: point.x, y: height)); path.closeSubpath() }
                    last = nil
                    continue
                }
                let x = width * (CGFloat(index) + 0.5) / CGFloat(max(1, points.count))
                let point = CGPoint(x: x, y: height * CGFloat(1 - (value - low) / range))
                if last == nil { path.move(to: CGPoint(x: x, y: height)) }
                path.addLine(to: point)
                last = point
            }
            if let point = last { path.addLine(to: CGPoint(x: point.x, y: height)); path.closeSubpath() }
        }
    }

    private func linePath(width: CGFloat, height: CGFloat, low: Double, range: Double) -> Path {
        Path { path in
            var previous = false
            for (index, day) in points.enumerated() {
                guard let value = day.value(metric) else { previous = false; continue }
                let x = width * (CGFloat(index) + 0.5) / CGFloat(max(1, points.count))
                let y = height * CGFloat(1 - (value - low) / range)
                if previous { path.addLine(to: CGPoint(x: x, y: y)) } else { path.move(to: CGPoint(x: x, y: y)) }
                previous = true
            }
        }
    }
}
