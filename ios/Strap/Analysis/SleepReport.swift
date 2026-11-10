import Foundation

/// Sleep performance and consistency, ported from `whoop/sleep_analysis.py`.
/// A transparent local composite — NOT WHOOP's Sleep Performance and not the
/// Phillips 2017 Sleep Regularity Index, which needs full-day epoch data.
enum SleepReport {
    static let consistencyToleranceMin = 60
    static let minConsistencyNights = 2
    static let stressWindowS = 300

    // MARK: - Consistency

    static func minutesOfDay(_ unix: Int) -> Int {
        ((unix / 60) % 1440 + 1440) % 1440
    }

    static func circularDeviation(_ a: Int, _ b: Int) -> Int {
        let distance = abs(a - b) % 1440
        return min(distance, 1440 - distance)
    }

    /// Same rule as the Python reference: choose the candidate value with the
    /// lowest total circular distance, first minimum on a tie.
    static func circularMedian(_ values: [Int]) -> Int {
        var best = values[0]
        var bestCost = Int.max
        for candidate in values {
            let cost = values.reduce(0) { $0 + circularDeviation(candidate, $1) }
            if cost < bestCost {
                bestCost = cost
                best = candidate
            }
        }
        return best
    }

    /// Percent of nights whose bedtime AND wake time sit within +/-60 min of
    /// the personal medians, plus how many nights were usable.
    static func consistency(nights: [NightSpan]) -> (pct: Double?, nights: Int) {
        let usable = nights.filter { $0.endUnix > $0.startUnix }
        guard usable.count >= minConsistencyNights else { return (nil, usable.count) }
        let beds = usable.map { minutesOfDay($0.startUnix) }
        let wakes = usable.map { minutesOfDay($0.endUnix) }
        let bedMedian = circularMedian(beds)
        let wakeMedian = circularMedian(wakes)
        var consistent = 0
        for (bed, wake) in zip(beds, wakes)
        where circularDeviation(bed, bedMedian) <= consistencyToleranceMin
            && circularDeviation(wake, wakeMedian) <= consistencyToleranceMin {
            consistent += 1
        }
        let pct = 100.0 * Double(consistent) / Double(usable.count)
        return (Stats.rounded(pct, 1), usable.count)
    }

    // MARK: - Sleep stress

    private struct StressBucket: Hashable {
        let period: Int
        let window: Int
    }

    /// Share of 5-minute sleep windows in each stress band, scored against the
    /// sleep baseline. High >= 2 SD below the norm, medium >= 1 SD, matching
    /// the daytime stress rule. Unavailable until 7 sleep nights exist.
    static func stressSplit(
        samples: [V18Sample],
        periods: [SleepPeriod],
        baseline: Baseline?
    ) -> SleepStressSplit {
        guard let baseline, baseline.days >= Recovery.minBaselineDays else {
            return SleepStressSplit(
                highPct: nil, mediumPct: nil, lowPct: nil, windows: 0,
                reason: "needs at least \(Recovery.minBaselineDays) sleep nights of baseline"
            )
        }
        var buckets: [StressBucket: [Double]] = [:]
        for sample in samples {
            guard sample.wearing, !sample.rrIntervalsMS.isEmpty else { continue }
            for (periodIndex, period) in periods.enumerated()
            where period.startUnix <= sample.unix && sample.unix <= period.endUnix {
                let key = StressBucket(
                    period: periodIndex,
                    window: (sample.unix - period.startUnix) / stressWindowS
                )
                buckets[key, default: []].append(contentsOf: sample.rrIntervalsMS.map(Double.init))
                break
            }
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
            return SleepStressSplit(
                highPct: nil, mediumPct: nil, lowPct: nil, windows: 0,
                reason: "no R-R beats in the sleep windows"
            )
        }
        let total = Double(scored)
        return SleepStressSplit(
            highPct: Stats.rounded(100.0 * Double(high) / total, 1),
            mediumPct: Stats.rounded(100.0 * Double(medium) / total, 1),
            lowPct: Stats.rounded(100.0 * Double(low) / total, 1),
            windows: scored,
            reason: nil
        )
    }

    // MARK: - Composite

    /// Equal-weight mean of whichever components are available. WHOOP's
    /// weighting is proprietary; this is our own composite.
    static func analyze(
        samples: [V18Sample],
        periods: [SleepPeriod],
        needHours: Double,
        nights: [NightSpan],
        sleepBaseline: Baseline?
    ) -> SleepAnalysis? {
        guard !periods.isEmpty, needHours > 0 else { return nil }
        let hours = SleepDetect.totalHours(periods)
        let totalSeconds = periods.reduce(0) { $0 + $1.durationS }
        let efficiency = 100.0
            * periods.reduce(0.0) { $0 + $1.quietFraction * Double($1.durationS) }
            / Double(totalSeconds)
        let consistencyResult = consistency(nights: nights)
        let stress = stressSplit(samples: samples, periods: periods, baseline: sleepBaseline)
        let hoursComponent = min(100.0, 100.0 * hours / needHours)

        var components: [Double] = [hoursComponent, efficiency]
        if let pct = consistencyResult.pct { components.append(pct) }
        if let high = stress.highPct { components.append(100.0 - high) }

        return SleepAnalysis(
            hours: hours,
            needHours: needHours,
            hoursVsNeededPct: Stats.rounded(hoursComponent, 1),
            efficiencyPct: Stats.rounded(efficiency, 1),
            wakeEvents: periods.reduce(0) { $0 + $1.wakeEvents },
            consistencyPct: consistencyResult.pct,
            consistencyNights: consistencyResult.nights,
            stress: stress,
            performancePct: Stats.rounded(Stats.mean(components), 1)
        )
    }
}
