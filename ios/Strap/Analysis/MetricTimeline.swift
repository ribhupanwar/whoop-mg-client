import Foundation

enum DetailMetric: String, CaseIterable, Identifiable {
    case strain, recovery, hrv, rhr, respiration, sleepPerformance, vo2
    case zonesLow, zonesHigh, steps, calories, strength
    var id: String { rawValue }
}

struct MetricDay: Identifiable {
    let date: Date
    let key: String
    let recorded: DayMetrics?
    let recovery: Double?
    let zones: [Double]?
    let calories: Double?
    let strength: Double?
    var vo2: Double? = nil
    var id: String { key }

    func value(_ metric: DetailMetric) -> Double? {
        let result: Double?
        switch metric {
        case .strain: result = recorded?.strain
        case .recovery: result = recovery
        case .hrv: result = recorded?.lnRMSSD.map { exp($0) }
        case .rhr: result = recorded?.restingHR
        case .respiration: result = recorded?.respiratoryRate
        case .sleepPerformance: result = recorded?.sleepPerformancePct
        case .steps: result = recorded?.steps.map(Double.init)
        case .calories: result = calories
        case .strength: result = strength
        case .vo2: result = vo2
        case .zonesLow: result = zones.map { $0.prefix(3).reduce(0, +) / 60 }
        case .zonesHigh: result = zones.map { $0.suffix(2).reduce(0, +) / 60 }
        }
        guard let result, result.isFinite, result >= 0 else { return nil }
        if metric == .strain && result > 21 { return nil }
        if (metric == .recovery || metric == .sleepPerformance) && result > 100 { return nil }
        if (metric == .hrv || metric == .rhr || metric == .respiration) && result <= 0 { return nil }
        return result
    }
}

/// Calendar days keep their slots, including DST and absent data. A baseline
/// only sees earlier observations; missing measurements are never zeros.
enum MetricTimeline {
    static func make(days: [DayMetrics], live: [LiveActivityRecord], manual: [ManualActivity],
                     caloriesByDay: [String: Double], ending: Date, count: Int = 37,
                     sleepNeedHours: Double, maxHR: Double? = nil, calendar: Calendar = .current) -> [MetricDay] {
        let byKey = Dictionary(days.map { ($0.dateKey, $0) }, uniquingKeysWith: { _, last in last })
        let ordered = byKey.values.sorted { $0.dateKey < $1.dateKey }
        let liveByDay = Dictionary(grouping: live, by: \.dateKey)
        let manualByDay = Dictionary(grouping: manual, by: \.dateKey)
        var priorEnd = 0
        let end = calendar.startOfDay(for: ending)
        guard count > 0 else { return [] }
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - count + 1, to: end) else { return nil }
            let key = JournalStore.dayKey(for: date, calendar: calendar)
            let day = byKey[key]
            while priorEnd < ordered.count && ordered[priorEnd].dateKey < key { priorEnd += 1 }
            let baseline = DailyAnalysis.baseline(from: Array(ordered[max(0, priorEnd - 30)..<priorEnd]))
            let recovery = Recovery.score(lnRMSSD: day?.lnRMSSD, rhr: day?.restingHR,
                sleepHours: day?.reliableSleepHours, sleepNeedHours: sleepNeedHours, baseline: baseline).score
            let sessions = liveByDay[key] ?? []
            var zones: [Double]?
            if let raw = day?.zoneSeconds, raw.count == 5, raw.allSatisfy({ $0 >= 0 }) {
                zones = raw.map(Double.init)
                if let start = day?.zoneCoverageStartUnix, let end = day?.zoneCoverageEndUnix, start < end {
                    // An afternoon live workout must not disappear behind an
                    // earlier morning sync. Add only provably disjoint sessions;
                    // legacy or partially overlapping coverage stays conservative.
                    let outside = sessions.filter {
                        ($0.endedUnix <= start || $0.startedUnix >= end)
                            && $0.zoneSeconds.count == 5 && $0.zoneSeconds.allSatisfy { $0 >= 0 }
                    }
                    zones = (0..<5).map { index in
                        Double(raw[index]) + outside.reduce(0.0) { $0 + Double($1.zoneSeconds[index]) }
                    }
                }
            } else {
                let valid = sessions.filter { $0.zoneSeconds.count == 5 && $0.zoneSeconds.allSatisfy { $0 >= 0 } }
                if !valid.isEmpty {
                    zones = (0..<5).map { index in valid.reduce(0.0) { $0 + Double($1.zoneSeconds[index]) } }
                }
            }
            let logs = manualByDay[key] ?? []
            let strengthLogs = logs.filter { $0.kind.usesSets }
            let hasDay = day != nil || !sessions.isEmpty || !logs.isEmpty
            let strength: Double? = hasDay && !strengthLogs.isEmpty && strengthLogs.allSatisfy({ $0.minutes > 0 })
                ? strengthLogs.reduce(0.0) { $0 + Double($1.minutes) } : nil
            let vo2: Double? = day?.state == "sleep" ? maxHR.flatMap { maximum in
                day?.restingHR.flatMap { resting in Hrv.vo2Max(maxHR: maximum, restingHR: resting) }
            } : nil
            return MetricDay(date: date, key: key, recorded: day, recovery: recovery,
                             zones: zones, calories: caloriesByDay[key], strength: strength, vo2: vo2)
        }
    }

    static func comparison(_ metric: DetailMetric, before key: String, in points: [MetricDay]) -> Double? {
        let values = points.filter { $0.key < key }.sorted { $0.key < $1.key }
            .compactMap { $0.value(metric) }.suffix(30)
        return values.isEmpty ? nil : Stats.mean(Array(values))
    }

    /// Average weekly duration over the requested calendar period. Missing
    /// days contribute nothing and are never extrapolated as if observed.
    static func averageWeeklyDuration(_ readings: [Double], calendarDayCount: Int) -> Double? {
        guard calendarDayCount > 0, !readings.isEmpty else { return nil }
        let weeks = Double(calendarDayCount) / 7
        return readings.reduce(0, +) / weeks
    }

    /// Values surrounded by gaps have no line segment, so the chart must draw
    /// a dot for those observations to keep them visible without bridging gaps.
    static func isolatedLineIndices(_ values: [Double?]) -> [Int] {
        values.indices.filter { index in
            guard values[index] != nil else { return false }
            let beforeIsMissing = index == values.startIndex || values[index - 1] == nil
            let afterIsMissing = index == values.index(before: values.endIndex) || values[index + 1] == nil
            return beforeIsMissing && afterIsMissing
        }
    }
}

