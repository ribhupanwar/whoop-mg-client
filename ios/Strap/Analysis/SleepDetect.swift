import Foundation

/// Actigraphy + heart-rate-drop sleep detector ported from `whoop/health.py`.
/// It finds the window and scores duration/continuity; the four-class estimate
/// is a separate pass over that window in `SleepStager`.
enum SleepDetect {
    static let quietAccelG = 0.08
    static let minSleepS = 3600
    static let maxSleepS = 12 * 3600 // WHOOP 5.80.2 TWELVE_HOUR limit (SleepWindow.swift)
    static let gapToleranceS = 300
    static let hrDropBPM = 5.0
    /// Autonomic onset gate: HR must settle ≤ awakeMedian + 5 for ≥10 min sustained stillness.
    static let autonomicOnsetThresholdBPM = 5.0
    static let autonomicOnsetWindowS = 10 * 60
    
    // NOOP parity improvements
    /// Sparse gravity threshold: when gravity coverage < 50% of HR coverage, engage robustness branches
    static let sparseGravityCoverageThreshold = 0.5
    /// Sparse gravity uses lower stillness threshold
    static let sparseQuietAccelG = 0.10
    /// Motion-corroborated HR confirmation multipliers
    static let hrSleepBaselineMult = 1.05
    static let quiescentHrSleepMult = 1.15
    /// Off-wrist fractional backstop: drop run only when off-wrist fraction >= threshold
    static let maxOffWristSleepFraction = 0.5
    
