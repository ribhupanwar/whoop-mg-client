import Foundation

/// Timestamped night-only HR. Empty minutes stay gaps rather than compressing time.
struct SleepHRPoint: Codable, Equatable, Identifiable {
    let unix: Int
    let bpm: Double
    var id: Int { unix }
}

/// The sole source of sleep durations on every screen. All ends here are exclusive.
/// A missing interval is unknown, never an awakening and never sleep debt.
struct SleepSession: Codable, Equatable {
    static let algorithmVersion = 2
    let version: Int
    let sourceStartUnix: Int
    let startUnix: Int
    let endUnix: Int
    let staging: SleepStaging
    let heartRate: [SleepHRPoint]
    let movementBouts: Int
    let isEdited: Bool

    var timeInBedHours: Double { Double(endUnix - startUnix) / 3600 }
    var classifiedAsleepHours: Double { staging.asleepMinutes / 60 }
    var classifiedAwakeHours: Double { staging.wakeMinutes / 60 }
    var unclassifiedHours: Double {
        max(0, timeInBedHours - classifiedAsleepHours - classifiedAwakeHours)
    }
    var isComplete: Bool { staging.stageable && unclassifiedHours < 1.0 / 3600 }
    /// Only a complete estimated night can drive need, Recovery or debt.
    var asleepHours: Double? { isComplete ? classifiedAsleepHours : nil }
    var awakeHours: Double? { isComplete ? classifiedAwakeHours : nil }
    var efficiencyPct: Double? {
        guard let asleepHours, timeInBedHours > 0 else { return nil }
        return 100 * asleepHours / timeInBedHours
    }
    var durationReason: String? {
        if let reason = staging.reason { return reason }
        if !isComplete { return "Part of this window has no usable HR; the full sleep duration is unknown." }
        return nil
    }

    /// Resolve each edit once, replacing overlapping detector fragments rather
    /// than summing the same corrected night twice.
    static func makeAll(
        samples: [V18Sample], periods: [SleepPeriod], overrides: [String: [Int]]
    ) -> [SleepSession] {
        let ordered = periods.sorted { $0.endUnix < $1.endUnix }
        var assigned: [Int: (distance: Int, times: [Int])] = [:]
        for key in overrides.keys.sorted() {
            guard let source = Int(key), let times = SleepCorrectionStore.validated(overrides[key]) else { continue }
            let candidate = ordered.enumerated().filter { _, period in
                if period.startUnix == source { return true }
                let overlap = min(period.endUnix + 1, times[1]) - max(period.startUnix, times[0])
                return abs(source - period.startUnix) <= 6 * 3600 && overlap > 0
                    && overlap * 2 >= min(period.durationS, times[1] - times[0])
            }.min { abs(source - $0.element.startUnix) < abs(source - $1.element.startUnix) }
            guard let candidate else { continue }
            let distance = abs(source - candidate.element.startUnix)
            if let previous = assigned[candidate.offset], previous.distance <= distance { continue }
            assigned[candidate.offset] = (distance, times)
        }
        let windows = assigned.values.map(\.times)
        var seen = Set<String>()
        var results: [SleepSession] = []
        for (index, period) in ordered.enumerated() {
            let edit = assigned[index]?.times
            if edit == nil && windows.contains(where: {
                max(period.startUnix, $0[0]) < min(period.endUnix + 1, $0[1])
            }) { continue }
            let start = edit?.first ?? period.startUnix
            let end = edit?.last ?? (period.endUnix + 1)
            guard seen.insert("\(start):\(end)").inserted else { continue }
            results.append(make(samples: samples, period: period, correctedTimes: edit))
        }
        return results.sorted { $0.endUnix < $1.endUnix }
    }

    static func make(
        samples: [V18Sample], period: SleepPeriod, correctedTimes: [Int]? = nil
    ) -> SleepSession {
        let times = SleepCorrectionStore.validated(correctedTimes)
        let start = times?.first ?? period.startUnix
        let end = times?.last ?? (period.endUnix + 1)
        let window = SleepPeriod(
            startUnix: start, endUnix: end - 1, quietFraction: period.quietFraction,
            meanHR: period.meanHR, wakeEvents: period.wakeEvents
        )
        let night = samples.filter { start <= $0.unix && $0.unix < end }
        var bySecond: [Int: V18Sample] = [:]
        for sample in night where sample.wearing && (35...220).contains(sample.heartRate) {
            if let old = bySecond[sample.unix], old.rrIntervalsMS.count >= sample.rrIntervalsMS.count { continue }
            bySecond[sample.unix] = sample
        }
        var buckets: [Int: [Double]] = [:]
        for sample in bySecond.values {
            buckets[sample.unix / 60, default: []].append(Double(sample.heartRate))
        }
        let hr = buckets.keys.sorted().map {
            SleepHRPoint(unix: max(start, $0 * 60), bpm: Stats.mean(buckets[$0]!))
        }
        // Count sustained movement episodes, not individual noisy one-second edges.
        // These are diagnostic bouts, NOT verified awakenings or awake subtraction.
        var movingSeconds: [Int: Int] = [:]
        for sample in bySecond.values {
            guard let accel = sample.dynamicAccelG, accel.isFinite,
                  accel > SleepDetect.quietAccelG else { continue }
            movingSeconds[(sample.unix - start) / 30, default: 0] += 1
        }
        let movingEpochs = movingSeconds.keys.filter { movingSeconds[$0]! >= 15 }.sorted()
        var bouts = 0
        var previous: Int?
        for epoch in movingEpochs {
            if previous == nil || epoch - previous! > 4 { bouts += 1 }
            previous = epoch
        }
        return SleepSession(
            version: algorithmVersion, sourceStartUnix: period.startUnix,
            startUnix: start, endUnix: end,
            staging: SleepStager.stage(samples: night, period: window),
            heartRate: hr, movementBouts: bouts, isEdited: times != nil
        )
    }
}

/// Existing saved corrections are bed/wake instants, with an EXCLUSIVE wake.
/// Recover a correction after a detector-onset change only for the same night.
enum SleepCorrectionStore {
    static let defaultsKey = "strap.sleep.time.corrections.v1"
    static func validated(_ times: [Int]?) -> [Int]? {
        guard let times, times.count == 2, times[0] > 0,
              times[1] > times[0], times[1] - times[0] <= 24 * 3600 else { return nil }
        return times
    }
    static func times(for period: SleepPeriod, overrides: [String: [Int]]) -> [Int]? {
        if let exact = validated(overrides[String(period.startUnix)]) { return exact }
        let candidates = overrides.compactMap { key, value -> (Int, [Int])? in
            guard let source = Int(key), abs(source - period.startUnix) <= 6 * 3600,
                  let times = validated(value) else { return nil }
            let overlap = min(period.endUnix + 1, times[1]) - max(period.startUnix, times[0])
            let shorter = min(period.durationS, times[1] - times[0])
            guard overlap > 0, overlap * 2 >= shorter else { return nil }
            return (abs(source - period.startUnix), times)
        }
        return candidates.min { $0.0 < $1.0 }?.1
    }
}
