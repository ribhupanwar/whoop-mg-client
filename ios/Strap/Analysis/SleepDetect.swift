import Foundation

/// Actigraphy + heart-rate-drop sleep detector ported from `whoop/health.py`.
/// It finds the window and scores duration/continuity; the four-class estimate
/// is a separate pass over that window in `SleepStager`.
enum SleepDetect {
    static let quietAccelG = 0.08
    static let minSleepS = 3600
    static let gapToleranceS = 300
    static let hrDropBPM = 5.0
    static let awakeMotionMinS = 120
    static let awakeMotionGapS = 20

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
            guard let accel = sample.dynamicAccelG else { return false }
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
            while index < ordered.count && closed[index] { index += 1 }
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
            if (18..<22).contains(startHour) && stateRows.count >= 300 {
                let sleepRows = run.filter { $0.sleepState == 2 }
                if let first = sleepRows.first, first.unix > verifiedStart {
                    verifiedStart = first.unix
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

            let wakeEvents = movementBoutCount(
                quiet: Array(quiet[start..<end]), unix: run.map(\.unix)
            )
            periods.append(
                SleepPeriod(
                    startUnix: verifiedStart,
                    endUnix: run[run.count - 1].unix,
                    quietFraction: estimatedAsleepFraction(
                        quiet: Array(quiet[start..<end]), unix: run.map(\.unix),
                        sleepStates: run.map(\.sleepState),
                        heartRates: run.map { Optional($0.heartRate) }
                    ),
                    meanHR: Stats.mean(runHRs),
                    wakeEvents: wakeEvents
                )
            )
        }
        return periods
    }

    /// Estimates asleep time without treating every small movement as an awakening.
    /// Sustained motion or a consistent band wake/up state contributes awake time.
    static func estimatedAsleepFraction(
        quiet: [Bool], unix: [Int], sleepStates: [Int?]? = nil,
        heartRates: [Int?]? = nil,
        minimumAwakeMotionS: Int = awakeMotionMinS, motionGapS: Int = awakeMotionGapS
    ) -> Double {
        guard quiet.count == unix.count, !unix.isEmpty else { return 0 }
        var awakeSeconds = Set<Int>()
        let states = sleepStates ?? Array(repeating: nil, count: unix.count)
        let statePairs = Array(zip(unix, states))
        let sleepStateSeconds = Set(statePairs.compactMap { pair -> Int? in pair.1 == 2 ? pair.0 : nil })
        let awakeStateSeconds = Set(statePairs.compactMap { pair -> Int? in
            pair.1 == 0 || pair.1 == 3 ? pair.0 : nil
        })
        let stateObserved = sleepStateSeconds.union(awakeStateSeconds)
        let reliableStateStream = sleepStateSeconds.count >= 300 && stateObserved.count >= 600
        if reliableStateStream { awakeSeconds.formUnion(awakeStateSeconds) }

        let validHR = (heartRates ?? []).compactMap { value -> Double? in
            guard let value, (35...220).contains(value) else { return nil }
            return Double(value)
        }
        // Movement during sleep is common. Only count a sustained motion bout
        // as awake when heart rate is also materially elevated above this
        // window's median; band wake/up states remain the direct signal.
        let motionWakeThreshold = validHR.isEmpty ? nil : Stats.median(validHR) + 10
        let elevatedHRSeconds: Set<Int>
        if let threshold = motionWakeThreshold, let heartRates, heartRates.count == unix.count {
            elevatedHRSeconds = Set(zip(unix, heartRates).compactMap { timestamp, value in
                guard let value, (35...220).contains(value), Double(value) >= threshold else { return nil }
                return timestamp
            })
        } else {
            elevatedHRSeconds = []
        }

        var motionStart: Int?
        var lastMotion: Int?
        func closeMotionBout() {
            guard let motionStart, let lastMotion else { return }
            let duration = lastMotion - motionStart + 1
            guard duration >= minimumAwakeMotionS else { return }
            let bout = Set(motionStart...lastMotion)
            let elevatedCount = bout.intersection(elevatedHRSeconds).count
            guard elevatedCount * 2 >= duration else { return }
            awakeSeconds.formUnion(bout)
        }
        for index in unix.indices {
            let timestamp = unix[index]
            if !quiet[index] {
                if let previous = lastMotion, timestamp - previous > motionGapS {
                    closeMotionBout()
                    motionStart = nil
                    lastMotion = nil
                }
                if motionStart == nil { motionStart = timestamp }
                lastMotion = timestamp
            } else if let previous = lastMotion, timestamp - previous > motionGapS {
                closeMotionBout()
                motionStart = nil
                lastMotion = nil
            }
        }
        closeMotionBout()
        let observed = Set(unix)
        guard !observed.isEmpty else { return 0 }
        return 1.0 - Double(awakeSeconds.intersection(observed).count) / Double(observed.count)
    }

    /// Counts coarse motion bouts, never individual movement samples or verified awakenings.
    /// A bout needs 30 seconds of observed motion; gaps up to 20 seconds are coalesced.
    static func movementBoutCount(quiet: [Bool], unix: [Int], minimumDurationS: Int = 30, gapToleranceS: Int = 20) -> Int {
        guard quiet.count == unix.count else { return 0 }
        var bouts = 0
        var start: Int?
        var lastMovement: Int?
        var lastCountedSecond: Int?
        var activeSeconds = 0
        func closeBout() {
            if start != nil && activeSeconds >= minimumDurationS { bouts += 1 }
        }
        func resetBout() {
            start = nil
            lastMovement = nil
            lastCountedSecond = nil
            activeSeconds = 0
        }
        for (index, timestamp) in unix.enumerated() {
            if !quiet[index] {
                if let previousMovement = lastMovement, timestamp - previousMovement > gapToleranceS {
                    closeBout(); resetBout()
                }
                if start == nil { start = timestamp }
                if lastCountedSecond != timestamp {
                    activeSeconds += 1
                    lastCountedSecond = timestamp
                }
                lastMovement = timestamp
            } else if let previousMovement = lastMovement, timestamp - previousMovement > gapToleranceS {
                closeBout(); resetBout()
            }
        }
        closeBout()
        return bouts
    }

    static func totalHours(_ periods: [SleepPeriod]) -> Double {
        periods.reduce(0.0) { $0 + $1.hours }
    }
}