    /// Diagnostic trace callback for forensic gate analysis
    /// Emits structured JSON-like dictionaries per gate decision
    typealias TraceSink = ([String: Any]) -> Void

/// Sustained-quiet periods confirmed by a heart-rate drop.
    ///
    /// Motion alone is not enough — sitting still at a desk is not sleep — so
    /// a candidate must also sit below the capture's active median by
    /// `hrDropBPM`. With no active seconds to compare against, the period is
    /// rejected rather than assumed.
    ///
    /// NOOP parity improvements:
    /// - Sparse gravity handling for WHOOP 5.0/MG
    /// - Motion-corroborated dual-band HR confirmation
    /// - Off-wrist fractional backstop
    /// - Structured diagnostic tracing
    static func detect(
        _ samples: [V18Sample],
        quietAccelG: Double = SleepDetect.quietAccelG,
        minSleepS: Int = SleepDetect.minSleepS,
        gapToleranceS: Int = SleepDetect.gapToleranceS,
        hrDropBPM: Double = SleepDetect.hrDropBPM,
        traceSink: TraceSink? = nil
    ) -> [SleepPeriod] {
        let ordered = samples.sorted { $0.unix < $1.unix }
        guard !ordered.isEmpty else { return [] }
        
        // Sparse gravity detection (NOOP P0): when gravity coverage < 50% of HR coverage
        let gravSeconds = Set(ordered.compactMap { $0.dynamicAccelG != nil ? $0.unix : nil }).count
        let hrSeconds = Set(ordered.filter { $0.wearing }.map(\.unix)).count
        let sparse = hrSeconds > 0 && Double(gravSeconds) / Double(hrSeconds) < sparseGravityCoverageThreshold
        if sparse {
            traceSink?(["gate": "sparseBridge", "verdict": "sparse", "gravityCoverageRatio": hrSeconds > 0 ? Double(gravSeconds) / Double(hrSeconds) : 0])
        }
        
        // Adjust stillness threshold for sparse gravity
        let effectiveQuietAccelG = sparse ? sparseQuietAccelG : quietAccelG
        
        let quiet = ordered.map { sample in
            guard let accel = sample.dynamicAccelG, accel.isFinite, accel >= 0 else { return false }
            return sample.wearing && (35...220).contains(sample.heartRate) && accel <= effectiveQuietAccelG
        }
        let activeHRs = zip(ordered, quiet)
            .filter { !$0.1 && $0.0.wearing && (35...220).contains($0.0.heartRate) }
            .map { Double($0.0.heartRate) }
        guard !activeHRs.isEmpty else { return [] }
        let activeMedian = Stats.median(activeHRs)
        
        let closed = GapClosing.closed(
            quiet, unix: ordered.map { $0.unix }, maxGapS: gapToleranceS
        )
        
        var periods: [SleepPeriod] = []
        var index = 0
        while index < ordered.count {
            guard closed[index] else {
                index += 1
                continue
            }
            let start = index
            while index < ordered.count && closed[index] {
                // No samples means no evidence of quiet. A gap longer than
                // the movement tolerance must split the candidate night.
                if index > start && ordered[index].unix - ordered[index - 1].unix - 1 > gapToleranceS {
                    break
                }
                index += 1
            }
            let end = index
            let fullRun = Array(ordered[start..<end])
            let fullDuration = fullRun[fullRun.count - 1].unix - fullRun[0].unix + 1
            guard fullDuration >= minSleepS else { continue }

            let runSegments = splitRunAtHRTransitions(
                fullRun, activeMedian: activeMedian, hrDropBPM: hrDropBPM,
                minSegmentS: minSleepS, quietAccelG: effectiveQuietAccelG
            )
            for run in runSegments {
                let duration = run[run.count - 1].unix - run[0].unix + 1
                guard duration >= minSleepS else { continue }
            // A short evening rest or lying still is easily mistaken for
            // sleep by actigraphy plus HR drop. Require substantially longer
            // evidence for daytime/evening sleep candidates. Overnight
            // sessions retain the original minimum for fragmented sleep.
            let startHour = Calendar.current.component(
                .hour, from: Date(timeIntervalSince1970: TimeInterval(run[0].unix))
            )
            let daytime = (8..<22).contains(startHour)
            if daytime && duration < max(minSleepS, 90 * 60) { continue }
            
            let runHRs = run.filter { $0.wearing && (35...220).contains($0.heartRate) }.map { Double($0.heartRate) }
            let wornSeconds = Set(run.filter { $0.wearing && (35...220).contains($0.heartRate) }.map(\.unix)).count
            let observedSeconds = Set(run.map(\.unix)).count
            // Avoid interpreting sparse or off-wrist quiet records as sleep.
            guard observedSeconds >= minSleepS / 2,
                  wornSeconds * 5 >= observedSeconds * 4,
                  !runHRs.isEmpty else { continue }
            
            // Primary HR drop gate (original STRAP): run median must be below active median by hrDropBPM
            let primaryThreshold = activeMedian - hrDropBPM
            
            // Motion-corroborated dual-band HR confirmation (NOOP P1)
            let deeplyQuiescent = runIsDeeplyQuiescent(run)
            let adaptiveThreshold = deeplyQuiescent ? activeMedian * quiescentHrSleepMult : activeMedian * hrSleepBaselineMult
            
            // Stillness alone cannot prove sleep. Keep the established HR-drop
            // gate until relaxed thresholds have independent validation.
            // The stricter threshold also agrees with the HR transition splitter.
            let effectiveThreshold = min(primaryThreshold, adaptiveThreshold)
            let runMedianHR = Stats.median(runHRs)
            guard runMedianHR <= effectiveThreshold else {
                traceSink?(["gate": "hrConfirm", "verdict": "dropped", 
                            "runMedianHR": runMedianHR, "primaryThreshold": primaryThreshold,
                            "adaptiveThreshold": adaptiveThreshold, "effectiveThreshold": effectiveThreshold,
                            "deeplyQuiescent": deeplyQuiescent])
                continue
            }
            
            traceSink?(["gate": "hrConfirm", "verdict": "passed", 
                        "runMedianHR": runMedianHR, "primaryThreshold": primaryThreshold,
                        "adaptiveThreshold": adaptiveThreshold, "effectiveThreshold": effectiveThreshold,
                        "deeplyQuiescent": deeplyQuiescent])
            
            // Off-wrist fractional backstop (NOOP P1)
            let offWristFraction = computeOffWristFraction(run, in: ordered)
            if offWristFraction >= maxOffWristSleepFraction {
                traceSink?(["gate": "offWrist", "verdict": "dropped", "offWristFraction": offWristFraction])
                continue
            }
            
            // A waking HR spike can make sedentary rest appear to have a
            // large HR drop. Require the candidate's lowest sustained HR
            // to be below the waking reference as an independent check.
            if daytime {
                guard let resting = Hrv.minimumRollingMean(runHRs, window: 300),
                      resting <= activeMedian * 0.95 else {
                    traceSink?(["gate": "daytimeGuard", "verdict": "dropped", "restingHR": Hrv.minimumRollingMean(runHRs, window: 300) as Any, "threshold": activeMedian * 0.95])
                    continue
                }
            }

            // WHOOP v18 inner[73] bits 4–5 encode a coarse band
            // wake(0)/still(1)/sleep(2)/up(3) state. It is NOT a sleep
            // stage or a definitive physiological measurement. Only use
            // sustained, positively identified "up" to veto a candidate;
            // do not require state=2, because the band's state lags onset
            // and may be absent/overridden on some firmware.
            let stateRows = run.filter { $0.sleepState != nil }
            let upRows = stateRows.filter { $0.sleepState == 3 }.count
            let declaredSleepRows = stateRows.filter { $0.sleepState == 2 }.count
            let declaredStillRows = stateRows.filter { $0.sleepState == 1 }.count
            // Early-evening quiet while reading or using a phone can last
            // hours and lower HR. Do not label pre-22:00 stillness as sleep
            // unless the band positively reports sustained sleep evidence.
            // This conservative gate may leave early bedtimes unclassified.
            // A long pre-bed quiet period can precede true sleep. Do not
            // discard the whole overnight window when onset is ambiguous;
            // trim the false early onset to the first sustained band sleep
            // declaration instead. Keep the rest of the night available.
            var verifiedStart = run[0].unix
            // Only daytime/evening rest before 22:00 needs a positive five-minute
            // band-sleep declaration. The device's coarse state=2 may lag true
            // overnight sleep onset by minutes. Overnight 22:00–07:59 quiet
            // candidates already require worn, observed, low-HR evidence above;
            // advancing to state=2 must not discard that measured prefix.
            if daytime {
                let sleepRows = run.filter {
                    $0.sleepState == 2 && $0.wearing && (35...220).contains($0.heartRate)
                }
                // An isolated state=2 packet while resting with a phone is
                // not sustained onset. Require five contiguous minutes, and
                // retain the start of that confirmation rather than its end.
                guard let confirmed = Hrv.contiguousRuns(sleepRows).first(where: { $0.count >= 300 }),
                      let first = confirmed.first else { continue }
                verifiedStart = first.unix
                // The coarse band sleep flag can lag physiological settling.
                // Backtrack only through sustained, worn, quiet, low-HR
                // evidence immediately preceding a confirmed sleep run.
                // Never subtract a fixed number of minutes.
                let confirmedHR = Stats.median(Array(confirmed.prefix(300)).map { Double($0.heartRate) })
                let floorUnix = max(run[0].unix, verifiedStart - 30 * 60)
                let prelude = run.filter { floorUnix <= $0.unix && $0.unix < verifiedStart }
                var cursor = verifiedStart
                while cursor - 60 >= floorUnix {
                    let minute = prelude.filter { cursor - 60 <= $0.unix && $0.unix < cursor }
                    let valid = minute.filter {
                        $0.wearing && (35...220).contains($0.heartRate)
                            && $0.sleepState != 3
                            && ($0.dynamicAccelG.map { $0.isFinite && $0 >= 0 && $0 <= 0.05 } ?? false)
                            && Double($0.heartRate) <= confirmedHR + 8
                    }
                    // At least 40 distinct observed seconds per minute;
                    // a sparse replay cannot be interpreted as sleep.
                    // Allows minor positional settling rustles.
                    guard Set(valid.map(\.unix)).count >= 40 else { break }
                    cursor -= 60
                }
                // Low movement alone can be awake resting. Only accept the
                // backtrack when the prelude contains a measured HR settling
                // transition, rather than hours of flat quiet lying.
                let earlier = run.filter {
                    cursor - 5 * 60 <= $0.unix && $0.unix < cursor
                        && $0.wearing && (35...220).contains($0.heartRate)
                }
                let transitionObserved = earlier.count >= 180
                    && Stats.median(earlier.map { Double($0.heartRate) }) >= confirmedHR + 6
                if verifiedStart - cursor >= 5 * 60 && transitionObserved {
                    verifiedStart = cursor
                }
            } else {
                // For overnight candidates, if the run begins with sustained band-up (state 3)
                // (e.g. awake in bed reading, moving, or talking before settling), trim that awake prefix.
                // Overnight sleep onset must not include a >= 5 minute (300s) sustained up(3) lead.
                var leadingUpSeconds = 0
                var leadingAwakeEnd: Int? = nil
                for sample in run {
                    guard sample.wearing, (35...220).contains(sample.heartRate) else { break }
                    if sample.sleepState == 3 {
                        leadingUpSeconds += 1
                        leadingAwakeEnd = sample.unix
                    } else if leadingUpSeconds >= 300 {
                        break
                    } else {
                        leadingUpSeconds = 0
                        leadingAwakeEnd = nil
                        break
                    }
                }
                if leadingUpSeconds >= 300, let leadingAwakeEnd {
                    verifiedStart = max(verifiedStart, leadingAwakeEnd + 1)
                }
                let refinedStart = refineOvernightOnset(run, start: verifiedStart, quietAccelG: quietAccelG)
                if run[run.count - 1].unix - refinedStart + 1 >= minSleepS {
                    verifiedStart = refinedStart
                }
            }

            // Autonomic onset gate (WHOOP parity): HR must settle ≤ activeMedian + 5 for sustained stillness.
            // This finds the true physiological sleep onset independent of band state lag.
            let autonomicThreshold = activeMedian + SleepDetect.autonomicOnsetThresholdBPM
            var autonomicCursor = verifiedStart
            let runStart = run[0].unix
            let searchFloor = max(runStart, verifiedStart - 60 * 60) // Search up to 1 hour before verifiedStart
            while autonomicCursor - 60 >= searchFloor {
                let minute = run.filter { autonomicCursor - 60 <= $0.unix && $0.unix < autonomicCursor }
                let valid = minute.filter {
                    $0.wearing && (35...220).contains($0.heartRate)
                        && $0.sleepState != 3
                        && ($0.dynamicAccelG.map { $0.isFinite && $0 >= 0 && $0 <= quietAccelG } ?? false)
                        && Double($0.heartRate) <= autonomicThreshold
                }
                // At least 50 distinct observed seconds per minute (≥83% coverage)
                guard Set(valid.map(\.unix)).count >= 50 else { break }
                autonomicCursor -= 60
            }
            // Only apply autonomic backtrack if it extends ≥5 min and shows a settling transition
            let autonomicBacktrack = verifiedStart - autonomicCursor
            if autonomicBacktrack >= 5 * 60 {
                let earlier = run.filter {
                    autonomicCursor - 5 * 60 <= $0.unix && $0.unix < autonomicCursor
                        && $0.wearing && (35...220).contains($0.heartRate)
                }
                let transitionObserved = earlier.count >= 180
                    && Stats.median(earlier.map { Double($0.heartRate) }) >= autonomicThreshold + 3
                if transitionObserved {
                    verifiedStart = autonomicCursor
                    print("[SleepDetect] Autonomic onset gate advanced start by \(autonomicBacktrack / 60) min to \(Date(timeIntervalSince1970: TimeInterval(verifiedStart)))")
                }
            }
            // A trimmed onset must still leave a real sleep-length window.
            // Otherwise an hours-long quiet evening with only a few minutes
            // of declared sleep could pass the earlier duration check.
            guard run[run.count - 1].unix - verifiedStart + 1 >= minSleepS else {
                traceSink?(["gate": "minSleepMin", "verdict": "dropped", "duration": run[run.count - 1].unix - verifiedStart + 1, "min": minSleepS])
                continue
            }
            // If the signal is a constant zero/default, abstain entirely.
            // A reliable veto needs at least five minutes of actual state
            // observations, with "up" occupying most of the period and no
            // positive sleep declaration.
            if stateRows.count >= 300,
               upRows * 10 >= stateRows.count * 7,
               declaredSleepRows == 0,
               declaredStillRows * 10 < stateRows.count {
                traceSink?(["gate": "stateVeto", "verdict": "dropped", "stateRows": stateRows.count, "upRows": upRows, "sleepRows": declaredSleepRows, "stillRows": declaredStillRows])
                continue
            }

            // A prolonged, explicitly reported band-up tail is wakefulness,
            // even when the wearer remains physically still. Trim at its onset
            // rather than extending the night's end on a later archive replay.
            // Do not infer wake from missing or ambiguous band states.
            var verifiedEnd = run[run.count - 1].unix
            // A terminal band state 0 means no positive sleep declaration,
            // not that an earlier sustained up(3) run has disappeared.
            // Skip only a short contiguous terminal 0 suffix, then require
            // at least five minutes of explicit up(3) before trimming.
            // This handles archive tails like 3 -> 0 without treating a
            // transient mid-night up(3) interval as final wake-up.
            var upStart: Int? = nil
            var nextUnix: Int? = nil
            var trailingUnknownSeconds = 0
            var upSeconds = 0
            for sample in run.reversed() {
                guard sample.wearing, (35...220).contains(sample.heartRate),
                      nextUnix.map({ $0 - sample.unix <= 2 }) ?? true else { break }
                if sample.sleepState == 0 && upSeconds == 0 {
                    trailingUnknownSeconds += nextUnix.map { $0 - sample.unix } ?? 1
                    if trailingUnknownSeconds > 30 * 60 { break }
                } else if sample.sleepState == 3 {
                    upStart = sample.unix
                    upSeconds += nextUnix.map { $0 - sample.unix } ?? 1
                } else {
                    break
                }
                nextUnix = sample.unix
            }
            if let upStart, upSeconds >= 300 {
                verifiedEnd = upStart - 1
            } else if let terminalUp = run.last(where: { $0.sleepState == 3 }),
                      let lastSample = run.last,
                      lastSample.unix - terminalUp.unix <= 60 {
                // A fresh terminal band-up transition corroborates wake, but
                // cannot alone establish when waking began. Require sustained
                // elevated HR AND motion relative to the preceding resting
                // baseline. A short bathroom break followed by sleep has no
                // terminal up marker and must not truncate the night.
                let baseline = run.filter {
                    terminalUp.unix - 30 * 60 <= $0.unix
                        && $0.unix < terminalUp.unix - 10 * 60
                        && $0.wearing && (35...220).contains($0.heartRate)
                }
                if baseline.count >= 600 {
                    let restingHR = Stats.median(baseline.map { Double($0.heartRate) })
                    let lowerBound = max(verifiedStart + minSleepS, terminalUp.unix - 12 * 60)
                    var wakeCandidate: Int?
                    var minute = lowerBound
                    while minute + 180 <= terminalUp.unix {
                        let window = run.filter {
                            minute <= $0.unix && $0.unix < minute + 180
                                && $0.wearing && (35...220).contains($0.heartRate)
                                && $0.dynamicAccelG.map { $0.isFinite && $0 >= 0 } == true
                        }
                        let elevated = window.filter {
                            Double($0.heartRate) >= restingHR + 10
                        }.count
                        let moving = window.filter {
                            ($0.dynamicAccelG ?? 0) >= 0.015
                        }.count
                        if Set(window.map(\.unix)).count >= 150,
                           elevated >= 150, moving >= 30 {
                            wakeCandidate = minute
                            break
                        }
                        minute += 60
                    }
                    if let wakeCandidate {
                        verifiedEnd = min(verifiedEnd, wakeCandidate - 1)
                    }
                }
            }
            // A band can continue reporting coarse sleep(2) after the wearer
            // wakes. Require a complete, densely sampled terminal five-minute
            // HR-and-motion transition before trimming without band-up(3).
            // Only examine the terminal tail: a bathroom awakening followed by
            // resumed sleep must not truncate the night.
            let terminalEnd = run[run.count - 1].unix
            let terminalStart = terminalEnd - 299
            let terminal = run.filter {
                terminalStart <= $0.unix && $0.unix <= terminalEnd
                    && $0.wearing && (35...220).contains($0.heartRate)
                    && ($0.dynamicAccelG.map { $0.isFinite && $0 >= 0 } ?? false)
            }
            let reference = run.filter {
                terminalStart - 30 * 60 <= $0.unix
                    && $0.unix < terminalStart - 10 * 60
                    && $0.wearing && (35...220).contains($0.heartRate)
            }
            if Set(terminal.map(\.unix)).count >= 270,
               Set(reference.map(\.unix)).count >= 600 {
                let restingHR = Stats.median(reference.map { Double($0.heartRate) })
                let elevated = terminal.filter { Double($0.heartRate) >= restingHR + 10 }.count
                let moving = terminal.filter { ($0.dynamicAccelG ?? 0) >= 0.015 }.count
                // Sustained elevation and measured movement are both required.
                // A single alarm vibration spike or HR-only rise is insufficient.
                if elevated >= 240, moving >= 90 {
                    verifiedEnd = min(verifiedEnd, terminalStart - 1)
                }
            }
            // Genuine sleep can exceed 12 hours during illness or deep recovery (Issue #126).
            // Do not drop genuine >12h sleep; protect only against multi-day corrupt RTC jumps.
            guard verifiedEnd - verifiedStart + 1 >= minSleepS,
                  verifiedEnd - verifiedStart + 1 <= 24 * 3600 else { continue }

            // Metrics must describe the verified interval, not the discarded
            // awake tail or a trimmed pre-bed onset.
            let verifiedIndices = (start..<end).filter {
                ordered[$0].unix >= verifiedStart && ordered[$0].unix <= verifiedEnd
            }
            // The pre-trim coverage check can be satisfied entirely by awake
            // evening records. Re-check coverage inside the confirmed sleep
            // window so an archive gap cannot become fabricated sleep.
            let verifiedDuration = verifiedEnd - verifiedStart + 1
            let verifiedObserved = Set(verifiedIndices.map { ordered[$0].unix }).count
            let verifiedWorn = Set(verifiedIndices.filter {
                ordered[$0].wearing && (35...220).contains(ordered[$0].heartRate)
            }.map { ordered[$0].unix }).count
            guard verifiedObserved >= verifiedDuration / 2,
                  verifiedWorn * 5 >= verifiedObserved * 4 else { continue }
            let quietSeconds = verifiedIndices.filter { quiet[$0] }.count
            let verifiedHRs = verifiedIndices.compactMap { index -> Double? in
                let row = ordered[index]
                return row.wearing && (35...220).contains(row.heartRate)
                    ? Double(row.heartRate) : nil
            }
            // Harmonize wakeEvents with WHOOP 5.80.2 disturbanceCount and SleepSession.movementBouts:
            // Count sustained movement bouts (movement persisting >= 15 seconds), not 1-second edge noise.
            // Timestamp gaps must break the contiguous movement bout rather than bridging across minutes.
            var movingSeconds = 0
            var wakeEvents = 0
            var lastMovingUnix: Int? = nil
            for index in verifiedIndices {
                let u = ordered[index].unix
                if !quiet[index] {
                    if let last = lastMovingUnix {
                        if u == last + 1 {
                            movingSeconds += 1
                        } else if u > last + 1 {
                            // Sparse gap: reset to single moving second rather than bridging across gap
                            movingSeconds = 1
                        }
                    } else {
                        movingSeconds = 1
                    }
                    lastMovingUnix = u
                    if movingSeconds == 15 { wakeEvents += 1 }
                } else {
                    movingSeconds = 0
                    lastMovingUnix = nil
                }
            }
            periods.append(
                SleepPeriod(
                    startUnix: verifiedStart,
                    endUnix: verifiedEnd,
                    quietFraction: Double(quietSeconds) / Double(max(1, verifiedIndices.count)),
                    meanHR: Stats.mean(verifiedHRs),
                    wakeEvents: wakeEvents
                )
            )
            }
        }
        return mergeNocturnalPeriods(periods, samples: ordered, quietAccelG: quietAccelG)
    }

