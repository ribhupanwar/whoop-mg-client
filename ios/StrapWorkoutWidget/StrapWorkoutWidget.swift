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
                    secondaryMetric(context)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Text(statusLabel(context)).lineLimit(1)
                        Spacer()
                        elapsedTimerView(context).monospacedDigit()
                        Spacer()
                        Text(strainText(context.state.estimatedStrain) + " EST. STRAIN")
                            .lineLimit(1).minimumScaleFactor(0.7)
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
                } else if context.state.paused {
                    elapsedTimerView(context).monospacedDigit()
                } else {
                    secondaryMetric(context)
                }
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(.orange)
            }
        }
    }
}

private struct WorkoutLockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>
    private var zone: Int? {
        guard !context.isStale, context.state.isConnected != false else { return nil }
        return context.state.zone
    }
    private var zoneColor: Color {
        switch zone {
        case 1: return Color(red: 0.45, green: 0.67, blue: 0.88)
        case 2: return .mint
        case 3: return .yellow
        case 4: return Color(red: 1, green: 0.66, blue: 0.36)
        case 5: return .red
        default: return .gray
        }
    }
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: activitySymbol(context.attributes.displayKind))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(zoneColor)
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.activityName).font(.subheadline.bold()).lineLimit(1)
                    Text("STRAP · Live Activity").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "waveform").foregroundStyle(.secondary)
            }
            HStack(alignment: .center, spacing: 5) {
                Image(systemName: "heart.fill").foregroundStyle(zoneColor)
                Text(hrText(context))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("bpm").font(.caption).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "stopwatch").foregroundStyle(.cyan)
                    elapsedTimerView(context)
                        .font(.system(.headline, design: .rounded)).monospacedDigit()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(red: 0.08, green: 0.21, blue: 0.32), in: Capsule())
            }
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { z in
                    Capsule()
                        .fill(z == zone ? zoneColor : Color.gray.opacity(0.55))
                        .frame(height: 4)
                        .overlay {
                            if z == zone {
                                Circle().fill(.white).frame(width: 10, height: 10)
                            }
                        }
                }
            }
            .accessibilityHidden(true)
            HStack {
                Text(statusLabel(context))
                    .font(.caption2.bold()).tracking(1).foregroundStyle(zoneColor)
                Spacer()
                if context.attributes.displayKind != .other {
                    Text(strainText(context.state.estimatedStrain) + " EST. STRAIN")
                        .font(.caption2.bold()).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                switch context.attributes.displayKind {
                case .running:
                    if context.attributes.hasGPS {
                        metric(distanceText(context.state.distanceMeters), label: "DISTANCE")
                        Divider()
                        metric(paceText(context.state.paceSecondsPerKilometer), label: "PACE / KM")
                        Divider()
                    } else {
                        metric(stepText(context), label: "RECORDED STEPS")
                        Divider()
                    }
                    metric(calorieText(context.state.estimatedActiveCalories), label: "EST. ACTIVE KCAL")
                case .walking:
                    metric(stepText(context), label: "RECORDED STEPS")
                    Divider()
                    if context.attributes.hasGPS {
                        metric(distanceText(context.state.distanceMeters), label: "DISTANCE")
                        Divider()
                    }
                    metric(calorieText(context.state.estimatedActiveCalories), label: "EST. ACTIVE KCAL")
                case .other:
                    metric(calorieText(context.state.estimatedActiveCalories), label: "EST. ACTIVE KCAL")
                    Divider()
                    metric(strainText(context.state.estimatedStrain), label: "EST. STRAIN")
                }
            }
            if context.attributes.displayKind == .walking ||
                (context.attributes.displayKind == .running && !context.attributes.hasGPS) {
                Text(stepFreshnessText(context))
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background {
            LinearGradient(colors: [zoneColor.opacity(zone == nil ? 0 : 0.29),
                                    Color(red: 0.06, green: 0.08, blue: 0.11)],
                           startPoint: .topLeading, endPoint: .trailing)
        }
    }
    private func metric(_ value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            Text(label).font(.caption2.bold()).tracking(0.7).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity)
    }
}

private func activitySymbol(_ kind: WorkoutActivityAttributes.DisplayKind) -> String {
    switch kind {
    case .running: return "figure.run"
    case .walking: return "figure.walk"
    case .other: return "dumbbell.fill"
    }
}

private func strainText(_ value: Double?) -> String {
    guard let value, value.isFinite, (0...21).contains(value) else { return "—" }
    return String(format: "%.1f", value)
}

private func stepText(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> String {
    context.state.steps?.formatted() ?? "—"
}

private func stepFreshnessText(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> String {
    guard let observed = context.state.stepsObservedAt, context.state.steps != nil else {
        return "Daily steps · awaiting band history"
    }
    return "Daily steps · recorded " + observed.formatted(date: .omitted, time: .shortened)
}

@ViewBuilder
private func secondaryMetric(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
    if context.isStale || context.state.isConnected == false {
        Text("STALE").font(.caption2.bold()).foregroundStyle(.orange)
    } else if context.state.paused {
        elapsedTimerView(context).monospacedDigit()
    } else {
        switch context.state.compactMetric(for: context.attributes.displayKind, hasGPS: context.attributes.hasGPS) {
        case .steps:
            Label(stepText(context), systemImage: "figure.walk")
                .foregroundStyle(.mint).accessibilityLabel("Recorded daily steps")
                .accessibilityValue(stepText(context))
        case .calories:
            Label(calorieText(context.state.estimatedActiveCalories), systemImage: "flame.fill")
                .foregroundStyle(.orange).accessibilityLabel("Estimated active calories")
                .accessibilityValue(calorieText(context.state.estimatedActiveCalories))
        case .pace:
            Text(paceText(context.state.paceSecondsPerKilometer))
        case .distance:
            Text(distanceText(context.state.distanceMeters))
        case .strain:
            Text(strainText(context.state.estimatedStrain) + " S")
                .foregroundStyle(.cyan).accessibilityLabel("Estimated workout strain")
                .accessibilityValue(strainText(context.state.estimatedStrain))
        case .elapsed:
            elapsedTimerView(context)
        }
    }
}

private func calorieText(_ calories: Int?) -> String {
    calories.map { "\($0) kcal" } ?? "—"
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
