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

/// Detailed HRV calculation diagnostic summary for provenance auditing.
struct HrvDetailedDiagnostics: Codable, Equatable {
    let rawRRCount: Int
    let acceptedNNCount: Int
    let rejectedBeatsByReason: [String: Int]
    let coveragePercentage: Double
    let timestampGaps: Int
    let selectedCalculationWindow: String
    let finalRMSSD: Double?
    let finalLnRMSSD: Double?
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

/// One bedtime-to-waketime span, used by the consistency rule.
struct NightSpan: Codable, Equatable {
    let startUnix: Int
    let endUnix: Int
}

/// A four-class estimate. Never a PSG reading and never presented as one.
enum SleepStage: String, Codable, CaseIterable, Identifiable {
    case wake, light, deep, rem

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wake: return "Awake"
        case .light: return "Light"
        case .deep: return "Deep"
        case .rem: return "REM"
        }
    }

    var icon: String {
        switch self {
        case .wake: return "sun.max.fill"
        case .light: return "moon.stars.fill"
        case .deep: return "moon.fill"
        case .rem: return "brain.head.profile"
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
    var totalMinutes: Double { asleepMinutes + wakeMinutes }

    func minutes(for stage: SleepStage) -> Double {
        switch stage {
        case .wake: return wakeMinutes
        case .light: return lightMinutes
        case .deep: return deepMinutes
        case .rem: return remMinutes
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
    /// Present only when each scored awake window has complete RR timestamp coverage.
    /// Older cached splits have no verified duration coverage.
    var durationCoverageSeconds: Int? = nil

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
    var sleepNeedBreakdown: SleepNeedBreakdown? = nil
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
    var maxHR: Int? = nil
    var strain: Double? = nil

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

/// Canonical WHOOP Recovery tiers identified from binary type descriptor `0x10a0f2874`
/// and presentation boundaries `-[WHPTheme recoveryColorForRecoveryScore:]` at `0x100041d3c`.
public enum RecoveryLevel: Int, Codable {
    case highRecovery   = 0  // Green (raw score > 66.0, displaying >= 67%)
    case mediumRecovery = 1  // Yellow (33.0 < score <= 66.0, displaying 34% - 66%)
    case lowRecovery    = 2  // Red (raw score <= 33.0, displaying <= 33%)
    case calibrating    = 3  // Insufficient baseline (< 7 days)
    case deadEnd        = 4  // Missing / invalid data
}

struct RecoveryResult: Codable, Equatable {
    let score: Double?
    let reason: String?
    let hrvComponent: Double?
    let rhrComponent: Double?
    let sleepComponent: Double?

    var level: RecoveryLevel {
        guard let score else {
            if let reason, reason.lowercased().contains("baseline") {
                return .calibrating
            }
            return .deadEnd
        }
        if score > 66.0 { return .highRecovery }
        if score > 33.0 { return .mediumRecovery }
        return .lowRecovery
    }

    var band: String {
        switch level {
        case .highRecovery: return "green"
        case .mediumRecovery: return "yellow"
        case .lowRecovery: return "red"
        case .calibrating, .deadEnd: return "unavailable"
        }
    }
}

struct StressResult: Codable, Equatable {
    let index: Double?
    let reason: String?
    let diagnostics: StressDiagnostics?

    var band: String {
        guard let index else { return "unavailable" }
        if index < Recovery.stressElevatedSD { return "low" }
        if index < Recovery.stressHighSD { return "elevated" }
        return "high"
    }
}

/// Canonical WHOOP VO2 Max source enumeration from binary strings (`0x109748af0`–`0x109748b50`).
public enum VO2MaxSource: String, Codable, CaseIterable {
    case internalEstimate = "INTERNAL_ESTIMATE"
    case manualLabTest    = "MANUAL_LAB_TEST"
    case manualWearable   = "MANUAL_WEARABLE"
    case manualOther      = "MANUAL_OTHER"

    public var title: String {
        switch self {
        case .internalEstimate: return "Internal Estimate"
        case .manualLabTest:    return "Lab Test"
        case .manualWearable:   return "Wearable"
        case .manualOther:      return "Manual Entry"
        }
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
    /// nil means a legacy quiet-fraction total, not verified by this version.
    var sleepDurationReliable: Bool? = nil
    /// Optional on legacy days; sourced from the canonical night's samples/report.
    var respiratoryRate: Double? = nil
    var sleepPerformancePct: Double? = nil
    /// Recorded awake HR seconds in Karvonen zones 1…5; nil means unavailable.
    var zoneSeconds: [Int]? = nil
    var awakeLnRMSSD: Double? = nil
    var awakeRestingHR: Double? = nil
    var restingHRWindowSeconds: Int? = nil
    var respiratoryWindows: Int? = nil
    var skinTemperatureC: Double? = nil
    var skinTemperatureSeconds: Int? = nil
    var skinTemperatureSource: String? = nil
    var oxygenCandidatePct: Double? = nil
    var zoneCoverageStartUnix: Int? = nil
    var zoneCoverageEndUnix: Int? = nil

    var id: String { dateKey }

    var reliableSleepHours: Double? {
        guard sleepDurationReliable == true, sleepHours.isFinite, sleepHours >= 0 else { return nil }
        return sleepHours
    }

    var night: NightSpan? {
        guard let start = sleepStartUnix, let end = sleepEndUnix else { return nil }
        return NightSpan(startUnix: start, endUnix: end + 1)
    }
}
