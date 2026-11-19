import Foundation

/// Automatic run/walk/workout detection ported from `whoop/activity.py`.
///
/// A session opens from sustained measured step-counter motion or a sustained
/// heart-rate rise (baseline = median HR 5-15 min old, start at max(100,
/// baseline+20) for 4 min; minimum session 5 min). The raw gait byte is not
/// vendor-verified and cannot open a session. Steps/min comes from step-counter
/// deltas, never the cadence byte, which can read 97-108 while sitting still.
enum ActivityDetect {
    static let baselineMinAgeS = 300
    static let baselineMaxAgeS = 900
    static let baselineMinSamples = 5
    static let hrStartAbsolute = 100.0
    static let hrStartDelta = 20.0
    static let startSustainS = 240
    static let minSessionS = 300
    // WHOOP's public 2026 ten-minute minimum is an optional comparison mode,
    // not evidence that every sport uses the same physiological gate.
    static let comparisonMinSessionS = 600
    // Walking needs sustained cardiovascular evidence; steps alone remain daily movement.
    // These conservative gates are STRAP heuristics, not reverse-engineered WHOOP thresholds.
    static let walkWorkoutMinSessionS = 600
    static let gapToleranceS = 180
    static let stepWindowS = 60
    static let walkSPM = 60.0
    static let runSPM = 140.0

    static let gaitStill = 0
    static let gaitWalk = 1
    static let gaitRun = 2

