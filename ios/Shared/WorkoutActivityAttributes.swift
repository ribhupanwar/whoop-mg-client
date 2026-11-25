import ActivityKit
import Foundation

/// Shared, privacy-minimal state used by the app and its Live Activity extension.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var heartRate: Int?
        var zone: Int?
        var distanceMeters: Double?
        var paceSecondsPerKilometer: Int?
        var paused: Bool
        var lastSampleAt: Date
    }

    var sessionID: String
    var activityName: String
    var startedAt: Date
    var hasGPS: Bool
}
