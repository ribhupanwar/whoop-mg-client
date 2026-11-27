import ActivityKit
import SwiftUI
import WidgetKit

/// Timeline-based Home Screen widget. WidgetKit owns refresh cadence; no
/// misleading 1 Hz/background promise and no access to app-private storage.
struct StrapStepsHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: StepWidgetSnapshot.widgetKind,
                            provider: StepTimelineProvider()) { entry in
            StrapStepsHomeView(entry: entry)
        }
        .configurationDisplayName("Captured Steps")
        .description("Verified band-recorded minimum, last-sync time and stale status.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct StepTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: StepWidgetSnapshot?
}

private struct StepTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StepTimelineEntry {
        StepTimelineEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (StepTimelineEntry) -> Void) {
        completion(StepTimelineEntry(date: Date(), snapshot: StepWidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepTimelineEntry>) -> Void) {
        let now = Date()
        let entry = StepTimelineEntry(date: now, snapshot: StepWidgetSnapshot.load())
        // Explicitly bounded, best-effort refresh; iOS may delay or coalesce it.
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

private struct StrapStepsHomeView: View {
    let entry: StepTimelineEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .foregroundStyle(.orange)
                Text("STEPS").font(.caption.bold()).tracking(1.5)
            }
            Spacer(minLength: 2)
            Text((entry.snapshot?.isForToday == true ? entry.snapshot?.recordedMinimum : nil).map { $0.formatted() } ?? "—")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("RECORDED MINIMUM")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            if let snapshot = entry.snapshot, snapshot.isForToday, let last = snapshot.lastObservedAt {
                Text(snapshot.isFresh ? "BAND SYNC" : "LAST BAND SYNC")
                    .font(.caption2.bold())
                    .foregroundStyle(snapshot.isFresh ? .green : .orange)
                Text(last, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("NEEDS BAND HISTORY SYNC")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            Color(red: 0.06, green: 0.08, blue: 0.11)
        }
        .foregroundStyle(.white)
    }
}

/// Non-workout walking Live Activity. Only activated by a fresh verified
/// band-counter increase when the app is running and ActivityKit permits it.
struct StrapCapturedStepsLiveWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CapturedStepsActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "figure.walk").foregroundStyle(.orange)
                    .font(.system(size: 25, weight: .bold))
                VStack(alignment: .leading) {
                    Text(context.state.recordedMinimum.formatted())
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("CAPTURED STEPS · MINIMUM")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    if !context.isStale, let bpm = context.state.heartRate {
                        Text("\(bpm) BPM").font(.caption.bold()).foregroundStyle(.orange)
                    }
                    if !context.isStale, let strain = context.state.estimatedStrain {
                        Text(String(format: "%.1f EST. STRAIN", strain))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(context.state.lastObservedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(context.isStale ? "STALE" : (context.state.isConnected ? "BAND" : "DISCONNECTED"))
                    .font(.caption2.bold())
            }
            .foregroundStyle(.white).padding(16)
            .activityBackgroundTint(Color(red: 0.06, green: 0.08, blue: 0.11))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Steps", systemImage: "figure.walk").foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.recordedMinimum.formatted())
                        .font(.headline).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("RECORDED MINIMUM").font(.caption2)
                        Spacer()
                        if !context.isStale, let bpm = context.state.heartRate {
                            Text("\(bpm) BPM").font(.caption2)
                        }
                        if !context.isStale, let strain = context.state.estimatedStrain {
                            Text(String(format: "%.1f EST STRAIN", strain)).font(.caption2)
                        }
                        Spacer()
                        if context.isStale {
                            Text("STALE").font(.caption2.bold())
                        } else {
                            Text(context.state.lastObservedAt, style: .relative).font(.caption2)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.walk").foregroundStyle(.orange)
            } compactTrailing: {
                Text(context.isStale ? "STALE" : context.state.recordedMinimum.formatted())
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "figure.walk").foregroundStyle(.orange)
            }
        }
    }
}


