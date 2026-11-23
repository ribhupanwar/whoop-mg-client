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
    // v6 invalidates v5 sleep-stage estimates that could classify prolonged
    // V18 sleepState=3 ("up") as Deep/Light. The retained sensor archive and
    // authoritative manual bed/wake corrections are not modified.
    static let algorithmVersion = 7
    let version: Int
    let sourceStartUnix: Int
    let startUnix: Int
    let endUnix: Int
    let staging: SleepStaging
    let heartRate: [SleepHRPoint]
    let movementBouts: Int
    let isEdited: Bool
    /// Original detector wake (exclusive), retained even if an edit excludes its tail.
    var sourceEndUnix: Int? = nil
    /// Recorded evidence, rather than duration or inactivity, identifies a nap.
    var bandSleepConfirmed: Bool? = nil
    var timezoneIdentifier: String? = nil

    enum Classification { case overnight, nap, pendingCandidate }
    var classification: Classification {
        var calendar = Calendar.current
        if let timezoneIdentifier, let zone = TimeZone(identifier: timezoneIdentifier) { calendar.timeZone = zone }
        let hour = calendar.component(.hour, from: Date(timeIntervalSince1970: Double(startUnix)))
        guard (8..<18).contains(hour) else { return .overnight }
        return bandSleepConfirmed == true || isEdited ? .nap : .pendingCandidate
    }


    var sourcePeriod: SleepPeriod {
        SleepPeriod(startUnix: sourceStartUnix,
                    endUnix: max(sourceStartUnix + 1, sourceEndUnix ?? endUnix) - 1,
                    quietFraction: 0, meanHR: 0, wakeEvents: 0)
    }

    var timeInBedHours: Double { Double(endUnix - startUnix) / 3600 }
    var classifiedAsleepHours: Double { staging.asleepMinutes / 60 }
    var classifiedAwakeHours: Double { staging.wakeMinutes / 60 }
    var unclassifiedHours: Double {
        max(0, timeInBedHours - classifiedAsleepHours - classifiedAwakeHours)
    }
    var isComplete: Bool {
        guard staging.stageable, timeInBedHours > 0 else { return false }
        let classified = classifiedAsleepHours + classifiedAwakeHours
        // Both missing epochs and over-counted epochs invalidate a duration.
        // Clamping a negative gap to zero must not turn bad staging into
        // a complete night or yield efficiency above 100%.
        return abs(timeInBedHours - classified) < 1.0 / 3600
    }
    /// Only a complete estimated night can drive need, Recovery or debt.
    var asleepHours: Double? { isComplete ? classifiedAsleepHours : nil }
    var awakeHours: Double? { isComplete ? classifiedAwakeHours : nil }
    var efficiencyPct: Double? {
        guard let asleepHours, timeInBedHours > 0 else { return nil }
        return 100 * asleepHours / timeInBedHours
    }
    /// A manual end action belongs to a current window at the archive frontier.
    /// A detector window with newer observations has already ended.
    func canEndNow(lastObservedUnix: Int?, nowUnix: Int) -> Bool {
        guard !isEdited, let lastObservedUnix, endUnix > startUnix,
              endUnix - 1 == lastObservedUnix, nowUnix >= lastObservedUnix,
              nowUnix - lastObservedUnix <= 15 * 60,
              nowUnix > startUnix, nowUnix - startUnix <= 86_400 else { return false }
        return true
    }

    var durationReason: String? {
        if let reason = staging.reason { return reason }
        if !isComplete { return "Part of this window has no usable HR; the full sleep duration is unknown." }
        return nil
    }

    /// Apply authoritative saved bounds immediately, without doing staging on
    /// the UI thread or briefly restoring an older persisted score on relaunch.
    func applyingSavedBounds(_ overrides: [String: [Int]]) -> SleepSession {
        guard let times = SleepCorrectionStore.times(for: sourcePeriod, overrides: overrides) else { return self }
        let changed = times[0] != startUnix || times[1] != endUnix
        let pending = SleepStaging(segments: [], deepMinutes: 0, lightMinutes: 0,
            remMinutes: 0, wakeMinutes: 0, epochs: 0, hrCoverage: 0,
            reason: "Recalculating the saved sleep window from recorded sensor data.")
        return SleepSession(version: version, sourceStartUnix: sourceStartUnix,
            startUnix: times[0], endUnix: times[1], staging: changed ? pending : staging,
            heartRate: changed ? heartRate.filter { times[0] <= $0.unix && $0.unix < times[1] } : heartRate,
            movementBouts: changed ? 0 : movementBouts, isEdited: true, sourceEndUnix: sourceEndUnix ?? endUnix,
            bandSleepConfirmed: bandSleepConfirmed, timezoneIdentifier: timezoneIdentifier)
    }

    /// Resolve each edit once, replacing overlapping detector fragments rather
    /// than summing the same corrected night twice.
    static func makeAll(
        samples: [V18Sample], periods: [SleepPeriod], overrides: [String: [Int]],
        cache: HistoryAnalysisCache? = nil, progress: ((Int, Int, Bool) -> Void)? = nil
    ) -> [SleepSession] {
        let ordered = periods.sorted { $0.endUnix < $1.endUnix }
        var assigned: [Int: (distance: Int, times: [Int])] = [:]
        for key in overrides.keys.sorted() {
            guard let source = Int(key), let times = SleepCorrectionStore.validated(overrides[key]) else { continue }
            // Reuse the same overflow-safe alias distance as saved correction
            // lookup. A corrupt extreme source key must not crash makeAll.
            let candidates = ordered.enumerated().compactMap { index, period -> (index: Int, distance: Int)? in
                guard let distance = SleepCorrectionStore.sourceDistance(source, period.startUnix) else { return nil }
                if period.startUnix == source { return (index, distance) }
                let overlap = min(period.endUnix + 1, times[1]) - max(period.startUnix, times[0])
                guard overlap > 0, overlap * 2 >= min(period.durationS, times[1] - times[0]) else { return nil }
                return (index, distance)
            }
            guard let candidate = candidates.min(by: { $0.distance < $1.distance }) else { continue }
            let distance = candidate.distance
            if let previous = assigned[candidate.index], previous.distance <= distance { continue }
            assigned[candidate.index] = (distance, times)
        }
        // Old caches can contain multiple edits recovered onto different fragments.
        // Prefer the closest source (then latest source), and never count overlapping edits twice.
        var accepted: [Int: (distance: Int, times: [Int])] = [:]
        for index in assigned.keys.sorted(by: {
            guard let lhs = assigned[$0], let rhs = assigned[$1] else { return false }
            return lhs.distance == rhs.distance
                ? ordered[$0].startUnix > ordered[$1].startUnix
                : lhs.distance < rhs.distance
        }) {
            guard let candidate = assigned[index] else { continue }
            guard !accepted.values.contains(where: {
                max($0.times[0], candidate.times[0]) < min($0.times[1], candidate.times[1])
            }) else { continue }
            accepted[index] = candidate
        }
        assigned = accepted
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
            let resolved = cache?.night(samples: samples, period: period, correctedTimes: edit)
            results.append(resolved?.0 ?? make(samples: samples, period: period, correctedTimes: edit))
            progress?(results.count, ordered.count, resolved?.1 ?? false)
        }
        return results.sorted { $0.endUnix < $1.endUnix }
    }

    /// A complete-looking retained tail is not a newly measured full night.
    /// Preserve the saved canonical window/result unless all of it can be reanalyzed,
    /// or the user explicitly changed its bounds.
    static func retainingUncovered(
        previous: [SleepSession], fresh: [SleepSession], coverageStart: Int?, coverageEnd: Int?,
        samples: [V18Sample] = [], overrides: [String: [Int]] = [:],
        cache: HistoryAnalysisCache? = nil
    ) -> [SleepSession] {
        // No archive coverage must not erase a previously saved canonical night.
        guard let first = coverageStart, let last = coverageEnd else {
            // Preserve saved nights while accepting genuinely new, non-overlapping
            // sessions. No coverage is not evidence that either night vanished.
            var retained = previous.map { old -> SleepSession in
                let corrected = SleepCorrectionStore.times(for: old.sourcePeriod, overrides: overrides)
                guard let corrected,
                      corrected[0] != old.startUnix || corrected[1] != old.endUnix else { return old }
                // A new manual correction must take effect even if the archive
                // has no samples. The resulting stages remain explicitly unknown.
                return make(samples: samples, period: old.sourcePeriod, correctedTimes: corrected)
            }
            for candidate in fresh where !retained.contains(where: {
                max($0.startUnix, candidate.startUnix) < min($0.endUnix, candidate.endUnix)
            }) {
                retained.append(candidate)
            }
            return retained.sorted { $0.endUnix < $1.endUnix }
        }
        var result = fresh
        let latestPrevious = previous.max { $0.endUnix < $1.endUnix }
        // Algorithm upgrades invalidate calculation caches, not saved history.
        // Keep older canonical windows/edits until their full data can be staged.
        for old in previous {
            let source = old.sourcePeriod
            let sourceEnd = source.endUnix + 1
            let savedEdit = SleepCorrectionStore.times(for: source, overrides: overrides)
            let editedBoundsChanged = savedEdit.map { $0[0] != old.startUnix || $0[1] != old.endUnix } ?? false
            // A manually edited canonical night is authoritative even when
            // a later BLE replay covers the entire old interval. Only an
            // explicit newly saved correction may change its bounds.
            let unsupportedExtension = fresh.contains { candidate in
                guard candidate.startUnix < old.endUnix, old.startUnix < candidate.endUnix,
                      candidate.endUnix > old.endUnix, !candidate.isEdited else { return false }
                let tail = samples.filter { $0.unix >= old.endUnix && $0.unix < candidate.endUnix
                    && $0.wearing && (35...220).contains($0.heartRate) && $0.sleepState == 2 }
                return !Hrv.contiguousRuns(tail).contains { $0.count >= 300 }
            }
            // Archive endpoints do not prove usable data throughout a night.
            // An empty/partial detector result is not evidence that a previously
            // complete recorded session vanished after a recipe upgrade.
            let missingReliableReplacement = old.isComplete && !fresh.contains {
                $0.isComplete && max($0.startUnix, old.startUnix) < min($0.endUnix, old.endUnix)
            }
            guard old.isEdited || editedBoundsChanged || unsupportedExtension || missingReliableReplacement
                    || first > old.startUnix || last < old.endUnix - 1 else { continue }
            // Keep intersecting source windows and the latest saved night, not a growing archive.
            guard (source.startUnix <= last && first < sourceEnd)
                    || old == latestPrevious else { continue }
            // A changed edit remains applicable even if its selected window no longer overlaps raw data.
            if editedBoundsChanged, let savedEdit {
                let updated = make(samples: samples, period: source, correctedTimes: savedEdit)
                result.removeAll {
                    max($0.startUnix, source.startUnix) < min($0.endUnix, sourceEnd)
                        || max($0.startUnix, updated.startUnix) < min($0.endUnix, updated.endUnix)
                }
                result.append(updated)
                continue
            }
            let changedEdit = fresh.contains {
                $0.isEdited && ($0.startUnix != old.startUnix || $0.endUnix != old.endUnix)
                    && ($0.sourceStartUnix == old.sourceStartUnix
                        || max($0.startUnix, source.startUnix) < min($0.endUnix, sourceEnd))
            }
            guard !changedEdit else { continue }
            // Preserve the user's bounds, not stale measurements. An edit made
            // before the BLE archive finishes can have incomplete (or older)
            // stages. Once the whole edited window can be staged, refresh those
            // measurements without letting detector drift change the edit.
            var retained = old
            if old.isEdited, first <= old.startUnix, last >= old.endUnix - 1 {
                let times = [old.startUnix, old.endUnix]
                let refreshed = cache?.night(samples: samples, period: source, correctedTimes: times).0
                    ?? make(samples: samples, period: source, correctedTimes: times)
                // A partial replay must never erase a previously measured night.
                if refreshed.isComplete { retained = refreshed }
            }
            result.removeAll {
                max($0.startUnix, old.startUnix) < min($0.endUnix, old.endUnix)
                    || (old.isEdited && max($0.startUnix, source.startUnix) < min($0.endUnix, sourceEnd))
            }
            result.append(retained)
        }
        return result.sorted { $0.endUnix < $1.endUnix }
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
        let movingEpochs = movingSeconds.keys.filter { (movingSeconds[$0] ?? 0) >= 15 }.sorted()
        var bouts = 0
        var previous: Int?
        for epoch in movingEpochs {
            if let prev = previous {
                if epoch - prev > 4 { bouts += 1 }
            } else {
                bouts += 1
            }
            previous = epoch
        }
        return SleepSession(
            version: algorithmVersion, sourceStartUnix: period.startUnix,
            startUnix: start, endUnix: end,
            staging: SleepStager.stage(samples: night, period: window),
            heartRate: hr, movementBouts: bouts, isEdited: times != nil,
            sourceEndUnix: period.endUnix + 1,
            bandSleepConfirmed: Hrv.contiguousRuns(night.filter {
                $0.wearing && (35...220).contains($0.heartRate) && $0.sleepState == 2
            }).contains { $0.count >= 300 }, timezoneIdentifier: TimeZone.current.identifier
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
    /// Corrupt or legacy override keys must never overflow Int distance arithmetic.
    static func sourceDistance(_ source: Int, _ start: Int) -> Int? {
        let (distance, overflow) = source.subtractingReportingOverflow(start)
        guard !overflow, distance != Int.min else { return nil }
        let magnitude = abs(distance)
        return magnitude <= 6 * 3600 ? magnitude : nil
    }
    /// Saving a recovered edit replaces its aliases instead of creating another night.
    static func saving(
        _ times: [Int], for period: SleepPeriod, overrides: [String: [Int]]
    ) -> [String: [Int]] {
        guard let times = validated(times) else { return overrides }
        let reference = self.times(for: period, overrides: overrides)
            ?? [period.startUnix, period.endUnix + 1]
        var result = overrides
        for (key, value) in overrides {
            guard let source = Int(key), sourceDistance(source, period.startUnix) != nil,
                  let existing = validated(value) else { continue }
            let overlap = min(reference[1], existing[1]) - max(reference[0], existing[0])
            if source == period.startUnix
                || (overlap > 0 && overlap * 2 >= min(reference[1] - reference[0], existing[1] - existing[0])) {
                result.removeValue(forKey: key)
            }
        }
        result[String(period.startUnix)] = times
        return result
    }

    static func times(for period: SleepPeriod, overrides: [String: [Int]]) -> [Int]? {
        if let exact = validated(overrides[String(period.startUnix)]) { return exact }
        let candidates = overrides.compactMap { key, value -> (Int, [Int])? in
            guard let source = Int(key), let distance = sourceDistance(source, period.startUnix),
                  let times = validated(value) else { return nil }
            let overlap = min(period.endUnix + 1, times[1]) - max(period.startUnix, times[0])
            let shorter = min(period.durationS, times[1] - times[0])
            guard overlap > 0, overlap * 2 >= shorter else { return nil }
            return (distance, times)
        }
        // Dictionary iteration order is undefined. Equal-distance aliases must
        // resolve identically across app launches and archive refreshes.
        return candidates.sorted {
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            if $0.1[0] != $1.1[0] { return $0.1[0] < $1.1[0] }
            return $0.1[1] < $1.1[1]
        }.first?.1
    }
}
