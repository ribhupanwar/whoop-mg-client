import ActivityKit
import SwiftUI
import WidgetKit

struct StrapWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.06, green: 0.08, blue: 0.11))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(hrText(context), systemImage: "heart.fill")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsedTimerView(context)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(statusLabel(context))
                        Spacer()
                        Text(distanceText(context.state.distanceMeters))
                        Spacer()
                        Text(paceText(context.state.paceSecondsPerKilometer))
                        if let steps = context.state.steps {
                            Spacer()
                            Label(steps.formatted(), systemImage: "figure.walk")
                        }
                        if let strain = context.state.estimatedStrain {
                            Spacer()
                            Text(String(format: "%.1f STRAIN", strain))
                        }
                    }
                    .font(.caption)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill").foregroundStyle(.orange)
                    Text(hrText(context)).monospacedDigit()
                }
            } compactTrailing: {
                if context.isStale || context.state.isConnected == false {
                    Text("STALE").font(.caption2.bold()).foregroundStyle(.orange)
                } else if let steps = context.state.steps {
                    Label(steps.formatted(), systemImage: "figure.walk")
                        .monospacedDigit()
                } else {
                    elapsedTimerView(context).monospacedDigit()
                }
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(.orange)
            }
        }
    }
}

private struct WorkoutLockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                Image(systemName: "heart.fill").foregroundStyle(.orange)
                Text(hrText(context))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("bpm").font(.caption).foregroundStyle(.secondary)
                Spacer()
                elapsedTimerView(context)
                    .font(.system(.headline, design: .rounded)).monospacedDigit()
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.blue.opacity(0.35), in: Capsule())
            }
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { z in
                    Capsule().fill(z == context.state.zone ? Color.orange : Color.gray.opacity(0.45))
                        .frame(height: 6)
                }
            }
            HStack {
                Text(statusLabel(context))
                    .font(.caption2.bold()).foregroundStyle(.orange)
                Spacer()
                if let strain = context.state.estimatedStrain {
                    Text(String(format: "%.1f EST. STRAIN", strain))
                        .font(.caption2.bold()).foregroundStyle(.secondary)
                }
            }
            HStack {
                VStack {
                    Text(distanceText(context.state.distanceMeters)).font(.headline)
                    Text("DISTANCE").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
                Divider()
                VStack(spacing: 2) {
                    Text("STRAP").font(.headline.bold()).tracking(2)
                    if let steps = context.state.steps {
                        Text("\(steps.formatted()) STEPS").font(.caption2).monospacedDigit()
                    }
                }.frame(maxWidth: .infinity)
                Divider()
                VStack {
                    Text(paceText(context.state.paceSecondsPerKilometer)).font(.headline)
                    Text("PACE / KM").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

private func hrText(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> String {
    guard !context.isStale, context.state.isConnected != false else { return "—" }
    return context.state.heartRate.map(String.init) ?? "—"
}

private func statusLabel(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> String {
    if context.state.paused {
        return context.state.isConnected == false ? "PAUSED · DISCONNECTED" : "PAUSED"
    }
    if context.state.isConnected == false { return "BAND DISCONNECTED" }
    if context.isStale { return "STALE · NO FRESH HR" }
    return "ZONE \(context.state.zone.map(String.init) ?? "—")"
}

@ViewBuilder
private func elapsedTimerView(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
    if context.state.paused {
        if let seconds = context.state.elapsedSeconds {
            Text(formattedElapsed(seconds))
        } else {
            Text("—")
        }
    } else if let anchor = context.state.timerAnchor {
        Text(anchor, style: .timer)
    } else {
        Text(context.attributes.startedAt, style: .timer)
    }
}

private func formattedElapsed(_ totalSeconds: Int) -> String {
    let clamped = max(0, totalSeconds)
    let hours = clamped / 3600
    let minutes = (clamped % 3600) / 60
    let seconds = clamped % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}
private func distanceText(_ meters: Double?) -> String {
    guard let meters else { return "—" }
    return String(format: "%.2f km", meters / 1000)
}
private func paceText(_ seconds: Int?) -> String {
    guard let seconds, seconds > 0, seconds < 3600 else { return "—" }
    return String(format: "%02d:%02d /km", seconds / 60, seconds % 60)
}

@main
struct StrapWorkoutWidgetBundle: WidgetBundle {
    var body: some Widget {
        StrapWorkoutWidget()
        StrapCapturedStepsLiveWidget()
        StrapStepsHomeWidget()
        StrapHealthHomeWidget()
        StrapSingleHealthWidget(metric: .recovery)
        StrapSingleHealthWidget(metric: .sleep)
        StrapSingleHealthWidget(metric: .strain)
        StrapSingleHealthWidget(metric: .battery)
        StrapSingleHealthWidget(metric: .stress)
    }
}
