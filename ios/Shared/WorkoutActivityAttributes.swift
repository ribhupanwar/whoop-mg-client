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
            case steps, calories, pace, distance, elapsed
        }

        /// Rotate only on real state deliveries. ActivityKit may coalesce
        /// updates; no extension timer or guaranteed update cadence.
        var compactMetric: CompactMetric {
            var available: [CompactMetric] = []
            if steps != nil { available.append(.steps) }
            if estimatedActiveCalories != nil { available.append(.calories) }
            if let paceSecondsPerKilometer, (1..<3600).contains(paceSecondsPerKilometer) { available.append(.pace) }
            if let distanceMeters, distanceMeters.isFinite, distanceMeters > 0 { available.append(.distance) }
            available.append(.elapsed)
            return available[(max(0, elapsedSeconds ?? 0) / 10) % available.count]
        }
    }

    var sessionID: String
    var activityName: String
    var startedAt: Date
    var hasGPS: Bool
}
