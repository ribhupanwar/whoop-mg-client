import ActivityKit
import Foundation

/// Bridges the existing workout recorder and live BLE HR into ActivityKit.
/// ActivityKit updates are opportunistic: iOS may suspend the app in background.
@MainActor
final class WorkoutLiveActivityController {
    static let shared = WorkoutLiveActivityController()
    private var active: Activity<WorkoutActivityAttributes>?
    private var lastUpdate = Date.distantPast
    private var lastState: WorkoutActivityAttributes.ContentState?
    private init() {}

    func start(session: WorkoutSession) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let id = session.id.uuidString
        if active?.attributes.sessionID == id { return }
        let attrs = WorkoutActivityAttributes(
            sessionID: id, activityName: session.activityLabel,
            startedAt: session.startedAt, hasGPS: session.hasGPS
        )
        let initial = WorkoutActivityAttributes.ContentState(
            heartRate: nil, zone: nil, distanceMeters: session.hasGPS ? 0 : nil,
            paceSecondsPerKilometer: nil, paused: false, lastSampleAt: Date()
        )
        Task {
            // Avoid duplicate cards after app recreation.
            for old in Activity<WorkoutActivityAttributes>.activities where old.attributes.sessionID != id {
                await old.end(nil, dismissalPolicy: .immediate)
            }
            if let existing = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.attributes.sessionID == id }) {
                active = existing
            } else {
                do {
                    active = try Activity.request(attributes: attrs, content: ActivityContent(state: initial, staleDate: Date().addingTimeInterval(120)), pushType: nil)
                } catch {
                    // ActivityKit can be disabled by system/user; workout continues normally.
                    return
                }
            }
            lastState = initial
            lastUpdate = .distantPast
        }
    }

    func update(session: WorkoutSession?, phase: WorkoutPhase, heartRate: Int?, maxHeartRate: Double?, distanceMeters: Double, elapsedSeconds: Int) {
        guard let session, let active, active.attributes.sessionID == session.id.uuidString else { return }
        guard phase == .recording || phase == .paused else { return }
        let now = Date()
        let bpm = heartRate.flatMap { (35...220).contains($0) ? $0 : nil }
        let zone: Int? = {
            guard let bpm, let maxHeartRate, maxHeartRate > 0 else { return nil }
            let ratio = Double(bpm) / maxHeartRate
            return min(5, max(1, Int(ratio / 0.1) - 4))
        }()
        let pace: Int? = session.hasGPS && distanceMeters >= 100 && elapsedSeconds > 0
            ? Int(Double(elapsedSeconds) / (distanceMeters / 1000.0)) : nil
        let state = WorkoutActivityAttributes.ContentState(
            heartRate: bpm, zone: zone,
            distanceMeters: session.hasGPS ? max(0, distanceMeters) : nil,
            paceSecondsPerKilometer: pace, paused: phase == .paused, lastSampleAt: now
        )
        // Rate-limit system updates, but always transmit pause/resume or HR changes after 5s.
        guard lastState?.paused != state.paused || now.timeIntervalSince(lastUpdate) >= 5 else { return }
        lastUpdate = now
        lastState = state
        Task { await active.update(ActivityContent(state: state, staleDate: now.addingTimeInterval(120))) }
    }

    func end() {
        let targets = Activity<WorkoutActivityAttributes>.activities
        active = nil
        lastState = nil
        Task {
            for activity in targets {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
