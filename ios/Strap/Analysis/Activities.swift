import Foundation

/// Automatic run/walk/workout detection ported from `whoop/activity.py`.
///
/// Session start/stop uses the HR-only detector (baseline = median HR 5-15 min
/// old, start at max(100, baseline+20) sustained 4 min, minimum 5 min). Gait
/// or a sustained step rate also opens a session, so a walk counts without a
/// start tap. The gait byte reads 0 still / 1 walk / 2 run, but the enum is
/// not vendor-verified, so a label always combines gait, steps and HR rather
/// than trusting the byte alone. Steps/min comes from the step counter, never
/// the cadence byte, which reads 97-108 even while sitting still.
enum ActivityDetect {
    static let baselineMinAgeS = 300
    static let baselineMaxAgeS = 900
    static let baselineMinSamples = 5
    static let hrStartAbsolute = 100.0
    static let hrStartDelta = 20.0
    static let startSustainS = 240
    static let minSessionS = 600
    static let minRunSessionS = 300
    static let minActiveFraction = 0.70
    static let gapToleranceS = 180
    static let stepWindowS = 60
    static let walkSPM = 60.0
    static let runSPM = 140.0

    static let gaitStill = 0
    static let gaitWalk = 1
    static let gaitRun = 2

    static func detect(
        _ samples: [V18Sample],
        sleepPeriods: [SleepPeriod] = []
    ) -> [ActivitySession] {
        let ordered = samples
            .filter { $0.wearing }
            .filter { sample in
                !sleepPeriods.contains {
                    $0.startUnix <= sample.unix && sample.unix <= $0.endUnix
                }
            }
            .sorted { $0.unix < $1.unix }
        guard !ordered.isEmpty else { return [] }

        let rates = (0..<ordered.count).map { StepCounter.rate(ordered, at: $0) }
        let baselines = baselineHRs(ordered)

        var flags: [Bool] = []
        flags.reserveCapacity(ordered.count)
        for (index, sample) in ordered.enumerated() {
            // The vendor gait byte is unverified; it cannot start a workout
            // without independent counter evidence. Elevated HR alone can be
            // commuting, stress, or stationary exercise, not walking/running.
            let measuredRate = rates[index] ?? 0
            let gait = sample.activityClass
            let counterMoving = measuredRate >= walkSPM
            let recentMoving: Bool
            if index > 0, let current = sample.stepCounter,
               let previous = ordered[index - 1].stepCounter {
                let elapsed = sample.unix - ordered[index - 1].unix
                let delta = (current - previous) & 0xFFFF
                recentMoving = elapsed > 0 && elapsed <= 5 && delta > 0 &&
                    Double(delta) / Double(elapsed) <= 5
            } else {
                recentMoving = false
            }
            // Require both sustained step cadence and recent movement;
            // trailing-minute cadence alone must not extend a stopped run.
            // HR is supporting evidence only, never an activity trigger.
            let locomotion = counterMoving && recentMoving
            _ = gait
            flags.append(locomotion)
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

            let duration = run[run.count - 1].unix - run[0].unix + 1
            let activeCount = flags[start..<end].filter { $0 }.count
            let runEvidence = rates[start..<end].compactMap { $0 }.filter { $0 >= runSPM }.count
            let running = runEvidence >= max(60, activeCount / 2)
            guard duration >= (running ? minRunSessionS : minSessionS) else { continue }
            guard activeCount >= startSustainS else { continue }
            // A few isolated steps with 3-minute bridged gaps are not a walk.
            guard Double(activeCount) / Double(max(1, run.count)) >= minActiveFraction else { continue }

            let walkTicks = run.filter { $0.activityClass == gaitWalk }.count
            let runTicks = run.filter { $0.activityClass == gaitRun }.count
            let spm = rates[start..<end].compactMap { $0 }.filter { $0 > 0 }
            let steps = StepCounter.total(run) ?? 0
            let hasSteps = run.contains { $0.stepCounter != nil }

            sessions.append(
                ActivitySession(
                    startUnix: run[0].unix,
                    endUnix: run[run.count - 1].unix,
                    kind: running ? "run" : "walk",
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
