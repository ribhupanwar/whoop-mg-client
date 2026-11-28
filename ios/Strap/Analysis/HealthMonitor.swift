import Foundation

enum HealthVital: String, CaseIterable { case respiration, oxygen, rhr, hrv, temperature }

struct HealthReading {
    enum Status: Equatable { case unavailable, calibrating, candidate, withinRange, outsideRange }
    let vital: HealthVital
    let value: Double?
    let status: Status
    let baselineDays: Int
    let reference: ClosedRange<Double>?
    var nightlyTemperatureCandidate: Double? = nil
    // Research-only candidate; deliberately excluded from measured vital counts.
    var nightlyOxygenCandidate: Double? = nil
    var verifiedWithinRange: Bool { status == .withinRange }
    var statusText: String {
        switch status {
        case .unavailable: return "UNAVAILABLE"
        case .calibrating: return "BUILDING BASELINE"
        case .candidate: return "UNVALIDATED CANDIDATE"
        case .withinRange: return "WITHIN PERSONAL RANGE"
        case .outsideRange: return "OUTSIDE PERSONAL RANGE"
        }
    }
    // Presentation only: a directional departure from a personal range
    // is not necessarily an adverse finding. Keep the underlying status
    // and within-range counts unchanged.
    var isFavourableDirection: Bool {
        guard status == .outsideRange, let value, let reference else { return false }
        return (vital == .rhr && value < reference.lowerBound)
            || (vital == .hrv && value > reference.upperBound)
    }
    // Green describes the direction relative to history, never clinical
    // normality. Very low resting HR keeps a caution indicator.
    var monitorShowsPositiveDirection: Bool {
        isFavourableDirection && (vital != .rhr || (value ?? 0) >= 50)
    }
    private var monitorNumberFormat: String {
        let base = vital == .respiration || vital == .temperature ? 1 : 0
        guard let value, let reference else { return "%." + String(base) + "f" }
        for digits in base...4 {
            let format = "%." + String(digits) + "f"
            let low = String(format: format, reference.lowerBound)
            let high = String(format: format, reference.upperBound)
            let shown = String(format: format, value)
            if reference.lowerBound != reference.upperBound && low == high { continue }
            if value < reference.lowerBound && shown == low { continue }
            if value > reference.upperBound && shown == high { continue }
            return format
        }
        return "%.4f"
    }
    var monitorValueText: String? {
        value.map { String(format: monitorNumberFormat, $0) }
    }
    var monitorStatusText: String {
        if status == .candidate { return "Unverified estimate" }
        guard let value, let reference else { return statusText }
        let format = monitorNumberFormat
        let low = String(format: format, reference.lowerBound)
        let high = String(format: format, reference.upperBound)
        let shown = String(format: format, value)
        if (value < reference.lowerBound && shown == low) || (value > reference.upperBound && shown == high) || (reference.lowerBound != reference.upperBound && low == high) { return statusText }
        switch status {
        case .withinRange: return "within \(low) – \(high)"
        case .outsideRange:
            if value < reference.lowerBound { return "low < \(low)" }
            return vital == .hrv ? "elevated > \(high)" : "high > \(high)"
        default: return statusText
        }
    }
    var monitorShowsWarning: Bool {
        status == .outsideRange && !monitorShowsPositiveDirection
    }
    var referenceText: String {
        if vital == .oxygen { return "Research estimate only — not a validated oxygen reading" }
        guard let reference else { return "Personal baseline: \(baselineDays)/7 prior nights" }
        let format = vital == .temperature ? "%+.1f to %+.1f °C" :
            (vital == .respiration ? "%.1f–%.1f rpm" : (vital == .rhr ? "%.0f–%.0f bpm" : "%.0f–%.0f ms"))
        return "Personal range: " + String(format: format, reference.lowerBound, reference.upperBound)
    }
}

struct HealthMonitorSnapshot {
    let readings: [HealthReading]
    subscript(_ vital: HealthVital) -> HealthReading { readings.first { $0.vital == vital }! }
    var withinCount: Int { readings.filter(\.verifiedWithinRange).count }
    var availableCount: Int { readings.filter { $0.value != nil }.count }
}

