import ActivityKit
import Foundation
import UIKit

/// On-device, best-effort automatic walking card. We never count steps from
/// GPS/HR and never start a new card from stale historical backfill.
@MainActor
final class CapturedStepsLiveActivityController {
    static let shared = CapturedStepsLiveActivityController()
    private var activity: Activity<CapturedStepsActivityAttributes>?
    private var lastState: CapturedStepsActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast
    private init() {}

    func reconcile(_ snapshot: StepWidgetSnapshot, workoutActive: Bool) {
        if workoutActive {
            end()
            return
        }
        let now = Date()
        let activeWalk: Bool = {
            guard snapshot.connectedAtWrite, let increase = snapshot.lastIncreaseAt else { return false }
            let age = now.timeIntervalSince(increase)
            return age >= 0 && age <= 120
        }()
        if activity == nil {
            activity = Activity<CapturedStepsActivityAttributes>.activities.first
        }
        if !activeWalk {
            // A stale card is not an always-on pedometer. Background suspension
            // can delay cleanup; the ActivityContent staleDate also expires.
            if !snapshot.connectedAtWrite || snapshot.lastIncreaseAt == nil
                || (snapshot.lastIncreaseAt.map { now.timeIntervalSince($0) > 4 * 60 } ?? true) {
                end()
            }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let count = snapshot.recordedMinimum,
              let observedAt = snapshot.lastObservedAt else { return }

        let state = CapturedStepsActivityAttributes.ContentState(
            recordedMinimum: count, lastObservedAt: observedAt,
            isConnected: snapshot.connectedAtWrite
        )
        if let active = activity {
            guard state != lastState || now.timeIntervalSince(lastUpdate) >= 60 else { return }
            lastState = state
            lastUpdate = now
            Task { await active.update(ActivityContent(state: state, staleDate: observedAt.addingTimeInterval(120))) }
        } else if UIApplication.shared.applicationState == .active {
            do {
                let created = try Activity.request(
                    attributes: CapturedStepsActivityAttributes(startedAt: now),
                    content: ActivityContent(state: state, staleDate: observedAt.addingTimeInterval(120)),
                    pushType: nil
                )
                activity = created
                lastState = state
                lastUpdate = now
            } catch {
                // User/iOS can decline a Live Activity. Home and widgets still work.
            }
        }
    }

    func end() {
        activity = nil
        lastState = nil
        let cards = Activity<CapturedStepsActivityAttributes>.activities
        Task {
            for card in cards { await card.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
