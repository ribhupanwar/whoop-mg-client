import Foundation

/// Awake stress share: the same 5-minute lnRMSSD windows as the sleep split,
/// but scored against the awake-quiet baseline. Used by the Stress detail
/// screen for the whole day and again with workouts removed. Local estimate,
/// not any proprietary algorithm.
enum StressWindows {
    static let windowSeconds = 300

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
        var buckets: [Int: [Double]] = [:]
        for sample in samples {
            guard sample.wearing, !sample.rrIntervalsMS.isEmpty else { continue }
            if excluded.contains(where: { $0.start <= sample.unix && sample.unix <= $0.end }) {
                continue
            }
            buckets[sample.unix / windowSeconds, default: []]
                .append(contentsOf: sample.rrIntervalsMS.map(Double.init))
        }

        var high = 0
        var medium = 0
        var low = 0
        var scored = 0
        for rr in buckets.values {
            let result = Recovery.stressIndex(
                lnRMSSD: Hrv.fromRR(rr).lnRMSSD, baseline: baseline
            )
            guard let index = result.index else { continue }
            scored += 1
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
            reason: nil
        )
    }

    /// Seconds covered by the scored windows — the denominator a share turns
    /// into a duration.
    static func scoredSeconds(_ split: StressSplit) -> Double {
        Double(split.windows) * Double(windowSeconds)
    }

    /// The same scored windows as `share`, but kept as an ordered per-window
    /// series for the through-the-day chart. Empty until the baseline unlocks.
    static func series(
        samples: [V18Sample],
        baseline: Baseline?,
        excluded: [(start: Int, end: Int)] = []
    ) -> [StressPoint] {
        guard let baseline, baseline.days >= Recovery.minBaselineDays else { return [] }
        var buckets: [Int: [Double]] = [:]
        for sample in samples {
            guard sample.wearing, !sample.rrIntervalsMS.isEmpty else { continue }
            if excluded.contains(where: { $0.start <= sample.unix && sample.unix <= $0.end }) {
                continue
            }
            buckets[sample.unix / windowSeconds, default: []]
                .append(contentsOf: sample.rrIntervalsMS.map(Double.init))
        }
        var points: [StressPoint] = []
        for bucket in buckets.keys.sorted() {
            let rr = buckets[bucket]!
            guard let index = Recovery.stressIndex(
                lnRMSSD: Hrv.fromRR(rr).lnRMSSD, baseline: baseline
            ).index else { continue }
            points.append(StressPoint(unix: bucket * windowSeconds, index: index))
        }
        return points
    }
}
