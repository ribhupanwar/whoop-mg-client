import Foundation

/// Experimental arithmetic recovered from WHOOP 5.78.0 ARM64 excerpts.
/// No production call sites. See docs/WHOOP_CALORIE_ENGINE_HANDOFF.md.
/// This estimates energy over covered intervals INCLUDING resting energy;
/// it is neither a validated WHOOP active-calorie value nor a full-day total.
enum WhoopRecoveredCalories {
    /// Numeric cases deliberately avoid guessing physiological enum metadata.
    enum Baseline: Int, CaseIterable { case raw0 = 0, raw1 = 1, raw2Mean = 2 }
    struct Profile {
        let weightKg: Double
        let heightMeters: Double
        let ageYears: Double
        let baseline: Baseline
        // Application guards, not recovered WHOOP physiological acceptance bounds.
        fileprivate var valid: Bool {
            weightKg.isFinite && weightKg > 0 && heightMeters.isFinite && heightMeters > 0 &&
                ageYears.isFinite && ageYears >= 0
        }
    }
    enum Failure: Error, Equatable {
        case invalidProfile, invalidAnchors, invalidReferenceRate, countMismatch
        case outOfOrderTimestamps, noCoveredIntervals, nonFiniteResult, negativeInterpolatedRate
    }
    enum TailPolicy {
        /// No invented endpoint: last HR has no duration without a next timestamp.
        case observedIntervalsOnly
        /// Explicit experiment corresponding to the recovered append-last branch.
        /// Its binary count predicate is unresolved. Never enabled implicitly.
        case repeatFinalInterval
    }
    struct Result {
        let integratedKcal: Double
        let coveredSeconds: Double
        let restingKcalForCoveredSeconds: Double
        let excludedIntervals: Int
        let repeatedTailSeconds: Double
        /// A mathematical difference, NOT a verified WHOOP active-energy field.
        var netAboveRestingKcal: Double { integratedKcal - restingKcalForCoveredSeconds }
    }
    static let intervalCapSeconds = 3.0

