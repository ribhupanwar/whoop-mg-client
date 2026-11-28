import Foundation

/// Independent, test-target-only experiment. Not a detector, not a wake
/// classifier, and never called by production. An eligible result only allows
/// the existing finalization decision to be evaluated; it cannot end a night.
enum SleepFinalizationShadow {
    struct Observation: Codable, Equatable {
        let unix: Int
        let state: Int?
        let usable: Bool
    }

    enum Verdict: String, Codable {
        case manualOverride, invalidInput, sleepObservedAfterEnd
        case insufficientHorizon, insufficientCoverage, eligibleForExistingDecision
    }

    struct Report: Codable {
        let verdict: Verdict
        let observedSeconds: Int
        let awakeStateSeconds: Int
        let sleepStateSeconds: Int
        let longestUnobservedSeconds: Int
    }

    // Match the existing 45-minute observation horizon. The coverage choices
    // below are provisional research gates, not WHOOP-derived constants.
    static let horizon = 45 * 60
    static let minimumAwakeStateSeconds = horizon * 9 / 10
    static let maxUnobservedSeconds = 60

    static func evaluate(endExclusive: Int, archiveLastUnix: Int?,
                         edited: Bool, observations: [Observation]) -> Report {
        func empty(_ verdict: Verdict) -> Report {
            Report(verdict: verdict, observedSeconds: 0, awakeStateSeconds: 0,
                   sleepStateSeconds: 0, longestUnobservedSeconds: 0)
        }
        if edited { return empty(.manualOverride) }
        guard endExclusive > 0, endExclusive <= Int.max - horizon,
              let last = archiveLastUnix, last >= 0 else { return empty(.invalidInput) }
        let limit = endExclusive + horizon
        var states: [Int: Set<Int>] = [:]
        for row in observations where row.usable && row.unix >= endExclusive && row.unix < limit && row.unix <= last {
            guard let state = row.state, (0...3).contains(state) else { continue }
            states[row.unix, default: []].insert(state)
        }
        var observed = 0, awake = 0, sleep = 0, gap = 0, longest = 0
        for second in endExclusive..<limit {
            let evidence = states[second] ?? []
            // Conflicting retransmissions cannot count as verified awake.
            if evidence.contains(2) { sleep += 1 }
            if evidence.count == 1 {
                observed += 1
                if evidence.contains(0) || evidence.contains(3) { awake += 1 }
                gap = 0
            } else {
                gap += 1
                longest = max(longest, gap)
            }
        }
        let verdict: Verdict
        if sleep > 0 { verdict = .sleepObservedAfterEnd }
        else if last < limit - 1 { verdict = .insufficientHorizon }
        else if awake < minimumAwakeStateSeconds || longest > maxUnobservedSeconds {
            verdict = .insufficientCoverage
        } else { verdict = .eligibleForExistingDecision }
        return Report(verdict: verdict, observedSeconds: observed, awakeStateSeconds: awake,
                      sleepStateSeconds: sleep, longestUnobservedSeconds: longest)
    }
}
