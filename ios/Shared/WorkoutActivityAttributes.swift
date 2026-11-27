import ActivityKit
import Foundation

/// Shared, privacy-minimal state used by the app and its Live Activity extension.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var heartRate: Int?
        var zone: Int?
        var distanceMeters: Double?
        var paceSecondsPerKilometer: Int?
        // Optional for backward decoding of existing workout Live Activities.
        var steps: Int?
        var stepsObservedAt: Date?
        var elapsedSeconds: Int?
        var timerAnchor: Date?
        var isConnected: Bool?
        var estimatedStrain: Double?
        var estimatedActiveCalories: Int? = nil
        var paused: Bool
        var lastSampleAt: Date

        enum CompactMetric: Equatable {
            case steps, calories, pace, distance, strain, elapsed
        }

        /// Rotate only on real ActivityKit state deliveries.
        func compactMetrics(for kind: DisplayKind, hasGPS: Bool) -> [CompactMetric] {
            var result: [CompactMetric] = []
            if kind == .walking, steps != nil { result.append(.steps) }
            if kind == .running, hasGPS,
               let paceSecondsPerKilometer, (1..<3600).contains(paceSecondsPerKilometer) {
                result.append(.pace)
            }
            if kind != .other, hasGPS,
               let distanceMeters, distanceMeters.isFinite, distanceMeters > 0 {
                result.append(.distance)
            }
            if estimatedActiveCalories != nil { result.append(.calories) }
            if let estimatedStrain, estimatedStrain.isFinite, (0...21).contains(estimatedStrain) {
                result.append(.strain)
            }
            result.append(.elapsed)
            return result
        }

        func compactMetric(for kind: DisplayKind, hasGPS: Bool) -> CompactMetric {
            let available = compactMetrics(for: kind, hasGPS: hasGPS)
            return available[(max(0, elapsedSeconds ?? 0) / 10) % available.count]
        }
    }

    var sessionID: String
    var activityName: String
    var startedAt: Date
    var hasGPS: Bool
    // Optional for existing Live Activities decoded after an update.
    var activityKind: String? = nil

    enum DisplayKind: Equatable {
        case running, walking, other
    }

    var displayKind: DisplayKind {
        Self.displayKind(activityKind ?? activityName)
    }

    static func displayKind(_ value: String) -> DisplayKind {
        switch value.lowercased() {
        case "run", "running", "outdoorrun", "outdoor run", "trailrun", "trail run",
             "intervalrun", "interval run", "indoorrun", "indoor run", "treadmill",
             "trackandfield", "track and field", "strollerjogging", "stroller jogging":
            return .running
        case "walk", "walking", "indoorwalk", "indoor walk", "commuting", "dogwalking",
             "dog walking", "strollerwalking", "stroller walking", "hiking":
            return .walking
        default: return .other
        }
    }
}
