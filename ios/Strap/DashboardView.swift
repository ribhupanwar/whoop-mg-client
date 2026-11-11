import SwiftUI

/// Dashboard tab — the exact same metric rows as Home's My Dashboard
/// (shared component), plus the customize sheet and baseline progress.
struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showCustomize = false
    @State private var trendWindow = 7

    private var demo: Bool { store.isPreview }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("My Dashboard")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Button {
                        showCustomize = true
                    } label: {
                        Text("CUSTOMIZE ✎")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(0.7)
                            .foregroundStyle(Color.appAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.appRaised))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.appLine, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 10)

                DashboardRows()
                trendsPanel
                baselinePanel
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCustomize) {
            DashboardCustomizeSheet()
                .environmentObject(store)
        }
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
            SectionTitle("Sleep · Recovery · Strain")
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
            trendChart(
                title: "Sleep",
                unit: "hours",
                values: recentDays.map { $0.sleepHours > 0 ? $0.sleepHours : nil },
                color: .appSleep,
                upper: max(10, store.settings.sleepNeedHours + 2)
            )
            trendChart(
                title: "Strain",
                unit: "0–21",
                values: recentDays.map { $0.strain },
                color: .appAccent,
                upper: 21
            )
            recoveryTrend
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

    private func trendChart(title: String, unit: String, values: [Double?],
                            color: Color, upper: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).foregroundStyle(Color.appFG)
                Spacer()
                Text(unit).foregroundStyle(Color.appMuted)
            }
            .font(.system(size: 12))
            if values.count >= 2 && values.allSatisfy({ $0 != nil }) {
                LineChart(values: values.compactMap { $0 },
                          color: color, minY: 0, maxY: upper, height: 105,
                          xLabels: [recentDays.first?.dateKey ?? "", recentDays.last?.dateKey ?? ""])
            } else {
                Hint("Not enough continuous recorded data to draw this trend.")
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