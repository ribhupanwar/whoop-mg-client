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

    /// Sustained-quiet periods confirmed by a heart-rate drop.
    ///
    /// Motion alone is not enough — sitting still at a desk is not sleep — so
    /// a candidate must also sit below the capture's active median by
    /// `hrDropBPM`. With no active seconds to compare against, the period is
    /// rejected rather than assumed.
    static func detect(
        _ samples: [V18Sample],
        quietAccelG: Double = SleepDetect.quietAccelG,
        minSleepS: Int = SleepDetect.minSleepS,
        gapToleranceS: Int = SleepDetect.gapToleranceS,
        hrDropBPM: Double = SleepDetect.hrDropBPM
    ) -> [SleepPeriod] {
        let ordered = samples.sorted { $0.unix < $1.unix }
        guard !ordered.isEmpty else { return [] }

        let quiet = ordered.map { sample in
            guard let accel = sample.dynamicAccelG, accel.isFinite, accel >= 0 else { return false }
            return sample.wearing && (35...220).contains(sample.heartRate) && accel <= quietAccelG
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
            let run = Array(ordered[start..<end])
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
                  !runHRs.isEmpty,
                  Stats.median(runHRs) <= activeMedian - hrDropBPM else { continue }
            // A waking HR spike can make sedentary rest appear to have a
            // large HR drop. Require the candidate's lowest sustained HR
            // to be below the waking reference as an independent check.
            if daytime {
                guard let resting = Hrv.minimumRollingMean(runHRs, window: 300),
                      resting <= activeMedian * 0.95 else { continue }
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
            if (8..<24).contains(startHour) {
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
            }
            // A trimmed onset must still leave a real sleep-length window.
            // Otherwise an hours-long quiet evening with only a few minutes
            // of declared sleep could pass the earlier duration check.
            guard run[run.count - 1].unix - verifiedStart + 1 >= minSleepS else {
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
                      run.last!.unix - terminalUp.unix <= 60 {
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
            guard verifiedEnd - verifiedStart + 1 >= minSleepS,
                  verifiedEnd - verifiedStart + 1 <= maxSleepS else { continue }

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
            var movingSeconds = 0
            var wakeEvents = 0
            var lastMovingUnix: Int? = nil
            for index in verifiedIndices {
                if !quiet[index] {
                    if ordered[index].unix != lastMovingUnix {
                        movingSeconds += 1
                        lastMovingUnix = ordered[index].unix
                    }
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
        return periods
    }

    static func totalHours(_ periods: [SleepPeriod]) -> Double {
        periods.reduce(0.0) { $0 + $1.hours }
    }
}
