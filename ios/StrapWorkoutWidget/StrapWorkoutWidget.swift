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
                    Label(hrText(context.state.heartRate), systemImage: "heart.fill")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("ZONE \(context.state.zone.map(String.init) ?? "—")")
                        Spacer()
                        Text(distanceText(context.state.distanceMeters))
                        Spacer()
                        Text(paceText(context.state.paceSecondsPerKilometer))
                    }
                    .font(.caption)
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill").foregroundStyle(.orange)
                    Text(hrText(context.state.heartRate)).monospacedDigit()
                }
            } compactTrailing: {
                Text(context.attributes.startedAt, style: .timer).monospacedDigit()
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
                Text(hrText(context.state.heartRate))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("bpm").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(context.attributes.startedAt, style: .timer)
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
            Text(context.state.paused ? "PAUSED" : "ZONE \(context.state.zone.map(String.init) ?? "—")")
                .font(.caption2.bold()).foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                VStack {
                    Text(distanceText(context.state.distanceMeters)).font(.headline)
                    Text("DISTANCE").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
                Divider()
                Text("STRAP").font(.headline.bold()).tracking(2).frame(maxWidth: .infinity)
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

private func hrText(_ value: Int?) -> String { value.map(String.init) ?? "—" }
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
    }
}
