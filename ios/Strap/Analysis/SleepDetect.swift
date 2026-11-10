import Foundation

/// Actigraphy + heart-rate-drop sleep detector ported from `whoop/health.py`.
/// Duration and continuity only: no light/deep/REM staging.
enum SleepDetect {
    static let quietAccelG = 0.08
    static let minSleepS = 1800
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
            guard let accel = sample.dynamicAccelG else { return false }
            return accel <= quietAccelG
        }
        let activeHRs = zip(ordered, quiet)
            .filter { !$0.1 && $0.0.wearing }
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

            let runHRs = run.filter { $0.wearing }.map { Double($0.heartRate) }
            guard !runHRs.isEmpty,
                  Stats.median(runHRs) <= activeMedian - hrDropBPM else { continue }

            let quietSeconds = quiet[start..<end].filter { $0 }.count
            var wakeEvents = 0
            if end > start + 1 {
                for second in (start + 1)..<end where !quiet[second] && quiet[second - 1] {
                    wakeEvents += 1
                }
            }
            periods.append(
                SleepPeriod(
                    startUnix: run[0].unix,
                    endUnix: run[run.count - 1].unix,
                    quietFraction: Double(quietSeconds) / Double(run.count),
                    meanHR: Stats.mean(runHRs),
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
