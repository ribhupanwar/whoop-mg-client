import Foundation

/// Confidence classification for candidate activity evaluation.
enum ActivityConfidence: String, Codable {
    case confirmed
    case uncertain
    case dailyMovement
}

/// Evaluated activity candidate carrying classification diagnostics.
struct ActivityCandidate {
    let session: ActivitySession
    let confidence: ActivityConfidence
    let reason: String
}

/// Measured cadence or simultaneous elevated HR and motion supply activity
/// evidence. A candidate needs a dense five-minute confirmation window.
/// Short gaps between confirmed evidence bouts may be pauses. Individual
/// bursts beyond those bouts cannot keep a session open.
struct ActivityDecision: Encodable {
    let startUnix: Int
    let endUnix: Int
    let proposedKind: String?
    let observedSeconds: Int
    let supportedSeconds: Int
    let meanHR: Double
    let cadenceMedian: Double?
    let movementSeconds: Int
    let reason: String
}

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
    // Sustained brisk cadence, not incidental one-step-per-second movement.
    // This is a STRAP workout classifier threshold; daily step counting is separate.
    static let walkSPM = 100.0
    static let runSPM = 140.0

    static let gaitStill = 0
    static let gaitWalk = 1
    static let gaitRun = 2

    static func detect(
        _ samples: [V18Sample],
        sleepPeriods: [SleepPeriod] = [],
        minimumDurationS: Int = minSessionS,
        restingHR: Double? = nil,
        maxHR: Double? = nil,
        onDecision: ((ActivityDecision) -> Void)? = nil
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
        var latchedBaseline: Double?
        var baselineFrozen = false
        var lastEvidenceUnix: Int?

        for (index, sample) in ordered.enumerated() {
            if let lastEvidenceUnix, sample.unix - lastEvidenceUnix > gapToleranceS {
                latchedBaseline = nil
                baselineFrozen = false
            }
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
                // A single two-step burst is not evidence of brisk walking.
                // Require the validated trailing cadence AND immediate motion:
                // the first prevents shopping/office false positives, the
                // second prevents the 60-second rate extending cooldown.
                recentSteps = elapsed > 0 && elapsed <= 5 &&
                    delta > 0 && delta <= StepCounter.maxStepsPerSecond * elapsed &&
                    (rates[index] ?? 0) >= walkSPM
            } else {
                recentSteps = (rates[index] ?? 0) >= walkSPM
            }
            // The unverified gait byte can describe a candidate, but only
            // measured step deltas may supply locomotion evidence.
            let locomotion = recentSteps
            let moving = hasMeasuredAcceleration(sample)

            // Pre-workout baseline latching prevents long workouts from inflating
            // their own baseline and prematurely cutting off after 10-15 minutes.
            let computedBaseline = baselines[index]
            // Do not learn a new 'resting' baseline from the middle of a
            // workout; a frozen nil means no pre-workout baseline is available.
            let baseline = baselineFrozen ? latchedBaseline : computedBaseline

            let elevated: Bool
            if let baseline = baseline {
                elevated = Double(sample.heartRate) >= max(hrStartAbsolute, baseline + hrStartDelta)
            } else if sample.stepCounter == nil {
                // When no pre-activity resting baseline exists and device has no step counter
                // (e.g. cardio, cycling, rowing starting at sync boundary), allow sustained
                // elevated HR combined with dynamic acceleration to initiate a candidate session
                // while strictly rejecting sedentary resting stress.
                elevated = Double(sample.heartRate) >= hrStartAbsolute && moving
            } else {
                elevated = false
            }
            measuredMotion.append(locomotion)
            let isActive = locomotion || (elevated && moving)
            flags.append(isActive)

            if isActive {
                if !baselineFrozen {
                    let prevIndex = max(0, index - 1)
                    latchedBaseline = baselines[prevIndex] ?? computedBaseline
                    baselineFrozen = true
                }
                lastEvidenceUnix = sample.unix
            }
        }
        let timestamps = ordered.map(\.unix)
        let supported = sustainedEvidence(flags, unix: timestamps)
        let closed = GapClosing.closed(supported, unix: timestamps, maxGapS: gapToleranceS)
        if let onDecision {
            let rejected = ordered.indices.filter { flags[$0] && !closed[$0] }
            if let first = rejected.first, let last = rejected.last {
                onDecision(ActivityDecision(startUnix: timestamps[first], endUnix: timestamps[last],
                    proposedKind: nil, observedSeconds: last - first + 1,
                    supportedSeconds: 0, meanHR: Stats.mean(rejected.map { Double(ordered[$0].heartRate) }),
                    cadenceMedian: nil, movementSeconds: rejected.filter { hasMeasuredAcceleration(ordered[$0]) }.count,
                    reason: "Sparse evidence outside confirmed bouts"))
            }
        }

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
            // Generic workouts already end at the last supported HR/motion evidence.
            let motionIndices = (start..<end).filter { supported[$0] && measuredMotion[$0] }
            let motionEnd = motionIndices.count >= startSustainS
                ? ((motionIndices.last ?? end) + 1) : end
            let run = Array(ordered[start..<motionEnd])

            let walkTicks = run.filter { $0.activityClass == gaitWalk }.count
            let runTicks = run.filter { $0.activityClass == gaitRun }.count
            let spm = rates[start..<motionEnd].compactMap { $0 }.filter { $0 > 0 }
            let steps = StepCounter.total(run) ?? 0
            let hasSteps = run.contains { $0.stepCounter != nil }

            let detectedKind = kind(spm: spm, hasSteps: hasSteps)
            let evidenceCount = supported[start..<motionEnd].filter { $0 }.count
            let duration = run[run.count - 1].unix - run[0].unix + 1
            func decision(_ reason: String) {
                guard let onDecision else { return }
                onDecision(ActivityDecision(startUnix: run[0].unix, endUnix: run[run.count - 1].unix,
                    proposedKind: detectedKind, observedSeconds: run.count, supportedSeconds: evidenceCount,
                    meanHR: Stats.mean(run.map { Double($0.heartRate) }),
                    cadenceMedian: spm.isEmpty ? nil : Stats.median(spm),
                    movementSeconds: run.filter(hasMeasuredAcceleration).count, reason: reason))
            }
            guard duration >= minimumDurationS, evidenceCount >= startSustainS else {
                decision("Insufficient duration or confirmed evidence")
                continue
            }
            if detectedKind == "walk" {
                // Casual steps must not be promoted to an automatic workout.
                // Keep step counting independent; only gate auto-saved walking sessions.
                guard duration >= max(minimumDurationS, walkWorkoutMinSessionS) else {
                    decision("Walk below the ten-minute floor")
                    continue
                }
                // Only an HR baseline observed BEFORE the candidate is
                // eligible. A baseline computed from workout samples can make
                // 135 bpm exercise appear unelevated relative to itself.
                let preWorkoutBaseline = baselines[start]
                let hrFloor = max(
                    hrStartAbsolute,
                    (preWorkoutBaseline ?? (hrStartAbsolute - hrStartDelta)) + hrStartDelta
                )
                let exertionSeconds = (start..<motionEnd).filter { sampleIndex in
                    supported[sampleIndex] && measuredMotion[sampleIndex] &&
                        Double(ordered[sampleIndex].heartRate) >= hrFloor
                }.count
                guard exertionSeconds >= startSustainS else {
                    decision("Walk lacks sustained cardiovascular evidence")
                    continue
                }
            }

            if detectedKind == "workout" || detectedKind == "cardio" {
                let baseline = baselines[start]
                let hrFloor = max(hrStartAbsolute, (baseline ?? (hrStartAbsolute - hrStartDelta)) + hrStartDelta)
                let concurrentSeconds = (start..<motionEnd).filter { sampleIndex in
                    supported[sampleIndex] && Double(ordered[sampleIndex].heartRate) >= hrFloor &&
                        hasMeasuredAcceleration(ordered[sampleIndex])
                }.count
                let confirmed = detectedKind == "workout"
                    ? confirmsGenericWorkout(durationS: duration, concurrentSeconds: concurrentSeconds,
                                             hasPreActivityBaseline: baseline != nil)
                    : concurrentSeconds >= startSustainS
                guard confirmed else {
                    decision("Candidate lacks sustained concurrent HR and motion")
                    continue
                }
            }

            var sessionStrain: Double? = nil
            let resting = restingHR ?? baselines[start] ?? 60.0
            let maxHeart = maxHR ?? 190.0
            if maxHeart > resting {
                sessionStrain = WhoopDerivedStrain.score(run, restingHR: resting, maxHR: maxHeart)
            }

            decision("Confirmed in retained samples before overlap and persistence checks")
            sessions.append(
                ActivitySession(
                    startUnix: run[0].unix,
                    endUnix: run[run.count - 1].unix,
                    kind: detectedKind,
                    steps: steps,
                    meanHR: Stats.mean(run.map { Double($0.heartRate) }),
                    walkTicks: walkTicks,
                    runTicks: runTicks,
                    maxHR: run.map(\.heartRate).max(),
                    strain: sessionStrain
                )
            )
        }
        return suppressDuplicates(sessions)
    }

    private static func hasMeasuredAcceleration(_ sample: V18Sample) -> Bool {
        guard let acceleration = sample.dynamicAccelG else { return false }
        return acceleration.isFinite && acceleration >= 0.03
    }

    /// Keep observed evidence only where four minutes of it fit in a rolling
    /// five-minute wall-clock interval. Never count a missing or inactive
    /// second as evidence, even when it is later bridged as a short pause.
    static func sustainedEvidence(_ flags: [Bool], unix: [Int]) -> [Bool] {
        var supported = Array(repeating: false, count: flags.count)
        var left = 0
        var count = 0
        var coveredThrough = -1
        for right in flags.indices {
            if flags[right] { count += 1 }
            while unix[right] - unix[left] >= minSessionS {
                if flags[left] { count -= 1 }
                left += 1
            }
            guard count >= startSustainS else { continue }
            for index in max(left, coveredThrough + 1)...right {
                supported[index] = flags[index]
            }
            coveredThrough = right
        }
        return supported
    }

    /// Suppress auto-detected sessions that overlap by >= 50% with an earlier accepted session
    /// (matching WHOOP 5.80.2 ActivityEntity duplicate suppression, 0xa39cef2).
    static func suppressDuplicates(
        _ sessions: [ActivitySession],
        existing: [ActivitySession] = []
    ) -> [ActivitySession] {
        var accepted: [ActivitySession] = []
        for candidate in sessions.sorted(by: { $0.startUnix < $1.startUnix }) {
            let candidateDuration = max(1, candidate.durationS)
            let isDuplicate = (accepted + existing).contains { other in
                let overlapStart = max(candidate.startUnix, other.startUnix)
                let overlapEnd = min(candidate.endUnix, other.endUnix)
                guard overlapEnd >= overlapStart else { return false }
                let overlap = overlapEnd - overlapStart + 1
                return Double(overlap) / Double(candidateDuration) >= 0.50
            }
            if !isDuplicate {
                accepted.append(candidate)
            }
        }
        return accepted
    }

    /// Evaluates activity candidate windows for diagnostic review and confidence classification.
    static func evaluateCandidates(
        _ samples: [V18Sample],
        sleepPeriods: [SleepPeriod] = [],
        minimumDurationS: Int = minSessionS
    ) -> [ActivityCandidate] {
        let detected = detect(samples, sleepPeriods: sleepPeriods, minimumDurationS: minimumDurationS)
        return detected.map { ActivityCandidate(session: $0, confidence: .confirmed, reason: $0.kind) }
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

    static func confirmsGenericWorkout(
        durationS: Int, concurrentSeconds: Int, hasPreActivityBaseline: Bool
    ) -> Bool {
        let requiredEvidence = hasPreActivityBaseline ? startSustainS : startSustainS * 2
        return durationS >= walkWorkoutMinSessionS && concurrentSeconds >= requiredEvidence
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