    static func restingKcalPerSecond(_ profile: Profile) throws -> Double {
        guard profile.valid else { throw Failure.invalidProfile }
        let w = profile.weightKg, h = profile.heightMeters, a = profile.ageYears
        let firstDaily = 88.362 + 13.397 * w + 479.9 * h - 5.677 * a
        let secondDaily = 447.593 + 9.247 * w + 309.8 * h - 4.33 * a
        guard firstDaily.isFinite, secondDaily.isFinite else { throw Failure.nonFiniteResult }
        let first = max(0, firstDaily) / 86400
        let second = max(0, secondDaily) / 86400
        let value: Double
        switch profile.baseline {
        case .raw0: value = first
        case .raw1: value = second
        case .raw2Mean: value = (first + second) / 2
        }
        guard value.isFinite else { throw Failure.nonFiniteResult }
        return value
    }
    static func workoutKcalPerSecond(hr: Double, maxHR: Double, profile: Profile) throws -> Double {
        guard profile.valid else { throw Failure.invalidProfile }
        return try workoutKcalPerSecond(hr: hr, maxHR: maxHR, weightKg: profile.weightKg,
            ageYears: profile.ageYears, rawBaseline: profile.baseline.rawValue)
    }
    /// Unlike resting enum metadata, the recovered workout helper explicitly
    /// averages every raw value other than 0/1. Height is not an input here.
    static func workoutKcalPerSecond(hr: Double, maxHR: Double, weightKg: Double,
                                     ageYears: Double, rawBaseline: Int) throws -> Double {
        guard weightKg.isFinite, weightKg > 0, ageYears.isFinite, ageYears >= 0 else { throw Failure.invalidProfile }
        guard hr.isFinite, hr > 0, maxHR.isFinite, maxHR > 0 else { throw Failure.invalidAnchors }
        let capped = min(hr, maxHR), a = ageYears, w = weightKg
        let firstNumerator = 0.2 * a + 0.19 * w + 0.6 * capped - 50
        let secondNumerator = 0.07 * a - 0.13 * w + 0.4 * capped - 15
        guard firstNumerator.isFinite, secondNumerator.isFinite else { throw Failure.nonFiniteResult }
        let first = max(0, firstNumerator) / 251.04
        let second = max(0, secondNumerator) / 251.04
        let value: Double
        switch rawBaseline {
        case 0: value = first
        case 1: value = second
        default: value = (first + second) / 2
        }
        guard value.isFinite else { throw Failure.nonFiniteResult }
        return value
    }
    static func threshold(restingHR: Double, maxHR: Double) throws -> Double {
        guard restingHR.isFinite, restingHR > 0, maxHR.isFinite, maxHR > restingHR else { throw Failure.invalidAnchors }
        let value = restingHR + 0.30 * (maxHR - restingHR)
        guard value.isFinite, maxHR > value else { throw Failure.invalidAnchors }
        return value
    }
    struct Interpolation {
        let threshold: Double
        let restingRate: Double
        let slope: Double
        let intercept: Double
        func rate(hr: Double) throws -> Double {
            guard hr.isFinite, hr > 0 else { throw Failure.invalidAnchors }
            // Caller ARM64 uses raw input HR here. Only the separate workout
            // helper has a proven maxHR cap; do not invent another clamp.
            let value = hr < threshold ? restingRate : intercept + slope * hr
            guard value.isFinite else { throw Failure.nonFiniteResult }
            guard value >= 0 else { throw Failure.negativeInterpolatedRate }
            return value
        }
    }
    /// Explicit reference anchor avoids guessing the unresolved caller's source
    /// of referenceRate. Choosing workoutKcalPerSecond(hr:maxHR,...) is a
    /// caller experiment, not an assertion of binary call-site equivalence.
    static func interpolation(restingRate: Double, referenceRate: Double,
                              restingHR: Double, maxHR: Double) throws -> Interpolation {
        guard restingRate.isFinite, restingRate >= 0, referenceRate.isFinite, referenceRate >= 0 else {
            throw Failure.invalidReferenceRate
        }
        let t = try threshold(restingHR: restingHR, maxHR: maxHR)
        let slope = (referenceRate - restingRate) / (maxHR - t)
        let intercept = restingRate - t * slope
        guard slope.isFinite, intercept.isFinite else { throw Failure.nonFiniteResult }
        return Interpolation(threshold: t, restingRate: restingRate, slope: slope, intercept: intercept)
    }
    /// Conservative interval construction. Missing/nonfinite timestamps break
    /// adjacency; valid timestamps must be nondecreasing, never silently sorted.
    /// Duplicate timestamps have zero duration. No gap contributes >3 seconds.
    static func durations(timestamps: [Double?], tailPolicy: TailPolicy) throws -> [Double] {
        var previousFinite: Double?
        for case let timestamp? in timestamps where timestamp.isFinite {
            if let previousFinite, timestamp < previousFinite { throw Failure.outOfOrderTimestamps }
            previousFinite = timestamp
        }
        guard !timestamps.isEmpty else { return [] }
        var result = [Double](repeating: 0, count: timestamps.count)
        if timestamps.count > 1 {
            for index in 0..<(timestamps.count - 1) {
                guard let start = timestamps[index], let end = timestamps[index + 1], start.isFinite, end.isFinite else { continue }
                let difference = end - start
                guard difference.isFinite else { throw Failure.nonFiniteResult }
                result[index] = min(intervalCapSeconds, max(0, difference))
            }
            if case .repeatFinalInterval = tailPolicy { result[result.count - 1] = result[result.count - 2] }
        }
        return result
    }
    static func integrate(heartRates: [Double?], timestamps: [Double?], profile: Profile,
                          restingHR: Double, maxHR: Double, referenceRate: Double,
                          tailPolicy: TailPolicy) throws -> Result {
        guard heartRates.count == timestamps.count else { throw Failure.countMismatch }
        let rest = try restingKcalPerSecond(profile)
        let line = try interpolation(restingRate: rest, referenceRate: referenceRate, restingHR: restingHR, maxHR: maxHR)
        let seconds = try durations(timestamps: timestamps, tailPolicy: tailPolicy)
        var energy = 0.0, covered = 0.0, tail = 0.0
        var excluded = 0
        func validHR(_ value: Double?) -> Bool { value.map { $0.isFinite && $0 > 0 } ?? false }
        for index in heartRates.indices {
            let last = index == heartRates.count - 1
            let neighborValid = last ? (index > 0 && validHR(heartRates[index - 1])) : validHR(heartRates[index + 1])
            guard seconds[index] > 0, validHR(heartRates[index]), neighborValid, let hr = heartRates[index] else {
                excluded += 1; continue
            }
            let contribution = try line.rate(hr: hr) * seconds[index]
            guard contribution.isFinite, (energy + contribution).isFinite, (covered + seconds[index]).isFinite else {
                throw Failure.nonFiniteResult
            }
            energy += contribution; covered += seconds[index]
            if last { tail = seconds[index] }
        }
        guard covered > 0 else { throw Failure.noCoveredIntervals }
        let basal = rest * covered
        guard basal.isFinite else { throw Failure.nonFiniteResult }
        return Result(integratedKcal: energy, coveredSeconds: covered, restingKcalForCoveredSeconds: basal,
                      excludedIntervals: excluded, repeatedTailSeconds: tail)
    }
}
