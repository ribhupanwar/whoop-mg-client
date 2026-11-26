import Foundation

/// Replay-idempotent local step ledger. This stores counter observations, not
/// an assumed WHOOP all-day step count. Missing capture intervals remain unknown.
actor DailyStepLedger {
    private struct Observation: Codable {
        let unix: Int
        let counter: Int? // nil marks conflicting retransmissions
    }

    private struct Day: Codable {
        let start: Date
        var observations: [Observation]
    }

    private let defaults: UserDefaults
    private let key = "strap.steps.counterObservations.v1"
    private var days: [Day]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let bytes = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Day].self, from: bytes) {
            days = decoded
        } else {
            days = []
        }
    }

    /// Merge historical/live observations without counting the same second twice.
    /// Conflicting counter values invalidate that second and break continuity.
    func ingest(_ samples: [V18Sample], calendar: Calendar = .current, now: Date = Date()) {
        var changed = false
        for sample in samples {
            guard let value = sample.stepCounter, (0..<StepCounter.modulus).contains(value) else { continue }
            let timestamp = Date(timeIntervalSince1970: Double(sample.unix))
            let start = calendar.startOfDay(for: timestamp)
            if let dayIndex = days.firstIndex(where: { $0.start == start }) {
                if let index = days[dayIndex].observations.firstIndex(where: { $0.unix == sample.unix }) {
                    let previous = days[dayIndex].observations[index].counter
                    if previous != value && previous != nil {
                        days[dayIndex].observations[index] = Observation(unix: sample.unix, counter: nil)
                        changed = true
                    }
                } else {
                    days[dayIndex].observations.append(Observation(unix: sample.unix, counter: value))
                    changed = true
                }
            } else {
                days.append(Day(start: start, observations: [Observation(unix: sample.unix, counter: value)]))
                changed = true
            }
        }
        // Keep recent observations for replay reconciliation, bounded on disk.
        let cutoff = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now)) ?? .distantPast
        let originalCount = days.count
        days.removeAll { $0.start < cutoff }
        changed = changed || days.count != originalCount
        if changed, let bytes = try? JSONEncoder().encode(days) {
            defaults.set(bytes, forKey: key)
        }
    }

    /// Returns nil when no valid counter was observed today. The count is a
    /// lower bound over verified continuous intervals, not a fabricated total.
    func capturedToday(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let lower = Int(start.timeIntervalSince1970)
        let upper = Int(end.timeIntervalSince1970)
        // Stored buckets reflect the timezone at ingestion. Re-select by absolute
        // timestamps so changing timezone cannot hide or double-count a day.
        var bySecond: [Int: Observation] = [:]
        for day in days {
            for row in day.observations where row.unix >= lower && row.unix < upper {
                if let previous = bySecond[row.unix] {
                    if previous.counter != row.counter {
                        bySecond[row.unix] = Observation(unix: row.unix, counter: nil)
                    }
                } else {
                    bySecond[row.unix] = row
                }
            }
        }
        var previous: (unix: Int, value: Int)?
        var sum = 0
        var sawValid = false
        for unix in bySecond.keys.sorted() {
            guard let value = bySecond[unix]?.counter else {
                previous = nil
                continue
            }
            sawValid = true
            if let before = previous {
                let seconds = unix - before.unix
                if seconds > 0 && seconds <= 10 {
                    let delta = StepCounter.delta(from: before.value, to: value, seconds: seconds)
                    if delta <= StepCounter.maxStepsPerSecond * seconds { sum += delta }
                }
            }
            previous = (unix, value)
        }
        return sawValid ? sum : nil
    }
}
