import Foundation

/// Automatic run/walk/workout detection ported from `whoop/activity.py`.
///
/// Session start/stop uses the HR-only detector (baseline = median HR 5-15 min
/// old, start at max(100, baseline+20) sustained 5 min, stop below that
/// baseline+10 for 8 min, minimum 10 min). The gait byte reads 0 still /
/// 1 walk / 2 run, but the enum is not vendor-verified, so a label always
/// combines gait, steps and HR rather than trusting the byte alone. Steps/min
/// comes from the step counter, never the cadence byte, which reads 97-108
/// even while sitting still.
enum ActivityDetect {
    static let baselineMinAgeS = 300
    static let baselineMaxAgeS = 900
    static let baselineMinSamples = 5
    static let hrStartAbsolute = 100.0
    static let hrStartDelta = 20.0
    static let startSustainS = 300
    static let minSessionS = 600
    static let gapToleranceS = 180
    static let stepWindowS = 60
    static let walkSPM = 60.0
    static let runSPM = 140.0

    static let gaitStill = 0
    static let gaitWalk = 1
    static let gaitRun = 2

    static func detect(_ samples: [V18Sample]) -> [ActivitySession] {
        let ordered = samples.filter { $0.wearing }.sorted { $0.unix < $1.unix }
        guard !ordered.isEmpty else { return [] }

        let rates = (0..<ordered.count).map { stepRate(ordered, at: $0) }
        let baselines = baselineHRs(ordered)

        var flags: [Bool] = []
        flags.reserveCapacity(ordered.count)
        for (index, sample) in ordered.enumerated() {
            let gait = sample.activityClass
            let locomotion: Bool
            if gait == gaitWalk || gait == gaitRun {
                locomotion = true
            } else if gait == nil || gait == 0xFF {
                // No gait readout: fall back to the step counter. The trailing
                // minute lags a real stop, so it is only used when the band
                // gives no per-tick answer of its own.
                locomotion = (rates[index] ?? 0) >= walkSPM
            } else {
                locomotion = false
            }
            let elevated: Bool
            if let baseline = baselines[index] {
                elevated = Double(sample.heartRate) >= max(hrStartAbsolute, baseline + hrStartDelta)
            } else {
                elevated = false
            }
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
            while index < ordered.count && closed[index] { index += 1 }
            let end = index
            let run = Array(ordered[start..<end])

            guard run[run.count - 1].unix - run[0].unix + 1 >= minSessionS else { continue }
            guard flags[start..<end].filter({ $0 }).count >= startSustainS else { continue }

            let walkTicks = run.filter { $0.activityClass == gaitWalk }.count
            let runTicks = run.filter { $0.activityClass == gaitRun }.count
            let spm = rates[start..<end].compactMap { $0 }.filter { $0 > 0 }
            let hasSteps = run.contains { $0.stepCounter != nil }
            let first = run.first?.stepCounter
            let last = run.last?.stepCounter
            var steps = 0
            if let first, let last, last >= first {
                steps = (last - first) & 0xFFFF
            }

            sessions.append(
                ActivitySession(
                    startUnix: run[0].unix,
                    endUnix: run[run.count - 1].unix,
                    kind: kind(runTicks: runTicks, walkTicks: walkTicks, spm: spm, hasSteps: hasSteps),
                    steps: steps,
                    meanHR: Stats.mean(run.map { Double($0.heartRate) }),
                    walkTicks: walkTicks,
                    runTicks: runTicks
                )
            )
        }
        return sessions
    }

    /// Steps per minute over the trailing minute, from counter deltas. A
    /// single-second delta above 5 steps is impossible even at sprint cadence,
    /// so it is a counter jump and is dropped rather than smeared into the
    /// window as a fake minute of walking.
    static func stepRate(_ samples: [V18Sample], at index: Int) -> Double? {
        guard samples[index].stepCounter != nil else { return nil }
        let lower = max(0, index - stepWindowS - 1)
        var window: [V18Sample] = []
        for candidate in samples[lower...index] {
            guard candidate.stepCounter != nil else { continue }
            if samples[index].unix - candidate.unix <= stepWindowS {
                window.append(candidate)
            }
        }
        guard window.count >= 2 else { return nil }
        var total = 0
        for position in 1..<window.count {
            guard let before = window[position - 1].stepCounter,
                  let after = window[position].stepCounter else { continue }
            let delta = (after - before) & 0xFFFF
            if delta <= 5 { total += delta }
        }
        let span = samples[index].unix - window[0].unix
        guard span > 0 else { return nil }
        return Double(total) * 60.0 / Double(span)
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

    static func kind(runTicks: Int, walkTicks: Int, spm: [Double], hasSteps: Bool) -> String {
        if runTicks > 0 || walkTicks > 0 {
            return runTicks > walkTicks ? "run" : "walk"
        }
        if !spm.isEmpty {
            let median = Stats.median(spm)
            if median >= runSPM { return "run" }
            if median >= walkSPM { return "walk" }
        }
        return hasSteps ? "workout" : "cardio"
    }
}
