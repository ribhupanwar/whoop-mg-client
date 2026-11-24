import Foundation

/// Detects a "stuck strap": the strap reports records newer than ours (`strapNewestTs` from
/// GET_DATA_RANGE) AND our biometric data frontier (`ourFrontierTs` = max persisted HR ts)
/// hasn't advanced for `stuckAfterSeconds`.
///
/// Comparing the two separates genuinely stuck from off-wrist / caught-up states (where the strap
/// is not ahead of us -> no new data expected -> never stuck).
/// Pure + value-typed so it is deterministically testable without BLE mocks.
public struct StuckStrapDetector: Equatable {
    public let stuckAfterSeconds: TimeInterval
    /// How far ahead the strap must be (seconds) before "frozen frontier" counts as behind.
    public let behindGapSeconds: Int
    private var lastFrontierTs: Int?
    private var lastAdvanceWall: TimeInterval?

    public init(stuckAfterSeconds: TimeInterval = 60.0, behindGapSeconds: Int = 300) {
        self.stuckAfterSeconds = stuckAfterSeconds
        self.behindGapSeconds = behindGapSeconds
    }

    /// `strapNewestTs` = newest record the strap reports having (from GET_DATA_RANGE).
    /// `ourFrontierTs` = newest record we've persisted in local SQLite storage.
    ///
    /// Stuck = behind (strap ahead by > behindGapSeconds) AND our frontier hasn't advanced for >= stuckAfterSeconds.
    /// Advancing -> healthy; not-behind -> caught up / off-wrist.
    public mutating func observe(strapNewestTs: Int?, ourFrontierTs: Int?, now: TimeInterval) -> Bool {
        guard let strapNewest = strapNewestTs, let frontier = ourFrontierTs else { return false }
        guard let last = lastFrontierTs else {
            // First observation: seed, not stuck
            lastFrontierTs = frontier
            lastAdvanceWall = now
            return false
        }
        if frontier > last {
            // Frontier is progressing -> healthy, reset the timer
            lastFrontierTs = frontier
            lastAdvanceWall = now
            return false
        }
        let behind = (strapNewest - frontier) > behindGapSeconds
        if !behind {
            // Caught up or off-wrist -> not stuck
            lastAdvanceWall = now
            return false
        }
        let elapsed = now - (lastAdvanceWall ?? now)
        return elapsed >= stuckAfterSeconds
    }

    public mutating func reset() {
        lastFrontierTs = nil
        lastAdvanceWall = nil
    }
}
