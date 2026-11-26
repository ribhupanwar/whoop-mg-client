import Foundation

/// Persisted lower-bound step count from on-band v18 counter observations.
/// This is deliberately not presented as a complete WHOOP daily step total.
/// All state is actor-isolated; history persistence must succeed before ingest.
actor DailyStepLedger {
    private struct Observation: Codable {
        let unix: Int
        let counter: Int? // nil is a permanent tombstone for conflicting replays
    }

    private struct Day: Codable {
        let start: Date
        var observations: [Observation]
    }

    private let defaults: UserDefaults
    // Retain the original key/format, preserving data from the partial version.
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

    /// Merge all readings by timestamp in O(existing + incoming) rather than
    /// scanning per-day arrays for every 1 Hz packet. A disputed second stays
    /// invalid even when its original payload is replayed later.
    func ingest(_ samples: [V18Sample], calendar: Calendar = .current, now: Date = Date()) {
        let cutoffDate = calendar.date(byAdding: .day, value: -2,
                                       to: calendar.startOfDay(for: now)) ?? .distantPast
        let cutoff = Int(cutoffDate.timeIntervalSince1970)
        var bySecond: [Int: Observation] = [:]
        var changed = false

        for day in days {
            for observation in day.observations {
                guard observation.unix >= cutoff else {
                    changed = true
                    continue
                }
                if let previous = bySecond[observation.unix] {
                    if previous.counter != observation.counter {
                        bySecond[observation.unix] = Observation(unix: observation.unix, counter: nil)
                        changed = true
                    }
                } else {
                    bySecond[observation.unix] = observation
                }
            }
        }

        for sample in samples {
            guard sample.unix >= cutoff, let counter = sample.stepCounter,
                  (0..<StepCounter.modulus).contains(counter) else { continue }
            // Off-wrist records are a continuity break, not counted steps.
            // Retain an invalidation marker so a later replay cannot rejoin
            // endpoints around that missing on-wrist evidence.
            let candidate: Int? = sample.wearing ? counter : nil
            if let previous = bySecond[sample.unix] {
                if previous.counter != candidate, previous.counter != nil {
                    bySecond[sample.unix] = Observation(unix: sample.unix, counter: nil)
                    changed = true
                }
            } else {
                bySecond[sample.unix] = Observation(unix: sample.unix, counter: candidate)
                changed = true
            }
        }
        guard changed else { return }

        // Write only after a successful merge, as one atomic UserDefaults value.
        // Calendar bucket keys are presentation hints: timestamps remain canonical
        // so timezone changes never reassign a delta across the local midnight.
        var grouped: [Date: [Observation]] = [:]
        for observation in bySecond.values {
            let start = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(observation.unix)))
            grouped[start, default: []].append(observation)
        }
        days = grouped.map { start, observations in
            Day(start: start, observations: observations.sorted { $0.unix < $1.unix })
        }.sorted { $0.start < $1.start }
        if let bytes = try? JSONEncoder().encode(days) {
            defaults.set(bytes, forKey: key)
        }
    }

    struct TodaySnapshot: Equatable {
        let steps: Int?
        let lastObservedAt: Date?
        let lastIncreaseAt: Date?
    }

    /// A change of timezone is evaluated from absolute timestamps, not from
    /// the saved day bucket. Unknown observations are never treated as zero.
    func capturedToday(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        todaySnapshot(now: now, calendar: calendar).steps
    }

    func todaySnapshot(now: Date = Date(), calendar: Calendar = .current) -> TodaySnapshot {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return TodaySnapshot(steps: nil, lastObservedAt: nil, lastIncreaseAt: nil)
        }
        let lower = Int(start.timeIntervalSince1970)
        let upper = Int(end.timeIntervalSince1970)
        var bySecond: [Int: Observation] = [:]

        for day in days {
            for observation in day.observations where observation.unix >= lower && observation.unix < upper {
                if let previous = bySecond[observation.unix] {
                    if previous.counter != observation.counter {
                        bySecond[observation.unix] = Observation(unix: observation.unix, counter: nil)
                    }
                } else {
                    bySecond[observation.unix] = observation
                }
            }
        }

        var previous: (unix: Int, counter: Int)?
        var captured = 0
        var sawValid = false
        var lastObservedAt: Date?
        var lastIncreaseAt: Date?
        for unix in bySecond.keys.sorted() {
            guard let counter = bySecond[unix]?.counter else {
                previous = nil
                continue
            }
            sawValid = true
            lastObservedAt = Date(timeIntervalSince1970: Double(unix))
            if let prior = previous {
                let seconds = unix - prior.unix
                if seconds > 0 && seconds <= 10 {
                    let delta = StepCounter.delta(from: prior.counter, to: counter, seconds: seconds)
                    if delta <= StepCounter.maxStepsPerSecond * seconds {
                        captured += delta
                        if delta > 0 { lastIncreaseAt = Date(timeIntervalSince1970: Double(unix)) }
                    }
                }
            }
            previous = (unix, counter)
        }
        return TodaySnapshot(steps: sawValid ? captured : nil,
                             lastObservedAt: lastObservedAt, lastIncreaseAt: lastIncreaseAt)
    }

    /// Two independently verified capture totals must not be added: their
    /// observation windows can overlap. Their maximum remains a lower bound.
    static func bestRecordedMinimum(archive: Int?, ledger: Int?) -> Int? {
        [archive, ledger].compactMap { $0 }.filter { $0 >= 0 }.max()
    }
}