    /// The full-run HR median can hide a prolonged elevated-HR lead-in.
    /// Refine only when a later, sustained band hint corroborates a distinct
    /// lower-HR portion of the run. A brief lag or missing hint keeps the
    /// original actigraphy onset.
    private static func refineOvernightOnset(
        _ run: [V18Sample], start: Int, quietAccelG: Double
    ) -> Int {
        let minimumDelay = 30 * 60      // 30 min: must have delayed hint before attempting
        let backtrackWindow = 90 * 60   // 90 min: max search window for HR transition
        let observed = run.filter { $0.unix >= start && $0.wearing && (35...220).contains($0.heartRate) }
        let sleepHints = observed.filter { $0.sleepState == 2 }
        guard let confirmation = Hrv.contiguousRuns(sleepHints).first(where: { $0.count >= 300 }),
              let hintStart = confirmation.first?.unix, hintStart - start >= minimumDelay else { return start }

        let anchor = Array(confirmation.prefix(300))
        guard anchor.filter({ sample in
            sample.dynamicAccelG.map { $0.isFinite && $0 >= 0 && $0 <= quietAccelG } ?? false
        }).count >= 270 else { return start }
        let confirmedHR = Stats.median(anchor.map { Double($0.heartRate) })

        // Use one observation per second. The same relative HR margin used
        // for daytime backtracking keeps stable, delayed-hint sleep intact.
        let prefix = observed.prefix { $0.unix < start + minimumDelay }
        var prefixHR: [Int: Int] = [:]
        for sample in prefix { prefixHR[sample.unix] = sample.heartRate }
        guard prefixHR.count >= minimumDelay * 4 / 5,
              Stats.median(prefixHR.values.map(Double.init)) > confirmedHR + 8 else { return start }

        let lowerBound = max(start, hintStart - backtrackWindow)
        var quietHRBySecond: [Int: Int] = [:]
        for sample in observed where lowerBound <= sample.unix && sample.unix < hintStart {
            guard sample.sleepState != 3, let motion = sample.dynamicAccelG,
                  motion.isFinite, motion >= 0, motion <= quietAccelG else { continue }
            quietHRBySecond[sample.unix] = sample.heartRate
        }

        var onset = hintStart
        while onset - 60 >= lowerBound {
            let minuteHR = ((onset - 60)..<onset).compactMap { quietHRBySecond[$0] }
            // Missing observations and the search limit cannot locate an onset.
            guard minuteHR.count >= 40 else { return start }
            if Stats.median(minuteHR.map(Double.init)) > confirmedHR + 8 {
                return onset
            }
            onset -= 60
        }
        return start
    }

