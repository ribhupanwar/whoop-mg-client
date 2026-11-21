import Foundation

/// Counters describe measured work. Network progress has no invented percentage.
struct HistoryProgress: Equatable {
    enum Stage: String {
        case preparing, nights, days, finishing

        var title: String {
            switch self {
            case .preparing: return "Preparing"
            case .nights: return "Analyzing Sleep"
            case .days: return "Updating Daily Metrics"
            case .finishing: return "Saving Results"
            }
        }
    }
    let stage: Stage
    let completed: Int
    let total: Int
    let reused: Int
    let startedAt: Date
    let lastStepAt: Date

    var title: String {
        switch stage {
        case .preparing: return "Preparing your history"
        case .nights: return "Analyzing sleep"
        case .days: return "Updating daily metrics"
        case .finishing: return "Saving your results"
        }
    }
    var fraction: Double? {
        guard total > 0, stage == .nights || stage == .days else { return nil }
        return min(1, max(0, Double(completed) / Double(total)))
    }
    func detail(now: Date) -> String {
        let age = max(0, Int(now.timeIntervalSince(lastStepAt)))
        if age >= 120 { return "Last progress \(age)s ago. Your saved checkpoints are safe." }
        guard total > 0 else { return "Your results update here automatically." }
        let unit = stage == .nights ? "nights" : "days"
        var text = "\(completed) of \(total) \(unit) · \(reused) reused"
        // Reused work is nearly instant: do not infer an ETA from cached units.
        if reused == 0, completed >= 3, completed < total {
            let elapsed = now.timeIntervalSince(startedAt)
            if elapsed >= 5 {
                let seconds = Int(ceil(elapsed / Double(completed) * Double(total - completed)))
                text += " · about \(max(1, (seconds + 59) / 60)) min left"
            }
        }
        return text
    }
}

enum HistorySyncPolicy {
    static let periodicSeconds: TimeInterval = 15 * 60
    static let foregroundSeconds: TimeInterval = 90
    static func shouldSync(now: Date, lastAttempt: Date?, manual: Bool = false,
                           foreground: Bool = false, emptyStreak: Int = 0) -> Bool {
        if manual { return true }
        guard let last = lastAttempt else { return true }
        let backoff = min(4.0, pow(2, Double(max(0, min(emptyStreak - 2, 2)))))
        let floor = foreground ? foregroundSeconds : periodicSeconds * backoff
        return now.timeIntervalSince(last) >= floor
    }

    /// Chase only a genuinely advancing, still-old backlog. Never spin on
    /// duplicate/empty chunks or a future-dated strap clock.
    static func shouldContinue(timedOut: Bool, sealedAndAcknowledged: Bool, newestInserted: Int?, previous: Int?, attempts: Int, now: Date) -> Bool {
        guard timedOut, sealedAndAcknowledged, attempts < 3, let newest = newestInserted, newest > 0,
              previous.map({ newest > $0 }) ?? true else { return false }
        let lag = now.timeIntervalSince1970 - Double(newest)
        return lag > 5 * 60
    }
}

/// Tied to the peer that reported RTC loss, including across reconnects.
struct HistoryClockGate {
    private var invalidPeers: Set<UUID> = []
    private(set) var revision = 0

    mutating func noteLoss(on peer: UUID) {
        invalidPeers.insert(peer)
        revision &+= 1
    }
    mutating func noteSynchronization(on peer: UUID) {
        invalidPeers.remove(peer)
    }

    func permitsHistory(on peer: UUID) -> Bool { !invalidPeers.contains(peer) }
}
