import ActivityKit
import Foundation

/// Bridges the existing workout recorder and live BLE HR into ActivityKit.
/// ActivityKit updates are serialized and opportunistic: iOS may still suspend
/// the app in background when no permitted BLE/location event is waking it.
@MainActor
final class WorkoutLiveActivityController {
    static let shared = WorkoutLiveActivityController()
    private var active: Activity<WorkoutActivityAttributes>?
    private var lastUpdate = Date.distantPast
    private var lastState: WorkoutActivityAttributes.ContentState?
    private var pendingTask: Task<Void, Never>?
    private init() {}

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = pendingTask
        pendingTask = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    func start(session: WorkoutSession, isConnected: Bool = true) {
        let now = Date()
        let initial = WorkoutActivityAttributes.ContentState(
            heartRate: nil, zone: nil, distanceMeters: session.hasGPS ? 0 : nil,
            paceSecondsPerKilometer: nil, steps: nil, stepsObservedAt: nil,
            elapsedSeconds: 0, timerAnchor: now, isConnected: isConnected,
            estimatedStrain: nil, paused: false, lastSampleAt: now
        )
        if lastState == nil {
            lastState = initial
            lastUpdate = .distantPast
        }
        enqueue { [weak self] in
            guard let self else { return }
            _ = await self.ensureActivity(session: session, state: initial)
        }
    }

    /// Run inside the serialized queue. Later eligible updates may retry
    /// a rejected start or adopt an already-existing card.
    private func ensureActivity(session: WorkoutSession,
                                state: WorkoutActivityAttributes.ContentState) async -> Activity<WorkoutActivityAttributes>? {
        let id = session.id.uuidString
        if let existing = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.attributes.sessionID == id }) {
            active = existing
            return existing
        }
        active = nil
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
        for old in Activity<WorkoutActivityAttributes>.activities where old.attributes.sessionID != id {
            await old.end(nil, dismissalPolicy: .immediate)
        }
        if let existing = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.attributes.sessionID == id }) {
            active = existing
            return existing
        }
        let attributes = WorkoutActivityAttributes(
            sessionID: id, activityName: session.activityLabel,
            startedAt: session.startedAt, hasGPS: session.hasGPS, activityKind: session.activityKind
        )
        do {
            let created = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(120)),
                pushType: nil
            )
            active = created
            return created
        } catch {
            return nil
        }
    }

    func update(session: WorkoutSession?, phase: WorkoutPhase, heartRate: Int?, maxHeartRate: Double?,
                distanceMeters: Double, elapsedSeconds: Int, steps: Int? = nil,
                stepsObservedAt: Date? = nil, isConnected: Bool = true,
                estimatedStrain: Double? = nil, estimatedActiveCalories: Int? = nil,
                stepsAreEstimated: Bool = false) {
        guard let session, phase == .recording || phase == .paused else { return }
        let now = Date()
        let bpm = isConnected ? heartRate.flatMap { (35...220).contains($0) ? $0 : nil } : nil
        let zone: Int? = {
            guard let bpm, let maxHeartRate, maxHeartRate.isFinite, maxHeartRate > 0 else { return nil }
            let ratio = min(1, max(0, Double(bpm) / maxHeartRate))
            return min(5, max(1, Int(ratio / 0.1) - 4))
        }()
        let pace: Int? = session.hasGPS && distanceMeters >= 100 && elapsedSeconds > 0
            ? Int(Double(elapsedSeconds) / (distanceMeters / 1000.0)) : nil
        let paused = phase == .paused
        let clampedElapsed = max(0, elapsedSeconds)
        let anchor = paused ? nil : now.addingTimeInterval(-Double(clampedElapsed))
        let state = WorkoutActivityAttributes.ContentState(
            heartRate: bpm, zone: zone,
            distanceMeters: session.hasGPS ? max(0, distanceMeters) : nil,
            paceSecondsPerKilometer: pace, steps: steps, stepsObservedAt: stepsObservedAt,
            elapsedSeconds: clampedElapsed, timerAnchor: anchor, isConnected: isConnected,
            estimatedStrain: estimatedStrain, estimatedActiveCalories: estimatedActiveCalories,
            paused: paused, lastSampleAt: now, stepsAreEstimated: stepsAreEstimated
        )
        let urgentTransition = lastState?.paused != state.paused
            || lastState?.isConnected != state.isConnected
            || lastState?.steps != state.steps
            || lastState?.stepsAreEstimated != state.stepsAreEstimated
            || (!stepsAreEstimated && lastState?.stepsObservedAt != state.stepsObservedAt)
        guard urgentTransition || now.timeIntervalSince(lastUpdate) >= 5 else { return }
        lastUpdate = now
        lastState = state
        enqueue { [weak self] in
            guard let self else { return }
            guard let active = await self.ensureActivity(session: session, state: state) else { return }
            await active.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(120)))
        }
    }

    /// BLE history may finish syncing while the workout screen is backgrounded.
    /// Keep the running workout card synchronized without starting a second one.
    func updateStepCount(_ steps: Int?, observedAt: Date?) {
        guard var state = lastState else { return }
        guard state.steps != steps || state.stepsObservedAt != observedAt else { return }
        state.steps = steps
        state.stepsObservedAt = observedAt
        lastState = state
        let now = Date()
        enqueue { [weak self] in
            guard let self, let active = self.active else { return }
            await active.update(ActivityContent(state: state, staleDate: now.addingTimeInterval(120)))
        }
    }

    func end() {
        active = nil
        lastState = nil
        lastUpdate = .distantPast
        enqueue {
            let targets = Activity<WorkoutActivityAttributes>.activities
            for activity in targets {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
