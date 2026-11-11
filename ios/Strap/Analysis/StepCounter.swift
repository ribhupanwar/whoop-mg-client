import Foundation

/// The v18 record carries a 16-bit step counter at `inner[49]`. Our own
/// captures pin down its behaviour well enough to count from it honestly:
///
///  * It climbs by 0-4 per second while the gait byte reads walk/run and sits
///    still otherwise, so a capture total is the sum of its deltas, not the
///    difference between the last and first reading.
///  * It returns to 0 when the band restarts or is re-synced mid-capture, so a
///    drop is a new epoch, never 65,536 steps. Only a fall from the top of the
///    16-bit range is treated as a wrap.
///  * It sometimes catches up in one leap (12 steps after six quiet readings)
///    once its internal gait counter flushes. Those leaps are real steps, so
///    the total keeps them; only the per-minute *rate* ignores them, because
///    smearing a leap across one minute would invent sustained walking.
///
/// The counter is not a daily total: a fresh wrist session can start at 0 in
/// the afternoon, so the app labels what it shows as the capture's steps.
enum StepCounter {
    static let modulus = 65_536
    /// Sprint cadence tops out near 250 steps/min; six in a second is the
    /// ceiling a single record can honestly represent.
    static let maxStepsPerSecond = 6
    static let wrapFloor = 0xF000
    static let wrapCeiling = 0x0FFF

    /// Steps recorded across a window. nil when no record carried a counter.
    static func total(_ samples: [V18Sample]) -> Int? {
        var total = 0
        var previous: (unix: Int, value: Int)?
        var sawCounter = false
        for sample in samples.sorted(by: { $0.unix < $1.unix }) {
            guard let value = sample.stepCounter else { continue }
            sawCounter = true
            guard let before = previous else {
                previous = (sample.unix, value)
                continue
            }
            // Replayed historical records can share a timestamp. Counting
            // either delta would manufacture steps and distort activity gait.
            guard sample.unix > before.unix else { continue }
            let seconds = sample.unix - before.unix
            let change = delta(from: before.value, to: value, seconds: seconds)
            // A counter reset or a gap cannot prove steps happened in the
            // missing interval. Keep only plausible continuous deltas.
            if seconds <= 10 && change <= maxStepsPerSecond * seconds {
                total += change
            }
            previous = (sample.unix, value)
        }
        return sawCounter ? total : nil
    }

    /// Steps between two counter readings. Wrap is unwrapped; anything else
    /// that falls is a restart and counts only what came after it.
    static func delta(from before: Int, to after: Int, seconds: Int) -> Int {
        if after >= before {
            return after - before
        }
        if before >= wrapFloor && after <= wrapCeiling {
            return modulus - before + after
        }
        // A reset is a new counter epoch. The first reading after reset
        // has no known starting point, so it must not count as new steps.
        return 0
    }

    /// Trailing-minute steps per minute. Leaps above the sprint ceiling are
    /// counter artefacts for rate purposes and are dropped, not smeared.
    static func rate(_ samples: [V18Sample], at index: Int, windowSeconds: Int = 60) -> Double? {
        guard index >= 0, index < samples.count, samples[index].stepCounter != nil else {
            return nil
        }
        let end = samples[index]
        let window = samples[max(0, index - windowSeconds - 1)...index].filter {
            $0.stepCounter != nil && end.unix - $0.unix <= windowSeconds
        }
        guard window.count >= 2, let start = window.first, let last = window.last else {
            return nil
        }
        var total = 0
        for (before, after) in zip(window, window.dropFirst()) {
            let gap = after.unix - before.unix
            // Do not turn duplicate timestamps or long sync gaps into cadence.
            // Match total() semantics: only adjacent, continuous counter epochs.
            guard gap > 0 && gap <= 10 else { continue }
            let steps = delta(from: before.stepCounter!, to: after.stepCounter!, seconds: gap)
            if steps <= maxStepsPerSecond * gap {
                total += steps
            }
        }
        let span = last.unix - start.unix
        guard span > 0 else { return nil }
        return Double(total) * 60.0 / Double(span)
    }
}
