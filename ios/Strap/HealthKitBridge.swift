import Combine
import Foundation
import HealthKit

/// Optional, write-only export to Apple Health.
///
/// Only sessions the band actually measured are written, as workouts with
/// their real start and end. Nothing is read back, no estimate (VO2 max,
/// SpO2 candidate, calories) is written, and every workout carries an
/// external UUID built from its start second so a replayed drain cannot
/// duplicate it in Health.
final class HealthKitBridge: ObservableObject {
    enum State: Equatable {
        case off
        case unavailable
        case denied
        case ready
        case failed(String)

        var text: String {
            switch self {
            case .off: return "Off — nothing is written to Health"
            case .unavailable: return "HealthKit is not available on this device"
            case .denied: return "Write access was declined in the Health app"
            case .ready: return "On — measured sessions export automatically"
            case .failed(let message): return "Not enabled — \(message)"
            }
        }

        var isOn: Bool { self == .ready }
    }

    @Published private(set) var state: State = .off

    /// Marks the records this app created, so the user can tell them apart.
    static let sourceKey = "com.ribhupanwar.strap.source"

    private let store = HKHealthStore()

    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType()]
    }

    /// Stable across drains and relaunches: the session's first second.
    static func externalID(startUnix: Int) -> String {
        "strap-session-\(startUnix)"
    }

    /// Gait labels map to the matching Health workout type; an HR-only
    /// session is "other" because the band did not say what it was.
    static func activityType(for kind: String) -> HKWorkoutActivityType {
        switch kind.lowercased() {
        case "run": return .running
        case "walk": return .walking
        case "lift": return .traditionalStrengthTraining
        default: return .other
        }
    }

    @MainActor
    func activate() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return
        }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: [])
            state = store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
                ? .ready
                : .denied
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    @MainActor
    func deactivate() {
        state = .off
    }

    @MainActor
    func export(_ sessions: [ActivitySession]) async {
        guard state == .ready else { return }
        for session in sessions {
            await export(session)
        }
    }

    @MainActor
    func export(_ session: ActivitySession) async {
        let id = Self.externalID(startUnix: session.startUnix)
        guard await !exists(id) else { return }
        let start = Date(timeIntervalSince1970: TimeInterval(session.startUnix))
        let end = Date(timeIntervalSince1970: TimeInterval(session.endUnix + 1))
        var metadata: [String: Any] = [
            HKMetadataKeyExternalUUID: id,
            Self.sourceKey: "strap-band"
        ]
        if session.steps > 0 {
            metadata["com.ribhupanwar.strap.steps"] = session.steps
        }
        if let meanHR = session.meanHR {
            metadata["com.ribhupanwar.strap.meanHR"] = Int(meanHR.rounded())
        }
        await save(start: start, end: end, type: Self.activityType(for: session.kind), metadata: metadata)
    }

    @MainActor
    func export(live record: LiveActivityRecord) async {
        let id = Self.externalID(startUnix: record.startedUnix)
        guard await !exists(id) else { return }
        let start = Date(timeIntervalSince1970: TimeInterval(record.startedUnix))
        let end = Date(timeIntervalSince1970: TimeInterval(record.endedUnix))
        guard end > start else { return }
        var metadata: [String: Any] = [
            HKMetadataKeyExternalUUID: id,
            Self.sourceKey: "strap-live"
        ]
        if let meanHR = record.meanHR {
            metadata["com.ribhupanwar.strap.meanHR"] = Int(meanHR.rounded())
        }
        await save(start: start, end: end, type: .other, metadata: metadata)
    }

    @MainActor
    private func save(
        start: Date,
        end: Date,
        type: HKWorkoutActivityType,
        metadata: [String: Any]
    ) async {
        guard end > start else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = type
        configuration.locationType = .unknown
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            builder.addMetadata(metadata)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Health has no built-in dedupe, so the external UUID is queried first.
    private func exists(_ id: String) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeyExternalUUID,
                operatorType: .equalTo,
                value: id
            )
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.isEmpty == false)
            }
            store.execute(query)
        }
    }
}