/// Empirical personal ranges from distinct, earlier, qualifying sleep nights.
/// Data availability, clinical validation and an in-range result are distinct.
enum HealthMonitor {
    static func make(days: [DayMetrics], session: SleepSession?,
                     calendar: Calendar = .current) -> HealthMonitorSnapshot {
        let key = session.map { JournalStore.dayKey(for: Date(timeIntervalSince1970: Double($0.endUnix - 1)), calendar: calendar) }
        let current = days.first {
            $0.dateKey == key && $0.state == "sleep" && $0.sleepStartUnix == session?.startUnix
                && $0.sleepEndUnix == session.map { $0.endUnix - 1 }
        }
        let prior = days.filter { $0.state == "sleep" && $0.dateKey < (key ?? "") }
        let readings = HealthVital.allCases.map { vital -> HealthReading in
            let value = current.flatMap { measurement($0, vital: vital) }
            let qualified = prior.filter { measurement($0, vital: vital) != nil }
            let distinct = Dictionary(qualified.map { ($0.dateKey, $0) }, uniquingKeysWith: { earlier, later in
                // A duplicate saved night must not depend on enumeration order.
                // Prefer the latest completed interval, then its earliest start.
                let earlierEnd = earlier.sleepEndUnix ?? Int.min
                let laterEnd = later.sleepEndUnix ?? Int.min
                if earlierEnd != laterEnd {
                    return earlierEnd > laterEnd ? earlier : later
                }
                return (earlier.sleepStartUnix ?? Int.max) <= (later.sleepStartUnix ?? Int.max) ? earlier : later
            })
            let values = distinct.values.sorted { $0.dateKey < $1.dateKey }.suffix(30)
                .compactMap { measurement($0, vital: vital) }
            let enough = values.count >= 7
            let center = enough ? Stats.mean(values) : nil
            var range: ClosedRange<Double>?
            if enough, let low = values.min(), let high = values.max() { range = low...high }
            if vital == .oxygen {
                // Expose only the saved same-night candidate, separately from
                // the unavailable measured value. Never classify its range.
                return HealthReading(vital: vital, value: nil, status: value == nil ? .unavailable : .candidate,
                                     baselineDays: values.count, reference: nil, nightlyOxygenCandidate: value)
            }
            if vital == .temperature {
                let delta = value.flatMap { reading in center.map { reading - $0 } }
                let deviationRange = range.flatMap { raw in center.map { (raw.lowerBound - $0)...(raw.upperBound - $0) } }
                return HealthReading(vital: vital, value: delta,
                    status: value == nil ? .unavailable : (enough ? .candidate : .calibrating),
                    baselineDays: values.count, reference: deviationRange, nightlyTemperatureCandidate: value)
            }
            let status: HealthReading.Status
            if let value { status = range.map { $0.contains(value) ? .withinRange : .outsideRange } ?? .calibrating }
            else { status = .unavailable }
            return HealthReading(vital: vital, value: value, status: status, baselineDays: values.count, reference: range)
        }
        return HealthMonitorSnapshot(readings: readings)
    }

    private static func measurement(_ day: DayMetrics, vital: HealthVital) -> Double? {
        let value: Double?
        switch vital {
        case .rhr:
            guard (day.restingHRWindowSeconds ?? day.hrvWindowSeconds) >= 300 else { return nil }
            value = day.restingHR
        case .hrv:
            guard day.hrvWindowSeconds >= 300 else { return nil }
            value = day.lnRMSSD.map { exp($0) }
        case .respiration:
            guard (day.respiratoryWindows ?? 0) > 0 else { return nil }
            value = day.respiratoryRate
        case .temperature:
            guard day.sleepDurationReliable == true, (day.skinTemperatureSeconds ?? 0) >= 300,
                  day.skinTemperatureSource == NightTemperature.source else { return nil }
            value = day.skinTemperatureC
        case .oxygen: value = day.oxygenCandidatePct
        }
        guard let value, value.isFinite, value > 0 else { return nil }
        switch vital {
        case .rhr: return (35...220).contains(value) ? value : nil
        case .respiration: return (8...25).contains(value) ? value : nil
        case .temperature: return (20...43).contains(value) ? value : nil
        case .oxygen: return (70...100).contains(value) ? value : nil
        case .hrv: return value
        }
    }
}