    /// Split a quiet run at three-consecutive-minute sustained HR elevations
    /// (e.g. quiet awake-in-bed laptop use before sleep or sustained mid-night wake),
    /// without splitting on brief 1–2 minute REM surges.
    static func splitRunAtHRTransitions(
        _ run: [V18Sample],
        activeMedian: Double,
        hrDropBPM: Double,
        minSegmentS: Int = 1800,
        quietAccelG: Double = SleepDetect.quietAccelG
    ) -> [[V18Sample]] {
        guard let firstUnix = run.first?.unix, let lastUnix = run.last?.unix,
              lastUnix - firstUnix + 1 >= minSegmentS else { return [run] }

        var hrBySec: [Int: Double] = [:]
        for sample in run where sample.wearing && (35...220).contains(sample.heartRate) {
            if hrBySec[sample.unix] == nil {
                hrBySec[sample.unix] = Double(sample.heartRate)
            }
        }
        guard hrBySec.count >= minSegmentS / 2 else { return [run] }

        let elevatedThreshold = activeMedian - hrDropBPM

        func minuteMedian(_ startSec: Int) -> Double? {
            let hrs = (startSec..<(startSec + 60)).compactMap { hrBySec[$0] }
            guard hrs.count >= 30 else { return nil }
            return Stats.median(hrs)
        }

        let hasBandSleep = run.contains { $0.sleepState == 2 }

        // An internal elevated HR minute is not independently a wake label.
        // Coarse firmware sleep plus dense measured quiet motion can corroborate
        // continuing overnight sleep, including a resumed segment. Limit the
        // exception to established sleep and modest HR elevation; never change
        // the leading-onset, daytime, terminal-wake or off-wrist gates.
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date(timeIntervalSince1970: Double(firstUnix)))
        let nocturnal = hour >= 22 || hour < 8
        var corroborated = Set<Int>()
        for row in run where row.wearing && (35...220).contains(row.heartRate) && row.sleepState == 2 {
            if let motion = row.dynamicAccelG, motion.isFinite, motion >= 0, motion <= quietAccelG {
                corroborated.insert(row.unix)
            }
        }
        var confirmedAt: Int?
        if nocturnal {
            var consecutive = 0
            var previous: Int?
            for second in corroborated.sorted() {
                consecutive = previous.map { second == $0 + 1 } == true ? consecutive + 1 : 1
                if consecutive >= 300 { confirmedAt = second; break }
                previous = second
            }
        }
        func elevatedForInternalSplit(_ minute: Int) -> Bool {
            guard let median = minuteMedian(minute), median >= elevatedThreshold else { return false }
            if let confirmedAt, minute > confirmedAt, median <= activeMedian + autonomicOnsetThresholdBPM {
                let quietSleepSeconds = (minute..<(minute + 60)).filter { corroborated.contains($0) }.count
                if quietSleepSeconds >= 48 { return false }
            }
            return true
        }