struct StrapHealthHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HealthWidgetSnapshot.widgetKind, provider: HealthTimelineProvider()) { entry in
            HealthSnapshotView(entry: entry)
        }
        .configurationDisplayName("Daily Health")
        .description("Opt-in saved recovery, sleep, strain and battery snapshot.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct HealthTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: HealthWidgetSnapshot?
}
private struct HealthTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HealthTimelineEntry { .init(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (HealthTimelineEntry) -> Void) {
        completion(.init(date: Date(), snapshot: HealthWidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthTimelineEntry>) -> Void) {
        let now = Date()
        let snapshot = HealthWidgetSnapshot.load()
        var entries = [HealthTimelineEntry(date: now, snapshot: snapshot)]
        if let snapshot {
            entries += snapshot.refreshBoundaries(after: now).map { .init(date: $0, snapshot: snapshot) }
        }
        if let midnight = Calendar.current.dateInterval(of: .day, for: now)?.end {
            entries.append(.init(date: midnight, snapshot: nil))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}
private struct HealthSnapshotView: View {
    let entry: HealthTimelineEntry
    private var current: HealthWidgetSnapshot? {
        guard let snapshot = entry.snapshot, snapshot.isForDay(entry.date) else { return nil }
        return snapshot
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STRAP · DAILY HEALTH").font(.caption2.bold()).tracking(0.5)
            HStack {
                metric("SLEEP", current?.sleep, suffix: "%", color: .cyan)
                metric("RECOVERY", current?.recovery, suffix: "%", color: .green)
            }
            HStack {
                metric("STRAIN", current?.strain, suffix: "", color: .blue)
                metric("BATTERY", current.flatMap { HealthWidgetMetric.battery.value(in: $0, at: entry.date) }, suffix: "%", color: .white)
            }
            if let snapshot = current {
                Text("SAVED " + snapshot.savedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            } else {
                Text("ENABLE IN MORE · APP PREFERENCES").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .privacySensitive()
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { Color(red: 0.06, green: 0.08, blue: 0.11) }
    }
    private func metric(_ label: String, _ value: Double?, suffix: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            Text(value.map { String(format: suffix.isEmpty ? "%.1f" : "%.0f", $0) + suffix } ?? "—")
                .font(.system(size: 19, weight: .bold)).monospacedDigit()
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


struct StrapSingleHealthWidget: Widget {
    let metric: HealthWidgetMetric

    // Widget requires a public zero-argument initializer for discovery.
    // The explicit metric initializer is used for each configured widget kind.
    init() { self.metric = .sleep }
    init(metric: HealthWidgetMetric) { self.metric = metric }
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: metric.kind, provider: HealthTimelineProvider()) { entry in
            SingleHealthMetricView(metric: metric, entry: entry)
        }
        .configurationDisplayName(metric.title)
        .description("Saved STRAP metric with date and availability; opt-in required.")
        .supportedFamilies([.systemSmall])
    }
}

private struct SingleHealthMetricView: View {
    let metric: HealthWidgetMetric
    let entry: HealthTimelineEntry
    private var color: Color {
        switch metric {
        case .sleep: return .cyan
        case .recovery: return .green
        case .strain: return .blue
        case .battery: return .white
        case .stress: return .orange
        }
    }
    var body: some View {
        let value = entry.snapshot.flatMap { metric.value(in: $0, at: entry.date) }
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.title.uppercased()).font(.caption2.bold()).tracking(1)
            Spacer(minLength: 2)
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 7)
                if let value {
                    Circle().trim(from: 0, to: CGFloat(min(1, max(0, value / metric.maximum))))
                        .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(value.map { String(format: metric.decimals == 1 ? "%.1f" : "%.0f", $0) + metric.suffix } ?? "—")
                    .font(.system(size: 25, weight: .bold)).monospacedDigit().minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: 78)
            Spacer(minLength: 2)
            if let snapshot = entry.snapshot, value != nil {
                Text("Saved " + snapshot.savedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("No current reading · Open STRAP to sync").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .privacySensitive()
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { Color(red: 0.06, green: 0.08, blue: 0.11) }
    }
}
