import ActivityKit
import Foundation

/// A separate, bounded walking Live Activity. No activity is started solely
/// from stale history. iOS decides when its Lock Screen/Island can update.
struct CapturedStepsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let recordedMinimum: Int
        let lastObservedAt: Date
        let isConnected: Bool
        var heartRate: Int?
        var estimatedStrain: Double?
    }

    let startedAt: Date
}