        var t = firstUnix
        while t + 60 <= lastUnix {
            if hasBandSleep && run.contains(where: { t <= $0.unix && $0.unix < t + 60 && $0.sleepState == 1 }) {
                break
            }
            if let med = minuteMedian(t), med >= elevatedThreshold {
                t += 60
            } else {
                break
            }
        }
        var segStart = t
        var segments: [[V18Sample]] = []

        // A leading band-still prefix followed by declared sleep belongs to
        // the existing overnight onset refinement policy. The internal HR
        // splitter must not bypass its delay, anchor and coverage guards.
        // Preserve segStart, and only scan for internal transitions after
        // the first declared sleep sample when the leading scan stopped on still.
        if hasBandSleep,
           run.contains(where: { t <= $0.unix && $0.unix < t + 60 && $0.sleepState == 1 }),
           let firstDeclaredSleep = run.first(where: { $0.unix >= t && $0.sleepState == 2 }) {
            t = firstDeclaredSleep.unix
        }

        while t + 180 <= lastUnix {
            if elevatedForInternalSplit(t),
               elevatedForInternalSplit(t + 60),
               elevatedForInternalSplit(t + 120) {
                var endT = t + 180
                while endT + 60 <= lastUnix {
                    if elevatedForInternalSplit(endT) {
                        endT += 60
                    } else {
                        break
                    }
                }
                // Do not split near the end of the night if the remaining resumed sleep
                // is shorter than minSegmentS (e.g. brief bathroom trip before final wake).
                guard lastUnix - endT + 1 >= minSegmentS else { break }
                if t - segStart >= minSegmentS {
                    let seg = run.filter { segStart <= $0.unix && $0.unix < t }
                    if !seg.isEmpty { segments.append(seg) }
                }
                t = endT
                segStart = t
            } else {
                t += 60
            }
        }

