import Foundation

/// Bounded exponential reconnect schedule for a remembered WHOOP peripheral.
///
/// Ported from verified DSTA / OpenStrap Edge implementations:
/// [1s, 2s, 4s, 8s, 16s, 30s]
///
/// Kept pure and deterministic so retry limits, backoff delays, and jitter bounds
/// can be thoroughly verified in unit tests without CoreBluetooth dependencies.
public enum ReconnectBackoffPolicy {
    /// Bounded retry delays in seconds.
    public static let delays: [TimeInterval] = [1, 2, 4, 8, 16, 30]

    /// Maximum configured attempt index.
    public static var maximumAttempts: Int { delays.count }

    /// Returns the recommended delay in seconds for the given 1-based attempt count.
    /// Attempt 1: 1s, Attempt 2: 2s, Attempt 3: 4s, Attempt 4: 8s, Attempt 5: 16s, Attempt 6+: 30s.
    public static func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return delays[0] }
        let index = min(attempt - 1, delays.count - 1)
        return delays[index]
    }

    /// Returns the delay with up to ±10% jitter applied to prevent connection storming.
    public static func jitteredDelay(forAttempt attempt: Int, jitterFraction: Double = 0.10) -> TimeInterval {
        let base = delay(forAttempt: attempt)
        let span = base * min(max(jitterFraction, 0.0), 0.25)
        let delta = Double.random(in: -span...span)
        return max(0.5, base + delta)
    }
}
