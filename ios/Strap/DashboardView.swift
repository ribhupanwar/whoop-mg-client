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
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Recovery")
                        .foregroundStyle(Color.appFG)
                    Spacer()
                    Text(store.band.recovery.score.map { String(format: "%.0f%%", $0) } ?? "—")
                        .foregroundStyle(Color.appGood)
                }
                .font(.system(size: 13, weight: .medium))
                if let reason = store.band.recovery.reason {
                    Hint(reason)
                } else {
                    Hint("Latest baseline-relative recovery only. Historical recovery is not stored per day, so no fabricated trend is drawn.")
                }
            }
            .padding(.top, 8)
        }
        .padding(.top, 12)
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