        if lastUnix - segStart + 1 >= minSegmentS {
            let tail = run.filter { segStart <= $0.unix && $0.unix <= lastUnix }
            if !tail.isEmpty { segments.append(tail) }
        }
        return segments.isEmpty ? [run] : segments
    }

    private static func isNocturnalPeriod(_ period: SleepPeriod) -> Bool {
        let startHour = Calendar.current.component(
            .hour, from: Date(timeIntervalSince1970: TimeInterval(period.startUnix))
        )
        let endHour = Calendar.current.component(
            .hour, from: Date(timeIntervalSince1970: TimeInterval(period.endUnix))
        )
        // Nocturnal sleep starts in the evening (>= 20) or overnight/early morning (< 8),
        // or extends into the morning hours (<= 12).
        return startHour >= 20 || startHour < 8 || endHour <= 12
    }

    /// Merges consecutive nocturnal sleep candidates separated by a brief
    /// awakening (e.g. bathroom break, hydration, or restless wakefulness <= 30 minutes)
    /// into a single continuous overnight sleep session, preserving the awakening as
    /// in-bed awake time for downstream staging.
    static func mergeNocturnalPeriods(
        _ periods: [SleepPeriod],
        samples: [V18Sample],
        quietAccelG: Double = SleepDetect.quietAccelG,
        maxAwakeningGapS: Int = 30 * 60,
        maxCombinedSleepS: Int = 18 * 3600
    ) -> [SleepPeriod] {
        guard periods.count > 1 else { return periods }
        var merged: [SleepPeriod] = []
        var current = periods[0]

        for next in periods.dropFirst() {
            let gap = next.startUnix - current.endUnix - 1
            let combinedEnd = max(current.endUnix, next.endUnix)
            let combinedSpan = combinedEnd - current.startUnix + 1

            let isNocturnal = isNocturnalPeriod(current) && isNocturnalPeriod(next)

            // Preserve the ordinary 30-minute rule. A modestly longer
            // overnight interruption can be joined only with substantially
            // stronger observed evidence on both sides and during the gap.
            let extendedLimit = 45 * 60
            guard isNocturnal, combinedSpan <= maxCombinedSleepS,
                  gap <= max(maxAwakeningGapS, extendedLimit) else {
                merged.append(current)
                current = next
                continue
            }
            let gapSamples = samples.filter { current.endUnix < $0.unix && $0.unix < next.startUnix }
            if gap > maxAwakeningGapS {
                guard maxAwakeningGapS == 30 * 60,
                      confirmedExtendedNocturnalResumption(current, next, gapSamples: gapSamples,
                                                           samples: samples, quietAccelG: quietAccelG) else {
                    merged.append(current)
                    current = next
                    continue
                }
            }
            // A short bathroom break still requires positive on-wrist coverage.
            // Use elapsed seconds so missing records and replays cannot pass the gate.
            let wornSeconds = Set(gapSamples.lazy.filter {
                $0.wearing && (35...220).contains($0.heartRate)
            }.map(\.unix)).count
            let wornDuringGap = gap <= 0 || wornSeconds * 5 >= gap * 3

            // A sustained active workout is not an in-bed awakening.
            let activeWorkoutDuringGap = Set(gapSamples.lazy.filter {
                $0.wearing && ($0.dynamicAccelG ?? 0) >= 0.15 && $0.heartRate >= 90
            }.map(\.unix)).count >= 180

            if wornDuringGap && !activeWorkoutDuringGap {
                let allIndices = samples.filter { current.startUnix <= $0.unix && $0.unix <= combinedEnd }
                let quietCount = allIndices.filter { sample in
                    guard let accel = sample.dynamicAccelG, accel.isFinite, accel >= 0 else { return false }
                    return sample.wearing && (35...220).contains(sample.heartRate) && accel <= quietAccelG
                }.count
                let validHRs = allIndices.compactMap {
                    $0.wearing && (35...220).contains($0.heartRate) ? Double($0.heartRate) : nil
                }
                current = SleepPeriod(
                    startUnix: current.startUnix,
                    endUnix: combinedEnd,
                    quietFraction: Double(quietCount) / Double(max(1, allIndices.count)),
                    meanHR: Stats.mean(validHRs),
                    wakeEvents: current.wakeEvents + next.wakeEvents + 1
                )
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }

    /// Narrow extension for two independently detected nocturnal periods.
    /// Coarse band state alone is not a physiological sleep stage.
    private static func confirmedExtendedNocturnalResumption(
        _ previous: SleepPeriod, _ next: SleepPeriod,
        gapSamples: [V18Sample], samples: [V18Sample], quietAccelG: Double
    ) -> Bool {
        let gap = next.startUnix - previous.endUnix - 1
        guard gap > 30 * 60, gap <= 45 * 60,
              previous.durationS >= 60 * 60, next.durationS >= 60 * 60 else { return false }
        let calendar = Calendar.current
        let wake = Date(timeIntervalSince1970: Double(previous.endUnix))
        let resume = Date(timeIntervalSince1970: Double(next.startUnix))
        guard calendar.isDate(wake, inSameDayAs: resume),
              calendar.component(.hour, from: wake) < 8,
              calendar.component(.hour, from: resume) < 8 else { return false }

        func valid(_ row: V18Sample) -> Bool {
            row.wearing && (35...220).contains(row.heartRate)
                && row.dynamicAccelG.map { $0.isFinite && $0 >= 0 } == true
        }
        let observed = gapSamples.filter(valid)
        let covered = Set(observed.map(\.unix)).count
        let quiet = Set(observed.filter { ($0.dynamicAccelG ?? .infinity) <= quietAccelG }.map(\.unix)).count
        guard covered * 10 >= gap * 9, quiet * 5 >= gap * 4 else { return false }

        // A sustained band sleep hint corroborates each independently detected
        // period; require unique worn quiet seconds, not retransmission counts.
        func confirmed(from lower: Int, through upper: Int) -> Bool {
            let seconds = Set(samples.lazy.filter {
                lower <= $0.unix && $0.unix <= upper && valid($0)
                    && $0.sleepState == 2 && ($0.dynamicAccelG ?? .infinity) <= quietAccelG
            }.map(\.unix))
            return seconds.count >= 15 * 60
        }
        return confirmed(from: max(previous.startUnix, previous.endUnix - 30 * 60 + 1),
                         through: previous.endUnix)
            && confirmed(from: next.startUnix,
                         through: min(next.endUnix, next.startUnix + 30 * 60 - 1))
    }

    static func totalHours(_ periods: [SleepPeriod]) -> Double {
        periods.reduce(0.0) { $0 + $1.hours }
    }
    
    // MARK: - NOOP Parity Helper Functions
    
    /// Check if run is deeply quiescent: wrist barely moved AND posture unchanged.
    /// NOOP's runIsDeeplyQuiescent: gravity vector delta < threshold for all samples.
    private static func runIsDeeplyQuiescent(_ run: [V18Sample]) -> Bool {
        guard run.count >= 2 else { return false }
        let gravitySamples = run.compactMap { $0.gravityXG != nil && $0.gravityYG != nil && $0.gravityZG != nil ? $0 : nil }
        guard gravitySamples.count >= 2 else { return false }
        // Check gravity vector stability (posture unchanged)
        let refX = gravitySamples[0].gravityXG!
        let refY = gravitySamples[0].gravityYG!
        let refZ = gravitySamples[0].gravityZG!
        for s in gravitySamples.dropFirst() {
            let dx = abs(s.gravityXG! - refX)
            let dy = abs(s.gravityYG! - refY)
            let dz = abs(s.gravityZG! - refZ)
            if dx > 0.05 || dy > 0.05 || dz > 0.05 {
                return false
            }
        }
        // Check motion is minimal
        for s in run {
            if let accel = s.dynamicAccelG, accel > 0.01 {
                return false
            }
        }
        return true
    }
    
    /// Measure off-wrist COVERAGE as union of HR gaps + wrist-off events.
    /// NOOP measures off-wrist fraction, drops run only when >= 50%.
    private static func computeOffWristFraction(_ run: [V18Sample], in ordered: [V18Sample]) -> Double {
        guard let runStart = run.first?.unix, let runEnd = run.last?.unix else { return 1.0 }
        let runDuration = runEnd - runStart + 1
        guard runDuration > 0 else { return 1.0 }
        
        var offWristSeconds = Set<Int>()
        // Off-wrist from wearing flag
        for s in ordered {
            if runStart <= s.unix && s.unix <= runEnd {
                if !s.wearing {
                    offWristSeconds.insert(s.unix)
                }
            }
        }
        // Add long HR gaps (missing seconds in run)
        let runUnixes = Set(run.map(\.unix))
        let expected = Set(runStart...runEnd)
        let missing = expected.subtracting(runUnixes)
        offWristSeconds.formUnion(missing)
        
        return Double(offWristSeconds.count) / Double(runDuration)
    }
}
