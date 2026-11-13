import SwiftUI

/// Dashboard tab — the exact same metric rows as Home's My Dashboard
/// (shared component), plus the customize sheet and baseline progress.
struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showCustomize = false
    @State private var trendWindow = 7
    var focusedMetric: String? = nil

    private var demo: Bool { store.isPreview }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                if focusedMetric == nil { analyticsOverview }
                if focusedMetric == nil { insightPanel }
                trendsPanel
                if focusedMetric == nil { baselinePanel }
            }
        }
        .navigationTitle(focusedMetric == "recovery" ? "Recovery" : focusedMetric == "strain" ? "Strain" : "Dashboard")
        .navigationBarTitleDisplayMode(.inline)

    }

    private var analyticsOverview: some View {
        Panel {
            SectionTitle("Your trends")
            Text("Historical analysis · Home keeps your live metrics")
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
            HStack(spacing: 10) {
                analyticsStat("RECORDED DAYS", "\(recentDays.count)/\(trendWindow)")
                analyticsStat("HRV + RHR", "\(recentDays.filter { $0.lnRMSSD != nil && $0.restingHR != nil }.count) days")
                analyticsStat("SLEEP", "\(recentDays.filter { $0.sleepHours > 0 }.count) nights")
            }
            .padding(.top, 10)
            if !store.hasRecoveryBaseline {
                Hint("Recovery comparison needs 7 measured baseline days. Missing values stay blank.")
            }
        }
    }

    // Analytics tab is intentionally different from Home: show changes over
    // time and data coverage, not a second copy of today's metric tiles.
    private var insightPanel: some View {
        Panel {
            SectionTitle("What changed this week")
            Text("Personal trends · comparing recent and preceding recorded days")
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                insightTile("HRV CHANGE", value: hrvChangeText,
                            note: "recent 7 vs previous 7 days", icon: "waveform.path.ecg")
                insightTile("RHR CHANGE", value: rhrChangeText,
                            note: "recent 7 vs previous 7 days", icon: "heart")
                insightTile("SLEEP SHORTFALL", value: sleepShortfallText,
                            note: "recorded nights · vs sleep need", icon: "moon.zzz")
                insightTile("DATA COVERAGE", value: "\(lastSevenDays.count)/7",
                            note: "days with any band record", icon: "checkmark.shield")
            }
            Hint("Changes require measured days in both weeks. No missing value is replaced by zero. Sleep shortfall covers recorded nights only.")
        }
        .padding(.top, 10)
    }

    private var previousSevenDays: [DayMetrics] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let from = calendar.date(byAdding: .day, value: -13, to: start),
              let through = calendar.date(byAdding: .day, value: -7, to: start) else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let first = formatter.string(from: from)
        let last = formatter.string(from: through)
        return store.band.days.filter { $0.dateKey >= first && $0.dateKey <= last }
    }

    private func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var hrvChangeText: String {
        let recent = lastSevenDays.compactMap { $0.lnRMSSD.map(exp) }.filter { $0.isFinite }
        let previous = previousSevenDays.compactMap { $0.lnRMSSD.map(exp) }.filter { $0.isFinite }
        guard let a = mean(recent), let b = mean(previous), b > 0 else { return "—" }
        return String(format: "%+.0f%%", (a / b - 1) * 100)
    }

    private var rhrChangeText: String {
        guard let a = mean(lastSevenDays.compactMap { $0.restingHR }),
              let b = mean(previousSevenDays.compactMap { $0.restingHR }) else { return "—" }
        return String(format: "%+.1f bpm", a - b)
    }

    private var sleepShortfallText: String {
        let nights = lastSevenDays.compactMap { $0.sleepHours > 0 ? $0.sleepHours : nil }
        guard !nights.isEmpty else { return "—" }
        let missing = nights.reduce(0) { $0 + max(0, store.settings.sleepNeedHours - $1) }
        return String(format: "%.1f h", missing)
    }

    private var lastSevenDays: [DayMetrics] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let from = calendar.date(byAdding: .day, value: -6, to: start) else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let first = formatter.string(from: from)
        let last = formatter.string(from: start)
        return store.band.days.filter { $0.dateKey >= first && $0.dateKey <= last }
    }

    private var averageSleepText: String {
        let values = lastSevenDays.compactMap { $0.sleepHours > 0 ? $0.sleepHours : nil }
        guard !values.isEmpty else { return "—" }
        return String(format: "%.1f h", values.reduce(0, +) / Double(values.count))
    }

    private var weeklyStepsText: String {
        let values = lastSevenDays.compactMap { $0.steps }
        guard !values.isEmpty else { return "—" }
        return values.reduce(0, +).formatted()
    }

    private var averageRHRText: String {
        let values = lastSevenDays.compactMap { $0.restingHR }
        guard !values.isEmpty else { return "—" }
        return String(format: "%.0f", values.reduce(0, +) / Double(values.count))
    }

    private var averageHRVText: String {
        let values = lastSevenDays.compactMap { $0.lnRMSSD.map { exp($0) } }
            .filter { $0.isFinite }
        guard !values.isEmpty else { return "—" }
        return String(format: "%.0f", values.reduce(0, +) / Double(values.count))
    }

    private func insightTile(_ label: String, value: String,
                             note: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(Color.appAccent)
                Text(label).foregroundStyle(Color.appMuted)
            }
            .font(.system(size: 10, weight: .medium))
            Text(value)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(Color.appFG)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(note)
                .font(.system(size: 10))
                .foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appRaised))
    }

    private func analyticsStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.appFG)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(Color.appMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Charts use recorded day metrics only; missing days remain missing rather
    /// than silently substituting preview numbers or a zero measurement.
    private var recentDays: [DayMetrics] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(trendWindow - 1), to: today) else {
            return []
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        let startKey = formatter.string(from: start)
        let endKey = formatter.string(from: today)
        return store.band.days
            .filter { $0.dateKey >= startKey && $0.dateKey <= endKey }
            .sorted { $0.dateKey < $1.dateKey }
    }

    private var trendsPanel: some View {
        Panel {
            SectionTitle(focusedMetric == "recovery" ? "Recovery history" : focusedMetric == "strain" ? "Strain history" : "Sleep · Recovery · Strain")
            Picker("Chart period", selection: $trendWindow) {
                Text("7D").tag(7)
                Text("30D").tag(30)
                Text("90D").tag(90)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Chart period")
            Text("Last \(trendWindow) calendar days · \(recentDays.count) recorded days")
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)
            if focusedMetric != "strain" { recoveryTrend }
            if focusedMetric == "recovery" { recoveryVitalsTrends }
            if focusedMetric != "recovery" { strainTrend }
            if focusedMetric == nil {
            trendChart(
                title: "STEPS · RECORDED MINIMUM",
                unit: "steps",
                values: recentDays.map { $0.steps.map(Double.init) },
                color: .appAccent,
                upper: max(1000, Double(recentDays.compactMap { $0.steps }.max() ?? 1000))
            )
            trendChart(
                title: "RESTING HEART RATE",
                unit: "bpm",
                values: recentDays.map { $0.restingHR },
                color: .appWarn,
                upper: max(100, (recentDays.compactMap { $0.restingHR }.max() ?? 80) + 10)
            )
            trendChart(
                title: "HRV · RMSSD",
                unit: "ms",
                values: recentDays.map { $0.lnRMSSD.map { exp($0) } },
                color: .appGood,
                upper: max(100, (recentDays.compactMap { $0.lnRMSSD }.map { exp($0) }.max() ?? 70) + 10)
            )
            trendChart(
                title: "SLEEP",
                unit: "hours",
                values: recentDays.map { $0.sleepHours > 0 ? $0.sleepHours : nil },
                color: .appSleep,
                upper: max(10, store.settings.sleepNeedHours + 2)
            )
            }
        }
        .padding(.top, 12)
    }

    /// A point is scored against only the PRECEDING 30 days, never the
    /// future/current day. This avoids leaking today's HRV into its baseline.
    /// A missing seven-day personal baseline is a gap, not a zero bar.
    private var recoveryHistory: [(date: Date, score: Double?)] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        let daysByKey = Dictionary(uniqueKeysWithValues: store.band.days.map { ($0.dateKey, $0) })
        let end = calendar.startOfDay(for: Date())
        return (0..<trendWindow).compactMap { offset -> (date: Date, score: Double?)? in
            guard let date = calendar.date(byAdding: .day, value: offset - trendWindow + 1, to: end) else { return nil }
            let key = formatter.string(from: date)
            guard let day = daysByKey[key] else { return (date: date, score: nil) }
            let earlier = store.band.days
                .filter { $0.dateKey < key && $0.lnRMSSD != nil && $0.restingHR != nil }
                .sorted { $0.dateKey < $1.dateKey }
            let baseline = DailyAnalysis.baseline(from: Array(earlier.suffix(30)))
            let result = Recovery.score(
                lnRMSSD: day.lnRMSSD,
                rhr: day.restingHR,
                sleepHours: day.sleepHours > 0 ? day.sleepHours : nil,
                sleepNeedHours: store.settings.sleepNeedHours,
                baseline: baseline
            )
            return (date: date, score: result.score)
        }
    }

    private var recoveryTrend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RECOVERY")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Color.appFG)
                Spacer()
                Text("0–100%")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
            }
            let history = recoveryHistory
            if history.contains(where: { $0.score != nil }) {
                GeometryReader { geometry in
                    let slot = geometry.size.width / CGFloat(max(history.count, 1))
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<4, id: \.self) { grid in
                            Path { path in
                                let y = CGFloat(grid) * 52 + 12
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                            }
                            .stroke(Color.appLine, lineWidth: 1)
                        }
                        ForEach(Array(history.enumerated()), id: \.offset) { index, item in
                            let width = min(27.0, slot * 0.47)
                            let x = slot * (CGFloat(index) + 0.5)
                            let value = min(max(item.score ?? 0, 0), 100)
                            let barHeight = CGFloat(value / 100) * 154
                            let color: Color = value >= 67 ? Color(hex: 0x16E000) :
                                value >= 34 ? Color(hex: 0xFFDA00) : Color(hex: 0xFF1744)
                            if index == history.count - 1 {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.09))
                                    .frame(width: slot * 0.82, height: 198)
                                    .position(x: x, y: 99)
                            }
                            if item.score != nil {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color)
                                    .frame(width: width, height: max(2, barHeight))
                                    .position(x: x, y: 166 - barHeight / 2)
                                Text(String(format: "%.0f%%", value))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(color)
                                    .position(x: x, y: max(10, 154 - barHeight))
                            }
                            VStack(spacing: 2) {
                                Text(item.date.formatted(.dateTime.weekday(.abbreviated)))
                                Text(item.date.formatted(.dateTime.day()))
                            }
                            .font(.system(size: 9))
                            .foregroundStyle(Color.appMuted)
                            .position(x: x, y: 184)
                        }
                    }
                }
                .frame(height: 198)
            } else {
                Hint("Recovery history needs 7 earlier measured days with HRV and resting HR. Missing days are not invented.")
            }
            Hint("Green ≥67% · Yellow 34–66% · Red <34%. Estimates from your recorded data, not WHOOP's proprietary score.")
        }
        .padding(.top, 10)
    }

    // Recovery drill-in mirrors the weekly WHOOP trends without fabricating
    // physiological values that the Gen5 daily archive does not contain.
    private var recoveryVitalsTrends: some View {
        VStack(alignment: .leading, spacing: 12) {
            weeklyRecoveryCard(
                title: "HEART RATE VARIABILITY",
                values: recentDays.map { $0.lnRMSSD.map { exp($0) } },
                unit: "ms",
                color: .appAccent,
                maximum: 110
            )
            weeklyRecoveryCard(
                title: "RESTING HEART RATE",
                values: recentDays.map { $0.restingHR },
                unit: "bpm",
                color: .appAccent,
                maximum: 110
            )
            weeklyRecoveryCard(
                title: "SLEEP PERFORMANCE",
                values: recentDays.map {
                    $0.sleepHours > 0
                        ? min(100, $0.sleepHours / max(1, store.settings.sleepNeedHours) * 100)
                        : nil
                },
                unit: "%",
                color: .appSleep,
                maximum: 100
            )
            VStack(alignment: .leading, spacing: 6) {
                Text("RESPIRATORY RATE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appFG)
                Hint("Weekly respiratory rate is not present in the stored daily records yet. A validated dated source is needed before plotting this chart.")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.appRaised))
            Hint("Sleep performance is estimated as recorded sleep divided by your configured sleep need, capped at 100%; it is not WHOOP's proprietary sleep score.")
        }
        .padding(.top, 12)
    }

    private func weeklyRecoveryCard(title: String, values: [Double?],
                                    unit: String, color: Color,
                                    maximum: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Color.appFG)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(recentDays.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 4) {
                        if index < values.count, let value = values[index], value.isFinite {
                            Text(String(format: unit == "%" ? "%.0f%%" : "%.0f", value))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color)
                                .frame(height: max(3, CGFloat(min(max(value, 0), maximum) / maximum) * 115))
                        } else {
                            Text("—")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.appMuted)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.appLine)
                                .frame(height: 3)
                        }
                        Text(String(day.dateKey.suffix(2)))
                            .font(.system(size: 9))
                            .foregroundStyle(Color.appMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 150, alignment: .bottom)
            Text("Last \(trendWindow) days · \(unit) · missing days stay blank")
                .font(.system(size: 10))
                .foregroundStyle(Color.appMuted)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appRaised))
    }

    private var strainTrend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STRAIN")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Color.appFG)
                Spacer()
                Text("0–21")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
            }
            let history = strainHistory
            if history.contains(where: { $0.strain != nil }) {
                GeometryReader { geometry in
                    let slot = geometry.size.width / CGFloat(max(history.count, 1))
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<4, id: \.self) { grid in
                            Path { path in
                                let y = CGFloat(grid) * 52 + 12
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                            }
                            .stroke(Color.appLine, lineWidth: 1)
                        }
                        ForEach(Array(history.enumerated()), id: \.offset) { index, item in
                            let width = min(27.0, slot * 0.47)
                            let x = slot * (CGFloat(index) + 0.5)
                            let value = min(max(item.strain ?? 0, 0), 21)
                            let barHeight = CGFloat(value / 21) * 154
                            if index == history.count - 1 {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.09))
                                    .frame(width: slot * 0.82, height: 198)
                                    .position(x: x, y: 99)
                            }
                            if item.strain != nil {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(hex: 0x009FEE))
                                    .frame(width: width, height: max(2, barHeight))
                                    .position(x: x, y: 166 - barHeight / 2)
                                Text(String(format: "%.1f", value))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0x009FEE))
                                    .position(x: x, y: max(10, 154 - barHeight))
                            }
                            VStack(spacing: 2) {
                                Text(item.date.formatted(.dateTime.weekday(.abbreviated)))
                                Text(item.date.formatted(.dateTime.day()))
                            }
                            .font(.system(size: 9))
                            .foregroundStyle(Color.appMuted)
                            .position(x: x, y: 184)
                        }
                    }
                }
                .frame(height: 198)
            } else {
                Hint("No measured daily strain available in this period.")
            }
            Hint("Daily strain from recorded band samples. Missing days are left blank.")
        }
        .padding(.top, 12)
    }

    private var strainHistory: [(date: Date, strain: Double?)] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        let values = Dictionary(uniqueKeysWithValues: store.band.days.map { ($0.dateKey, $0.strain) })
        let end = calendar.startOfDay(for: Date())
        return (0..<trendWindow).compactMap { offset -> (date: Date, strain: Double?)? in
            guard let date = calendar.date(byAdding: .day, value: offset - trendWindow + 1, to: end) else { return nil }
            return (date: date, strain: values[formatter.string(from: date)] ?? nil)
        }
    }

    private func trendChart(title: String, unit: String, values: [Double?],
                            color: Color, upper: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).foregroundStyle(Color.appFG)
                Spacer()
                Text(unit).foregroundStyle(Color.appMuted)
            }
            .font(.system(size: 12))
            if values.compactMap({ $0 }).count >= 2 {
                SparseLineChart(
                    values: values,
                    color: color,
                    minY: 0,
                    maxY: upper,
                    height: 105,
                    xLabels: [recentDays.first?.dateKey ?? "", recentDays.last?.dateKey ?? ""]
                )
                Text("Missing days stay blank; no values are interpolated.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.appMuted)
            } else {
                Hint("At least two measured days are needed to draw this trend.")
            }
        }
        .padding(.top, 10)
    }

    private var baselinePanel: some View {
        Panel {
            SectionTitle("Baseline progress")
            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { day in
                    let filled = day <= filledDays
                    Text("\(day)")
                        .font(.system(size: 11))
                        .foregroundStyle(filled ? Color(hex: 0x08130C) : Color.appMuted)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 9).fill(filled ? Color.appGood : Color.appRaised))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(filled ? Color.appGood : Color.appLine, lineWidth: 1))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Hint("\(filledDays)/7 scored days. The small number under each metric is your comparison value — it stays absent until there is history to compare against, which is the whole point of a personal baseline.")
        }
        .padding(.top, 12)
    }

    private var filledDays: Int {
        demo ? 1 : min(store.recordedDayCount, 7)
    }
}