    static func detect(
        _ samples: [V18Sample],
        sleepPeriods: [SleepPeriod] = [],
        minimumDurationS: Int = minSessionS
    ) -> [ActivitySession] {
        // Preserve the established five-minute behavior unless a caller
        // explicitly opts into a longer, independently evaluated duration.
        guard minimumDurationS > 0 else { return [] }
        // Historical offload can replay the same second after reconnect.
        // Choose one record per timestamp before calculating cadence, HR
        // baselines and sustained-activity duration; duplicates are not time.
        var bySecond: [Int: V18Sample] = [:]
        for sample in samples where sample.wearing && (35...220).contains(sample.heartRate) {
            guard !sleepPeriods.contains(where: {
                $0.startUnix <= sample.unix && sample.unix <= $0.endUnix
            }) else { continue }
            if let old = bySecond[sample.unix] {
                let oldQuality = (old.stepCounter == nil ? 0 : 2)
                    + (old.dynamicAccelG == nil ? 0 : 1)
                    + old.rrIntervalsMS.count
                let newQuality = (sample.stepCounter == nil ? 0 : 2)
                    + (sample.dynamicAccelG == nil ? 0 : 1)
                    + sample.rrIntervalsMS.count
                if newQuality <= oldQuality { continue }
            }
            bySecond[sample.unix] = sample
        }
        let ordered = bySecond.values.sorted { $0.unix < $1.unix }
        guard !ordered.isEmpty else { return [] }

        let rates = (0..<ordered.count).map { StepCounter.rate(ordered, at: $0) }
        let baselines = baselineHRs(ordered)

        var flags: [Bool] = []
        var measuredMotion: [Bool] = []
        flags.reserveCapacity(ordered.count)
        measuredMotion.reserveCapacity(ordered.count)
        for (index, sample) in ordered.enumerated() {
            let locomotion: Bool
            // The gait byte is not vendor-verified. A still/unknown gait
            // must not suppress a sustained, measured step rate.
            // Prefer recent measured counter movement for every gait state:
            // the trailing 60-second rate otherwise extends runs into cooldown.
            let recentSteps: Bool
            if index > 0,
               let current = sample.stepCounter,
               let previous = ordered[index - 1].stepCounter {
                let elapsed = sample.unix - ordered[index - 1].unix
                // The 16-bit counter wraps near 65,535 and may reset on sync.
                // Reuse the validated counter semantics instead of signed
                // subtraction, which loses real movement at a legitimate wrap.
                let delta = elapsed > 0
                    ? StepCounter.delta(from: previous, to: current, seconds: elapsed) : 0
                recentSteps = elapsed > 0 && elapsed <= 5 &&
                    delta > 0 && Double(delta) * 60.0 / Double(elapsed) >= walkSPM &&
                    delta <= StepCounter.maxStepsPerSecond * elapsed
            } else {
                recentSteps = (rates[index] ?? 0) >= walkSPM
            }
            // The raw gait byte is not verified; it cannot open an activity by itself.
            locomotion = recentSteps
            let elevated: Bool
            if let baseline = baselines[index] {
                elevated = Double(sample.heartRate) >= max(hrStartAbsolute, baseline + hrStartDelta)
            } else {
                elevated = false
            }
            measuredMotion.append(locomotion)
            flags.append(locomotion || elevated)
        }
        let closed = GapClosing.closed(
            flags, unix: ordered.map { $0.unix }, maxGapS: gapToleranceS
        )

        var sessions: [ActivitySession] = []
        var index = 0
        while index < ordered.count {
            guard closed[index] else {
                index += 1
                continue
            }
            let start = index
            while index < ordered.count && closed[index] {
                if index > start && ordered[index].unix - ordered[index - 1].unix - 1 > gapToleranceS { break }
                index += 1
            }
            let end = index
            // HR remains elevated after a measured walk/run stops. Keep short
            // pauses inside the workout but exclude trailing HR-only cooldown.
            // Preserve existing behavior for HR-only cardio workouts.
            let motionIndices = (start..<end).filter { measuredMotion[$0] }
            let motionEnd = motionIndices.count >= startSustainS
                ? (motionIndices.last! + 1) : end
            let run = Array(ordered[start..<motionEnd])

            guard run[run.count - 1].unix - run[0].unix + 1 >= minimumDurationS else { continue }
            guard flags[start..<motionEnd].filter({ $0 }).count >= startSustainS else { continue }

            let walkTicks = run.filter { $0.activityClass == gaitWalk }.count
            let runTicks = run.filter { $0.activityClass == gaitRun }.count
            let spm = rates[start..<motionEnd].compactMap { $0 }.filter { $0 > 0 }
            let steps = StepCounter.total(run) ?? 0
            let hasSteps = run.contains { $0.stepCounter != nil }

            let detectedKind = kind(spm: spm, hasSteps: hasSteps)
            if detectedKind == "walk" {
                // Casual steps must not be promoted to an automatic workout.
                // Keep step counting independent; only gate auto-saved walking sessions.
                let duration = run[run.count - 1].unix - run[0].unix + 1
                guard duration >= max(minimumDurationS, walkWorkoutMinSessionS) else { continue }
                let elevatedSeconds = (start..<motionEnd).filter { sampleIndex in
                    guard measuredMotion[sampleIndex], let baseline = baselines[sampleIndex] else {
                        return false
                    }
                    return Double(ordered[sampleIndex].heartRate) >=
                        max(hrStartAbsolute, baseline + hrStartDelta)
                }.count
                guard elevatedSeconds >= startSustainS else { continue }
            }

            sessions.append(
                ActivitySession(
                    startUnix: run[0].unix,
                    endUnix: run[run.count - 1].unix,
                    kind: detectedKind,
                    steps: steps,
                    meanHR: Stats.mean(run.map { Double($0.heartRate) }),
                    walkTicks: walkTicks,
                    runTicks: runTicks
                )
            )
        }
        return sessions
    }

    /// Steps per minute over the trailing minute, from counter deltas. The
    /// shared accumulator handles wrap and restarts; leaps above the sprint
    /// ceiling are dropped rather than smeared into a fake minute of walking.
    static func stepRate(_ samples: [V18Sample], at index: Int) -> Double? {
        StepCounter.rate(samples, at: index, windowSeconds: stepWindowS)
    }

    /// Median HR of the 5-15 min old window, one value per sample.
    static func baselineHRs(_ samples: [V18Sample]) -> [Double?] {
        var result: [Double?] = []
        result.reserveCapacity(samples.count)
        var low = 0
        var high = 0
        for index in 0..<samples.count {
            let unix = samples[index].unix
            while low < index && samples[low].unix < unix - baselineMaxAgeS { low += 1 }
            while high < index && samples[high].unix <= unix - baselineMinAgeS { high += 1 }
            if high > low {
                let window = samples[low..<high].map { Double($0.heartRate) }
                result.append(window.count >= baselineMinSamples ? Stats.median(window) : nil)
            } else {
                result.append(nil)
            }
        }
        return result
    }

    static func kind(spm: [Double], hasSteps: Bool) -> String {
        if !spm.isEmpty {
            let median = Stats.median(spm)
            if median >= runSPM { return "run" }
            if median >= walkSPM { return "walk" }
        }
        return hasSteps ? "workout" : "cardio"
    }
}
