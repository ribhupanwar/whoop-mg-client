import Foundation

// MARK: - Statistics

/// The few summary statistics the estimators below share. Python's statistics
/// module is the reference: the median averages the two middle values and the
/// standard deviation is the sample (n-1) form. Callers guard emptiness, so an
/// empty input yields .nan instead of trapping inside a UI-driven pass.
enum Stats {
    static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .nan }
        return values.reduce(0.0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .nan }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return (sorted[middle - 1] + sorted[middle]) / 2.0
    }

    static func median(_ values: [Int]) -> Double {
        median(values.map(Double.init))
    }

    /// Sample standard deviation (n-1), matching statistics.stdev.
    static func sampleStdev(_ values: [Double]) -> Double? {
        guard values.count >= 2 else { return nil }
        let average = mean(values)
        let squares = values.reduce(0.0) { $0 + ($1 - average) * ($1 - average) }
        return (squares / Double(values.count - 1)).squareRoot()
    }

    static func populationStdev(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .nan }
        let average = mean(values)
        let squares = values.reduce(0.0) { $0 + ($1 - average) * ($1 - average) }
        return (squares / Double(values.count)).squareRoot()
    }

    static func rounded(_ value: Double, _ digits: Int) -> Double {
        let scale = pow(10.0, Double(digits))
        return (value * scale).rounded() / scale
    }
}

// MARK: - HRV

/// Standard HRV numbers from a beat train. All optional: an artefact-only
/// window produces no value rather than a zero.
struct HrvResult: Codable, Equatable {
    let beats: Int
    let nnBeats: Int
    let rmssdMS: Double?
    let sdnnMS: Double?
    let pnn50Pct: Double?
    let lnRMSSD: Double?
    let meanRRMS: Double?

    var rejectedBeats: Int { beats - nnBeats }

    static let empty = HrvResult(
        beats: 0, nnBeats: 0, rmssdMS: nil, sdnnMS: nil,
        pnn50Pct: nil, lnRMSSD: nil, meanRRMS: nil
    )
}

// MARK: - Sleep

/// A detected sleep window from actigraphy + an HR drop. The stages come from
/// a separate estimate over the same window; a period carries no stage itself.
struct SleepPeriod: Codable, Equatable {
    let startUnix: Int
    let endUnix: Int
    let quietFraction: Double
    let meanHR: Double
    /// Movement bursts that ended inside the period. Actigraphy events, not
    /// verified awakenings.
    let wakeEvents: Int

    var durationS: Int { endUnix - startUnix + 1 }
    var hours: Double { Double(durationS) / 3600.0 }
}



/// Stable wake-day key keeps user-edited sleep boundaries attached when detection trims onset.
enum SleepCorrectionStore {
    static func key(for period: SleepPeriod, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let wakeDate = Date(timeIntervalSince1970: TimeInterval(period.endUnix))
        return "wake-day-\(formatter.string(from: wakeDate))"
    }

    static func times(for period: SleepPeriod, overrides: [String: [Int]], timeZone: TimeZone = .current) -> [Int]? {
        overrides[key(for: period, timeZone: timeZone)] ?? overrides[String(period.startUnix)]
    }

    /// Sensor-derived fallback for an edited bed window when stage data is incomplete.
    /// Quiet fraction comes from recorded on-wrist motion; it never treats the full
    /// time-in-bed window as asleep and never fills missing HR or stages.
    static func estimatedAsleepHours(period: SleepPeriod, editedTimes: [Int]?) -> Double {
        let observedEstimate = period.hours * min(1.0, max(0.0, period.quietFraction))
        guard let editedTimes, editedTimes.count == 2, editedTimes[1] > editedTimes[0] else {
            return observedEstimate
        }
        let editedWindowHours = Double(editedTimes[1] - editedTimes[0]) / 3600.0
        return min(observedEstimate, editedWindowHours)
    }
}

/// One bedtime-to-waketime span, used by the consistency rule.
struct NightSpan: Codable, Equatable {
    let startUnix: Int
    let endUnix: Int
}

/// A four-class estimate. Never a PSG reading and never presented as one.
enum SleepStage: String, Codable, CaseIterable, Identifiable {
    case wake, light, deep, rem, unclassified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wake: return "Awake"
        case .light: return "Light"
        case .deep: return "Deep"
        case .rem: return "REM"
        case .unclassified: return "Unclassified"
        }
    }
}

/// A staged span. The end is EXCLUSIVE, unlike SleepPeriod's inclusive end, so
/// consecutive segments tile the window without an off-by-one gap.
struct SleepStageSegment: Codable, Equatable, Identifiable {
    let startUnix: Int
    let endUnix: Int
    let stage: SleepStage

    var id: Int { startUnix }
    var durationS: Int { endUnix - startUnix }
    var minutes: Double { Double(durationS) / 60.0 }
}

/// One window's staged hypnogram plus the per-stage totals the UI shows. A
/// `reason` with empty segments means the data could not support staging —
/// that is a refusal, not an all-light night.
struct SleepStaging: Codable, Equatable {
    let segments: [SleepStageSegment]
    let deepMinutes: Double
    let lightMinutes: Double
    let remMinutes: Double
    let wakeMinutes: Double
    /// Minutes without enough HR, motion or R-R evidence to assign a stage.
    /// Optional so summaries saved by older builds still decode.
    var unclassifiedMinutes: Double? = nil
    /// Unique in-window seconds containing at least one valid HR sample.
    var hrObservedSeconds: Int? = nil
    /// Full analyzed window in seconds; older cached summaries omit this.
    var hrWindowSeconds: Int? = nil
    /// Longest run of seconds without an HR sample inside the analyzed window.
    var longestHRGapSeconds: Int? = nil
    let epochs: Int
    let hrCoverage: Double
    let reason: String?

