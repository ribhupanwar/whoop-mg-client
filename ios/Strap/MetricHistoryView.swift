import SwiftUI

/// Metric-specific dated history opened directly from a Home dashboard row.
/// Only stored measurements are plotted; unavailable days remain gaps.
struct MetricHistoryView: View {
    @EnvironmentObject private var store: AppStore
    let metric: DetailMetric
    @State private var window = 30

    private var ending: Date { Calendar.current.startOfDay(for: Date()) }

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
            return MetricTimeline.preview(ending: ending, count: min(window, 7))
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

    private var measuredCount: Int {
        points.filter { $0.value(metric) != nil }.count
    }

    var body: some View {
        Screen {
            Panel {
                SectionTitle(metric.title)
                Text("Recorded trend · missing measurements stay blank")
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appMuted)
                Picker("History period", selection: $window) {
                    Text("7D").tag(7)
                    Text("30D").tag(30)
                    Text("90D").tag(90)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("History period")
                Text("Last \(window) calendar days · \(measuredCount) recorded readings")
                    .font(StrapTypography.body(11))
                    .foregroundStyle(Color.appMuted)
                WeeklyMetricChart(
                    metric: metric,
                    points: points,
                    selectedKey: JournalStore.dayKey(for: ending)
                )
                .padding(.top, 12)
                Hint(historyNote)
            }
            Panel {
                SectionTitle("Daily history")
                ForEach(points.reversed()) { day in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(day.date.formatted(date: .complete, time: .omitted))
                                .font(StrapTypography.body(13, weight: .medium))
                                .foregroundStyle(Color.appFG)
                            Text(day.value(metric) == nil ? "No recorded reading" : "Recorded")
                                .font(StrapTypography.body(10))
                                .foregroundStyle(Color.appMuted)
                        }
                        Spacer()
                        Text(metric.text(day.value(metric)))
                            .font(StrapTypography.metric(15, weight: .regular))
                            .foregroundStyle(Color.appFG)
                    }
                    .padding(.vertical, 9)
                    Divider().overlay(Color.appLine)
                }
            }
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var historyNote: String {
        switch metric {
        case .calories:
            return "Activity calories are local estimates based on recorded heart rate and profile data; they are not WHOOP's full-day total."
        case .strength:
            return "Strength duration comes from saved activity logs. No duration is inferred when the log has no recorded time."
        case .zonesLow, .zonesHigh:
            return "Heart-rate zone time uses recorded awake heart-rate samples and saved activity sessions."
        case .recovery:
            return "Recovery is a local estimate using available recorded inputs and baseline days."
        case .sleepPerformance:
            return "Sleep performance is estimated from recorded sleep and configured sleep need."
        case .respiration:
            return "Respiratory rate is shown only when a dated validated value exists."
        default:
            return "This chart uses the saved daily values for this metric. It does not substitute missing readings."
        }
    }
}
