import Foundation

enum DetailMetric: String, CaseIterable, Identifiable {
    case strain, recovery, hrv, rhr, respiration, sleepPerformance
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
                     sleepNeedHours: Double, calendar: Calendar = .current) -> [MetricDay] {
        let byKey = Dictionary(days.map { ($0.dateKey, $0) }, uniquingKeysWith: { _, last in last })
        let end = calendar.startOfDay(for: ending)
        guard count > 0 else { return [] }
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - count + 1, to: end) else { return nil }
            let key = JournalStore.dayKey(for: date, calendar: calendar)
            let day = byKey[key]
            let prior = byKey.values.filter { $0.dateKey < key }.sorted { $0.dateKey < $1.dateKey }
            let baseline = DailyAnalysis.baseline(from: Array(prior.suffix(30)))
            let recovery = Recovery.score(lnRMSSD: day?.lnRMSSD, rhr: day?.restingHR,
                sleepHours: day?.reliableSleepHours, sleepNeedHours: sleepNeedHours, baseline: baseline).score
            let sessions = live.filter { $0.dateKey == key }
            var zones: [Double]?
            if let raw = day?.zoneSeconds, raw.count == 5, raw.allSatisfy({ $0 >= 0 }) {
                zones = raw.map(Double.init)
            } else {
                let valid = sessions.filter { $0.zoneSeconds.count == 5 && $0.zoneSeconds.allSatisfy { $0 >= 0 } }
                if !valid.isEmpty {
                    zones = (0..<5).map { index in valid.reduce(0.0) { $0 + Double($1.zoneSeconds[index]) } }
                }
            }
            let logs = manual.filter { $0.dateKey == key }
            let strengthLogs = logs.filter { $0.kind.usesSets }
            let hasDay = day != nil || !sessions.isEmpty || !logs.isEmpty
            let strength: Double? = hasDay && strengthLogs.allSatisfy({ $0.minutes > 0 })
                ? strengthLogs.reduce(0.0) { $0 + Double($1.minutes) } : nil
            return MetricDay(date: date, key: key, recorded: day, recovery: recovery,
                             zones: zones, calories: caloriesByDay[key], strength: strength)
        }
    }

    static func comparison(_ metric: DetailMetric, before key: String, in points: [MetricDay]) -> Double? {
        let values = points.filter { $0.key < key }.suffix(30).compactMap { $0.value(metric) }
        return values.isEmpty ? nil : Stats.mean(values)
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
            let record = DayMetrics(dateKey: key, state: "sleep", restingHR: 63 + wave * 5,
                lnRMSSD: log(46 + wave * 12), hrvWindowSeconds: 600, sleepHours: 7.2 + wave * 0.3,
                sleepStartUnix: nil, sleepEndUnix: nil, strain: 5.5 + wave * 1.5,
                steps: 6500 + Int(wave * 3000), sleepDurationReliable: true,
                respiratoryRate: 18.2 + wave * 0.4, sleepPerformancePct: 76 + wave * 10)
            if offset % 7 == 4 {
                return MetricDay(date: date, key: key, recorded: nil, recovery: nil, zones: nil, calories: nil, strength: nil)
            }
            let zones: [Double] = offset % 3 == 0 ? [0, 0, 0, 0, 0] : [900, 300, 120, 60, 0]
            return MetricDay(date: date, key: key, recorded: record, recovery: 50 + wave * 35,
                             zones: zones, calories: 350 + wave * 150, strength: offset % 4 == 0 ? 40 : 0)
        }
    }
}
