import Foundation

/// Official source values are chart overlays, never replacement band records.
/// Stage totals stay totals: the CSV does not establish epoch-level staging.
struct WhoopImportedDay {
    let dateKey: String
    var recovery: Double?
    var strain: Double?
    var sleepHours: Double?
    var performance: Double?
    var hrvMS: Double?
    var restingHR: Double?
    var respiratoryRate: Double?
    var energyKcal: Double?
    var sleepNeedHours: Double?
    var deepMinutes: Double?
    var remMinutes: Double?
    var efficiency: Double?
    var consistency: Double?
    var onsetUnix: Int?
    var wakeUnix: Int?
    var onsetClockMinutes: Double?
    var timeInBedMinutes: Double?

    func fillingDisplayGaps(in local: DayMetrics?) -> DayMetrics {
        guard let local else { return displayDay }
        let protectedSleep = local.sleepStartUnix != nil
        return DayMetrics(dateKey: local.dateKey, state: local.state,
            restingHR: local.restingHR ?? restingHR, lnRMSSD: local.lnRMSSD ?? hrvMS.map(log),
            hrvWindowSeconds: local.hrvWindowSeconds,
            sleepHours: protectedSleep ? local.sleepHours : sleepHours ?? local.sleepHours,
            sleepStartUnix: local.sleepStartUnix, sleepEndUnix: local.sleepEndUnix,
            strain: local.strain ?? strain, steps: local.steps,
            sleepDurationReliable: protectedSleep ? local.sleepDurationReliable : (sleepHours != nil ? true : local.sleepDurationReliable),
            respiratoryRate: local.respiratoryRate ?? respiratoryRate,
            sleepPerformancePct: protectedSleep ? local.sleepPerformancePct : local.sleepPerformancePct ?? performance,
            zoneSeconds: local.zoneSeconds, awakeLnRMSSD: local.awakeLnRMSSD, awakeRestingHR: local.awakeRestingHR,
            restingHRWindowSeconds: local.restingHRWindowSeconds, respiratoryWindows: local.respiratoryWindows,
            skinTemperatureC: local.skinTemperatureC, skinTemperatureSeconds: local.skinTemperatureSeconds,
            skinTemperatureSource: local.skinTemperatureSource, oxygenCandidatePct: local.oxygenCandidatePct,
            zoneCoverageStartUnix: local.zoneCoverageStartUnix, zoneCoverageEndUnix: local.zoneCoverageEndUnix)
    }

    var displayDay: DayMetrics {
        DayMetrics(dateKey: dateKey, state: "whoop-imported", restingHR: restingHR,
            lnRMSSD: hrvMS.map(log), hrvWindowSeconds: 0, sleepHours: sleepHours ?? 0,
            sleepStartUnix: onsetUnix, sleepEndUnix: wakeUnix.map { $0 - 1 }, strain: strain,
            steps: nil, sleepDurationReliable: sleepHours == nil ? false : true,
            respiratoryRate: respiratoryRate, sleepPerformancePct: performance)
    }
}

enum WhoopImportedHistory {
    static func normalized(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
    static func make(_ sources: [String: [WhoopCSVImport.SupplementalRecord]]) -> [String: WhoopImportedDay] {
        var result: [String: WhoopImportedDay] = [:]
        let dates = WhoopSourceDates(sources: sources)
        for category in ["physiological_cycles", "sleeps"] {
            for record in sources[category] ?? [] {
                let fields = Dictionary(record.fields.map { (normalized($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
                func text(_ name: String) -> String? {
                    fields[normalized(name)].flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                }
                if category == "sleeps", let nap = text("Nap"), ["true", "yes", "1"].contains(nap.lowercased()) { continue }
                guard let key = dates.dateKey(for: record) else { continue }
                var day = result[key] ?? WhoopImportedDay(dateKey: key)
                func number(_ name: String, _ range: ClosedRange<Double>) -> Double? {
                    guard let raw = text(name), let value = Double(raw), value.isFinite, range.contains(value) else { return nil }
                    return value
                }
                day.recovery = number("Recovery score %", 0...100) ?? day.recovery
                day.strain = number("Day Strain", 0...21) ?? day.strain
                day.hrvMS = number("Heart rate variability (ms)", 0.001...1000) ?? day.hrvMS
                day.restingHR = number("Resting heart rate (bpm)", 25...230) ?? day.restingHR
                day.energyKcal = number("Energy burned (cal)", 0...100_000) ?? day.energyKcal
                day.sleepHours = number("Asleep duration (min)", 0...1440).map { $0 / 60 } ?? day.sleepHours
                day.performance = number("Sleep performance %", 0...100) ?? day.performance
                day.respiratoryRate = number("Respiratory rate (rpm)", 1...100) ?? day.respiratoryRate
                day.sleepNeedHours = number("Sleep need (min)", 0...1440).map { $0 / 60 } ?? day.sleepNeedHours
                day.deepMinutes = number("Deep (SWS) duration (min)", 0...1440) ?? day.deepMinutes
                day.remMinutes = number("REM duration (min)", 0...1440) ?? day.remMinutes
                day.efficiency = number("Sleep efficiency %", 0...100) ?? day.efficiency
                day.consistency = number("Sleep consistency %", 0...100) ?? day.consistency
                day.timeInBedMinutes = number("In bed duration (min)", 0...1440) ?? day.timeInBedMinutes
                day.onsetUnix = timestamp(text("Sleep onset"), timezone: text("Cycle timezone")) ?? day.onsetUnix
                day.wakeUnix = timestamp(text("Wake onset"), timezone: text("Cycle timezone")) ?? day.wakeUnix
                if let onset = text("Sleep onset"), onset.count >= 16 {
                    let clock = String(onset.dropFirst(11).prefix(5)).split(separator: ":").compactMap { Double($0) }
                    if clock.count == 2 { day.onsetClockMinutes = clock[0] * 60 + clock[1] }
                }
                result[key] = day
            }
        }
        return result
    }
    static func dateKey(_ value: String?) -> String? {
        guard let value, value.count >= 10 else { return nil }
        let key = String(value.prefix(10))
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian); format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "yyyy-MM-dd"; format.isLenient = false
        return format.date(from: key) == nil ? nil : key
    }
    static func timestamp(_ value: String?, timezone: String?) -> Int? {
        guard let value else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return Int(date.timeIntervalSince1970) }
        guard let timezone else { return nil }
        let offset = timezone.replacingOccurrences(of: "UTC", with: "").replacingOccurrences(of: ":", with: "")
        let seconds: Int
        if offset.isEmpty || offset == "Z" { seconds = 0 }
        else {
            guard offset.count == 5, let hours = Int(offset.dropFirst().prefix(2)),
                  let minutes = Int(offset.suffix(2)), hours <= 14, minutes < 60,
                  offset.first == "+" || offset.first == "-" else { return nil }
            seconds = (offset.first == "-" ? -1 : 1) * (hours * 3600 + minutes * 60)
        }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: seconds)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"; formatter.isLenient = false
        return formatter.date(from: value).map { Int($0.timeIntervalSince1970) }
    }
}
