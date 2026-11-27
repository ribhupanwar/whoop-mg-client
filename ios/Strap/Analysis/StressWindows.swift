import Foundation

/// Awake stress share: the same 5-minute lnRMSSD windows as the sleep split,
/// but scored against the awake-quiet baseline. Used by the Stress detail
/// screen for the whole day and again with workouts removed. Local estimate,
/// not any proprietary algorithm.
enum StressWindows {
    static let windowSeconds = 300
    static let maxRestingAccelG = Hrv.restingQuietAccelG
    // Match the existing five-minute HRV coverage floor, not a WHOOP calibration.
    static let minimumCoveredSeconds = 150
    static let minimumRRDurationSeconds = 75.0

    static func outsideWorkouts(
        samples: [V18Sample], baseline: Baseline?, sleep: [(start: Int, end: Int)],
        activities: [ActivitySession], isDeleted: (ActivitySession) -> Bool
    ) -> StressSplit {
        let workouts = activities.filter { !isDeleted($0) }.map { (start: $0.startUnix, end: $0.endUnix) }
        return share(samples: samples, baseline: baseline, excluded: sleep + workouts)
    }

    private static func bucketedRR(
        samples: [V18Sample],
        excluded: [(start: Int, end: Int)]
    ) -> (buckets: [Int: [V18Sample]], coveredSeconds: [Int: Int]) {
        var uniqueBySecond: [Int: V18Sample] = [:]
        for sample in samples {
            guard sample.wearing, !sample.rrIntervalsMS.isEmpty else { continue }
            guard let accel = sample.dynamicAccelG, accel.isFinite,
                  (0...maxRestingAccelG).contains(accel) else { continue }
            if excluded.contains(where: { $0.start <= sample.unix && sample.unix <= $0.end }) {
                continue
            }
            if let previous = uniqueBySecond[sample.unix],
               !Hrv.preferRetransmittedRR(sample.rrIntervalsMS, over: previous.rrIntervalsMS) {
                continue
            }
            uniqueBySecond[sample.unix] = sample
        }
        var buckets: [Int: [V18Sample]] = [:]
        var coveredSeconds: [Int: Int] = [:]
        var firstUnixByBucket: [Int: Int] = [:]
        var lastUnixByBucket: [Int: Int] = [:]
        for unix in uniqueBySecond.keys.sorted() {
            let sample = uniqueBySecond[unix]!
            let rr = sample.rrIntervalsMS.map(Double.init).filter { (300...2000).contains($0) }
            guard !rr.isEmpty else { continue }
            let bucket = unix / windowSeconds
            coveredSeconds[bucket, default: 0] += 1
            if firstUnixByBucket[bucket] == nil { firstUnixByBucket[bucket] = unix }
            lastUnixByBucket[bucket] = unix
            buckets[bucket, default: []].append(sample)
        }
        // Reject over-counted buckets whose total beat duration exceeds elapsed span by > 5%.
        for (bucket, records) in buckets {
            if let first = firstUnixByBucket[bucket], let last = lastUnixByBucket[bucket] {
                let elapsed = max(1, last - first + 1)
                let totalRRS = records.flatMap(\.rrIntervalsMS).filter { (300...2000).contains($0) }.reduce(0.0) { $0 + Double($1) } / 1000.0
                if records.count < minimumCoveredSeconds || totalRRS < minimumRRDurationSeconds || totalRRS > Double(elapsed) * 1.05 {
                    buckets.removeValue(forKey: bucket)
                    coveredSeconds.removeValue(forKey: bucket)
                }
            }
        }
        return (buckets, coveredSeconds)
    }

    /// Share of awake windows in each stress band. `excluded` drops windows
    /// inside sleep periods (for the awake split) and detected workouts (for
    /// the outside-workouts split).
    static func share(
        samples: [V18Sample],
        baseline: Baseline?,
        excluded: [(start: Int, end: Int)] = []
    ) -> StressSplit {
        guard let baseline, baseline.days >= Recovery.minBaselineDays else {
            return StressSplit(
                highPct: nil, mediumPct: nil, lowPct: nil, windows: 0,
                reason: "needs at least \(Recovery.minBaselineDays) awake-baseline days"
            )
        }
        let (buckets, coveredSecondsByBucket) = bucketedRR(samples: samples, excluded: excluded)

        var high = 0
        var medium = 0
        var low = 0
        var scored = 0
        var completeCoverage = true
        for (bucket, rr) in buckets {
            let result = Recovery.stressIndex(
                lnRMSSD: Hrv.fromSamples(rr, rrRange: 300...2000).lnRMSSD, baseline: baseline
            )
            guard let index = result.index else { continue }
            scored += 1
            if coveredSecondsByBucket[bucket] != windowSeconds { completeCoverage = false }
            if index >= Recovery.stressHighSD {
                high += 1
            } else if index >= Recovery.stressElevatedSD {
                medium += 1
            } else {
                low += 1
            }
        }
        guard scored > 0 else {
            return StressSplit(
                highPct: nil, mediumPct: nil, lowPct: nil, windows: 0,
                reason: "no R-R beats in awake windows"
            )
        }
        let total = Double(scored)
        return StressSplit(
            highPct: Stats.rounded(100.0 * Double(high) / total, 1),
            mediumPct: Stats.rounded(100.0 * Double(medium) / total, 1),
            lowPct: Stats.rounded(100.0 * Double(low) / total, 1),
            windows: scored,
            reason: nil,
            durationCoverageSeconds: completeCoverage ? scored * windowSeconds : nil
        )
    }

    /// Do not infer a full elapsed stress duration from sparse RR observations.
    /// A window can still contribute an estimated stress index without a duration.
    static func scoredSeconds(_ split: StressSplit) -> Double? {
        split.durationCoverageSeconds.map(Double.init)
    }

    /// The same scored windows as `share`, but kept as an ordered per-window
    /// series for the through-the-day chart. Empty until the baseline unlocks.
    static func series(
        samples: [V18Sample],
        baseline: Baseline?,
        excluded: [(start: Int, end: Int)] = []
    ) -> [StressPoint] {
        guard let baseline, baseline.days >= Recovery.minBaselineDays else { return [] }
        let (buckets, _) = bucketedRR(samples: samples, excluded: excluded)
        var points: [StressPoint] = []
        for bucket in buckets.keys.sorted() {
            let rr = buckets[bucket]!
            let result = Recovery.stressIndex(
                lnRMSSD: Hrv.fromSamples(rr, rrRange: 300...2000).lnRMSSD, baseline: baseline
            )
            guard let index = result.index else { continue }
            points.append(StressPoint(unix: bucket * windowSeconds, index: index,
                                      unclampedScore: result.diagnostics?.unclampedScore))
        }
        return points
    }
}