extension MetricTimeline {
    /// Explicit design-preview data only; never persisted or used in live mode.
    static func preview(ending: Date, count: Int = 37, calendar: Calendar = .current) -> [MetricDay] {
        let end = calendar.startOfDay(for: ending)
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - count + 1, to: end) else { return nil }
            let key = JournalStore.dayKey(for: date, calendar: calendar)
            let wave = sin(Double(offset) * 1.7)
            let record = DayMetrics(dateKey: key, state: "sleep", restingHR: offset == count - 1 ? 67 : 63 + wave * 5,
                lnRMSSD: log(offset == count - 1 ? 44 : 46 + wave * 12), hrvWindowSeconds: 600, sleepHours: 7.2 + wave * 0.3,
                sleepStartUnix: nil, sleepEndUnix: nil, strain: offset == count - 1 ? 4.7 : 5.5 + wave * 1.5,
                steps: offset == count - 1 ? 3921 : 6500 + Int(wave * 3000), sleepDurationReliable: true,
                respiratoryRate: offset == count - 1 ? 18.0 : 18.2 + wave * 0.4,
                sleepPerformancePct: offset == count - 1 ? 78 : 76 + wave * 10)
            if offset % 7 == 4 {
                return MetricDay(date: date, key: key, recorded: nil, recovery: nil, zones: nil, calories: nil, strength: nil)
            }
            let zones: [Double] = offset % 3 == 0 ? [0, 0, 0, 0, 0] : [900, 300, 120, 60, 0]
            return MetricDay(date: date, key: key, recorded: record, recovery: offset == count - 1 ? 53 : 50 + wave * 35,
                             zones: zones, calories: 350 + wave * 150, strength: offset % 4 == 0 ? 40 : 0, vo2: 48 + wave * 3)
        }
    }
}

struct MetricDurationBucket: Identifiable {
    let start: Date
    let end: Date
    let minutes: Double?
    let zoneSeconds: [Double]?
    let recordedDays: Int
    var id: Date { start }
}

extension MetricTimeline {
    /// Calendar-aligned chunks ending on the selected day. Missing buckets
    /// remain nil; observed zero-duration days retain an explicit zero.
    static func durationBuckets(_ points: [MetricDay], metric: DetailMetric,
                                daysPerBucket: Int = 7) -> [MetricDurationBucket] {
        guard daysPerBucket > 0, metric.isDurationMetric else { return [] }
        let sorted = points.sorted { $0.date < $1.date }
        var end = sorted.count
        var buckets: [MetricDurationBucket] = []
        while end > 0 {
            let start = max(0, end - daysPerBucket)
            let days = Array(sorted[start..<end])
            let readings = days.compactMap { $0.value(metric) }
            let zones = days.compactMap(\.zones).filter { $0.count == 5 }
            let sums: [Double]? = zones.isEmpty ? nil : (0..<5).map { zone in
                zones.reduce(0) { $0 + $1[zone] }
            }
            buckets.append(MetricDurationBucket(start: days[0].date, end: days[days.count - 1].date,
                minutes: readings.isEmpty ? nil : readings.reduce(0, +),
                zoneSeconds: sums, recordedDays: readings.count))
            end = start
        }
        return buckets.reversed()
    }
}

private extension DetailMetric {
    var isDurationMetric: Bool { self == .zonesLow || self == .zonesHigh || self == .strength }
}
