import Foundation
import CoreLocation

enum WorkoutPhase: String, Codable, Equatable {
    case idle
    case preparing
    case recording
    case paused
    case saving
    case saved
    case discarded
}

struct WorkoutMetrics: Codable, Equatable {
    var elapsedSeconds: Int = 0
    var distanceMeters: Double = 0
    var averageHeartRate: Int?
    var maximumHeartRate: Int?
    var calories: Int?
    var activityStrain: Double?
    var splits: [WorkoutSplit] = []
}

struct WorkoutSplit: Codable, Equatable {
    let index: Int
    let distanceMeters: Double
    let elapsedSeconds: Int
    let averageHeartRate: Int?
}

struct WorkoutRoutePoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let unix: TimeInterval
    let accuracyMeters: Double
    let heartRate: Int?
}

struct WorkoutSession: Codable, Identifiable, Equatable {
    let id: UUID
    let activityKind: String
    let activityLabel: String
    let startedAt: Date
    var endedAt: Date?
    var phase: WorkoutPhase = .idle
    var metrics: WorkoutMetrics = WorkoutMetrics()
    var route: [WorkoutRoutePoint] = []
    var hasGPS: Bool = false

    var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    var isComplete: Bool {
        phase == .saved || phase == .discarded
    }
}

final class WorkoutHistory {
    private let fileURL: URL
    private let defaults: UserDefaults
    private let key = "strap.workouts.v1"

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let suffix: String
        if directory == nil && defaults !== UserDefaults.standard {
            let idKey = "strap.workout.test.storageID"
            let id = defaults.string(forKey: idKey) ?? UUID().uuidString
            defaults.set(id, forKey: idKey)
            suffix = "workouts-\(id).json"
        } else {
            suffix = "workouts-v1.json"
        }
        self.fileURL = root.appendingPathComponent("Strap", isDirectory: true)
            .appendingPathComponent(suffix)
    }

    func all() -> [WorkoutSession] {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let data = try? Data(contentsOf: fileURL),
                  let sessions = try? JSONDecoder().decode([WorkoutSession].self, from: data) else {
                return []
            }
            return sessions.sorted { $0.startedAt > $1.startedAt }
        }
        guard let legacy = defaults.data(forKey: key),
              let sessions = try? JSONDecoder().decode([WorkoutSession].self, from: legacy) else { return [] }
        if persist(sessions) { defaults.removeObject(forKey: key) }
        return sessions.sorted { $0.startedAt > $1.startedAt }
    }

    @discardableResult
    private func persist(_ sessions: [WorkoutSession]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            return true
        } catch {
            return false
        }
    }

    private var currentArchiveReadable: Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return true }
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        return (try? JSONDecoder().decode([WorkoutSession].self, from: data)) != nil
    }

    @discardableResult
    func save(_ session: WorkoutSession) -> Bool {
        guard currentArchiveReadable else { return false }
        var sessions = all()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        return persist(sessions)
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        guard currentArchiveReadable else { return false }
        return persist(all().filter { $0.id != id })
    }
}