import Foundation

/// Reverse-engineered WHOOP-style strain estimator, independent of legacy TRIMP.
/// Source: user's extracted Whoop.app/strain_raw_scale_lookup.json (SHA-256
/// 10CD25BF8C560D39BE83FFB31E9B73CD8F58973BDEBFD3194135D8402C828301).
/// The raw formula is derived from Ghidra functions 0x1001eecac,
/// 0x1001eed98, 0x1001eee6c and 0x1001ee9ec. Exact sample alignment and
/// boundary behavior still require device-side validation.
enum WhoopDerivedStrain {
    static let lookup: [(raw: Double, score: Double)] = {
        guard let url = Bundle.main.url(forResource: "strain_raw_scale_lookup", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([[Double]].self, from: bytes),
              rows.count == 211,
              rows.allSatisfy({ $0.count == 2 }),
              rows.first == [0, 0], rows.last == [0.70195765, 21] else {
            return []
        }
        let values = rows.map { (raw: $0[0], score: $0[1]) }
        guard zip(values, values.dropFirst()).allSatisfy({ $0.0.raw < $0.1.raw && $0.0.score < $0.1.score }) else {
            return []
        }
        return values
    }()

    static func intensity(hr: Double, restingHR: Double, maxHR: Double) -> Double? {
        guard hr.isFinite, restingHR.isFinite, maxHR.isFinite,
              restingHR > 0, maxHR > restingHR else { return nil }
        let reserve = min(1, max(0, (hr - restingHR) / (maxHR + 3 - restingHR)))
        guard reserve > 0.30 else { return 0 }
        return 16 / (1 + exp((1 - reserve) / 0.15))
    }

    /// Integrate forward to the next observed sample, capped at 3 seconds.
    /// A terminal sample has no verified next timestamp and adds no duration.
    /// Invalid and off-wrist samples break continuity; duplicate seconds
    /// are collapsed before integration.
    static func raw(_ samples: [V18Sample], restingHR: Double, maxHR: Double) -> Double? {
        guard restingHR > 0, maxHR > restingHR,
              restingHR.isFinite, maxHR.isFinite else { return nil }
        let ordered = samples.sorted { $0.unix < $1.unix }
        var unique: [V18Sample] = []
        for sample in ordered where unique.last?.unix != sample.unix { unique.append(sample) }
        guard !unique.isEmpty else { return nil }
        var total = 0.0
        for index in 0..<max(0, unique.count - 1) {
            let current = unique[index], next = unique[index + 1]
            guard current.wearing, next.wearing,
                  (35...220).contains(current.heartRate),
                  (35...220).contains(next.heartRate),
                  let weight = intensity(hr: Double(current.heartRate),
                                         restingHR: restingHR, maxHR: maxHR) else { continue }
            let seconds = min(3, max(0, next.unix - current.unix))
            total += weight * Double(seconds) / 691200.0
        }
        return total
    }

    /// Midpoint classification (not linear interpolation). Boundary tie
    /// behavior follows the closest table entry, with ties selecting lower.
    static func display(raw: Double) -> Double? {
        guard raw.isFinite, raw >= 0, !lookup.isEmpty else { return nil }
        if raw >= lookup[lookup.count - 1].raw { return 21 }
        var low = 0, high = lookup.count - 1
        while low < high {
            let middle = (low + high) / 2
            if lookup[middle].raw < raw { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return lookup[0].score }
        let left = lookup[low - 1], right = lookup[low]
        return raw <= (left.raw + right.raw) / 2 ? left.score : right.score
    }

    /// Convert display score (0.0 to 21.0) back to raw integrated strain.
    static func raw(forScore score: Double) -> Double? {
        guard score.isFinite, !lookup.isEmpty else { return nil }
        let clamped = min(21.0, max(0.0, score))
        let index = min(lookup.count - 1, max(0, Int((clamped * 10).rounded())))
        return lookup[index].raw
    }

    /// Incremental step for live stream accumulation.
    /// Delta seconds is capped at 3 seconds per WHOOP 5.80.2 staleHeartRateInterval.
    static func accumulateStep(currentRaw: Double, hr: Double, deltaSeconds: Double, restingHR: Double, maxHR: Double) -> Double {
        guard let weight = intensity(hr: hr, restingHR: restingHR, maxHR: maxHR) else { return currentRaw }
        let dt = min(3.0, max(0.0, deltaSeconds))
        return currentRaw + weight * dt / 691200.0
    }

    static func score(_ samples: [V18Sample], restingHR: Double, maxHR: Double) -> Double? {
        guard let value = raw(samples, restingHR: restingHR, maxHR: maxHR) else { return nil }
        return display(raw: value)
    }
}