    static let unavailable = SleepStaging(
        segments: [], deepMinutes: 0, lightMinutes: 0, remMinutes: 0,
        wakeMinutes: 0, epochs: 0, hrCoverage: 0,
        reason: "no sleep window to stage"
    )

    var asleepMinutes: Double { deepMinutes + lightMinutes + remMinutes }
    var restorativeMinutes: Double { deepMinutes + remMinutes }
    var totalMinutes: Double { asleepMinutes + wakeMinutes + (unclassifiedMinutes ?? 0) }

    func minutes(for stage: SleepStage) -> Double {
        switch stage {
        case .wake: return wakeMinutes
        case .light: return lightMinutes
        case .deep: return deepMinutes
        case .rem: return remMinutes
        case .unclassified: return unclassifiedMinutes ?? 0
        }
    }

    var stageable: Bool { reason == nil && !segments.isEmpty }
}

struct StressSplit: Codable, Equatable {
    let highPct: Double?
    let mediumPct: Double?
    let lowPct: Double?
    let windows: Int
    let reason: String?

    static let unavailable = StressSplit(
        highPct: nil, mediumPct: nil, lowPct: nil, windows: 0,
        reason: "no sleep-stress windows scored"
    )
}

/// One scored 5-minute window's stress index, plotted by the through-the-day
/// chart. Local 0-3 estimate, never a proprietary reading.
struct StressPoint: Codable, Equatable {
    let unix: Int
    let index: Double
}

struct SleepAnalysis: Codable, Equatable {
    let hours: Double
    let needHours: Double
    let hoursVsNeededPct: Double
    let efficiencyPct: Double
    let wakeEvents: Int
    let consistencyPct: Double?
    let consistencyNights: Int
    let stress: StressSplit
    let performancePct: Double?
}

// MARK: - Activities

struct ActivitySession: Codable, Equatable, Identifiable {
    let startUnix: Int
    let endUnix: Int
    /// "run", "walk", "workout" or "cardio" — a combined label, never the raw
    /// unverified gait byte alone.
    let kind: String
    let steps: Int
    let meanHR: Double?
    let walkTicks: Int
    let runTicks: Int

    var id: Int { startUnix }
    var durationS: Int { endUnix - startUnix + 1 }
    var minutes: Double { Double(durationS) / 60.0 }
}

// MARK: - Baselines and scores

/// Personal norms from one value per day. Every baseline-relative score needs
/// at least a week of them before it means anything.
struct Baseline: Codable, Equatable {
    let lnRMSSDMean: Double
    let lnRMSSDSD: Double
    let rhrMean: Double
    let rhrSD: Double
    let days: Int

    static func fromDaily(lnRMSSD: [Double], rhr: [Double]) -> Baseline? {
        guard lnRMSSD.count >= 2, rhr.count >= 2,
              let hrvSD = Stats.sampleStdev(lnRMSSD),
              let rhrSD = Stats.sampleStdev(rhr) else { return nil }
        return Baseline(
            lnRMSSDMean: Stats.mean(lnRMSSD),
            lnRMSSDSD: hrvSD,
            rhrMean: Stats.mean(rhr),
            rhrSD: rhrSD,
            days: min(lnRMSSD.count, rhr.count)
        )
    }
}

struct RecoveryResult: Codable, Equatable {
    let score: Double?
    let reason: String?
    let hrvComponent: Double?
    let rhrComponent: Double?
    let sleepComponent: Double?

    var band: String {
        guard let score else { return "unavailable" }
        if score >= 67 { return "green" }
        if score >= 34 { return "yellow" }
        return "red"
    }
}

struct StressResult: Codable, Equatable {
    let index: Double?
    let reason: String?

    var band: String {
        guard let index else { return "unavailable" }
        if index < Recovery.stressElevatedSD { return "low" }
        if index < Recovery.stressHighSD { return "elevated" }
        return "high"
    }
}

// MARK: - Respiration and SpO2

struct RespRate: Codable, Equatable {
    let breathsPerMinute: Double?
    let reason: String?
    let beats: Int
    let windows: Int

    var available: Bool { breathsPerMinute != nil }
}

/// The band's own candidate byte summarised. Never a clinical SpO2.
struct Spo2Summary: Codable, Equatable {
    let pct: Double?
    let readings: Int
    let saturated: Int
    let diagnostic: Int
    let reason: String?

    var available: Bool { pct != nil }
}

// MARK: - Day metrics

/// One local day's resting values, the input to a personal baseline.
struct DayMetrics: Identifiable, Equatable, Codable {
    let dateKey: String
    /// "sleep" when the day carried a detected night, otherwise "awake".
    /// Stress is scored against awake days only, sleep stress against nights.
    let state: String
    let restingHR: Double?
    let lnRMSSD: Double?
    let hrvWindowSeconds: Int
    let sleepHours: Double
    let sleepStartUnix: Int?
    let sleepEndUnix: Int?
    let strain: Double?
    let steps: Int?

    var id: String { dateKey }

    var night: NightSpan? {
        guard let start = sleepStartUnix, let end = sleepEndUnix else { return nil }
        return NightSpan(startUnix: start, endUnix: end)
    }
}
