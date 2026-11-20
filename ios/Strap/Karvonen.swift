import Foundation

/// Karvonen heart-rate-reserve zones. Pure Swift, unit-testable, no UI imports.
/// Zone bpm = RHR + pct × (HRmax − RHR).
struct HRZone: Equatable {
    let index: Int
    let name: String
    let use: String
    let lowerFraction: Double
    let upperFraction: Double
    let lowerBPM: Double
    let upperBPM: Double
}

enum Karvonen {
    static let bounds: [(Double, Double)] = [
        (0.50, 0.60),
        (0.60, 0.70),
        (0.70, 0.80),
        (0.80, 0.90),
        (0.90, 1.00)
    ]

    static let uses = ["Recovery", "Easy aerobic", "Tempo", "Threshold", "VO2 max"]

    /// Zone 0 is below 50% HR reserve. The configured maximum belongs to Z5;
    /// an above-maximum reading is not silently mislabeled as Zone 0.
    static func zoneIndex(heartRate: Double, zones: [HRZone]) -> Int? {
        guard heartRate.isFinite, heartRate > 0, let first = zones.first,
              let last = zones.last, heartRate <= last.upperBPM else { return nil }
        if heartRate < first.lowerBPM { return 0 }
        if heartRate == last.upperBPM { return last.index }
        return zones.first { heartRate >= $0.lowerBPM && heartRate < $0.upperBPM }?.index
    }

    /// Returns nil when the inputs cannot produce meaningful zones.
    static func zones(restingHR: Double, maxHR: Double) -> [HRZone]? {
        guard restingHR.isFinite, maxHR.isFinite, restingHR > 0, maxHR > restingHR else {
            return nil
        }
        let reserve = maxHR - restingHR
        return bounds.enumerated().map { offset, bound in
            HRZone(
                index: offset + 1,
                name: "Z\(offset + 1)",
                use: uses[offset],
                lowerFraction: bound.0,
                upperFraction: bound.1,
                lowerBPM: restingHR + bound.0 * reserve,
                upperBPM: restingHR + bound.1 * reserve
            )
        }
    }

    /// Age-predicted default only — a population guess, never a measurement.
    static func agePredictedMaxHR(age: Int) -> Double {
        208.0 - 0.7 * Double(age)
    }

    /// WHOOP 5.80.2 verified method (0x109a85a8c): getReserveWithHeartRate:restingHeartRate:maximumHeartRate:
    /// Maps instantaneous heart rate to reserve ratio in [0.0, 1.0].
    static func getReserveWithHeartRate(heartRate: Double, restingHeartRate: Double, maximumHeartRate: Double) -> Double? {
        guard heartRate.isFinite, restingHeartRate.isFinite, maximumHeartRate.isFinite,
              restingHeartRate > 0, maximumHeartRate > restingHeartRate else { return nil }
        let reserve = (heartRate - restingHeartRate) / (maximumHeartRate - restingHeartRate)
        return max(0.0, min(1.0, reserve))
    }

    /// WHOOP 5.80.2 verified method (0x109a85158): getHeartRateForReserve:restingHeartRate:maximumHeartRate:
    /// Inverts reserve ratio back to absolute heart rate in BPM.
    static func getHeartRateForReserve(reserve: Double, restingHeartRate: Double, maximumHeartRate: Double) -> Double? {
        guard reserve.isFinite, restingHeartRate.isFinite, maximumHeartRate.isFinite,
              restingHeartRate > 0, maximumHeartRate > restingHeartRate else { return nil }
        return restingHeartRate + reserve * (maximumHeartRate - restingHeartRate)
    }

    /// WHOOP 5.80.2 fallback calibration preventing strain withholding when user profile lacks explicit baselines.
    static func effectiveMaxHR(configuredMaxHR: Double?, age: Int?) -> Double {
        if let configured = configuredMaxHR, configured > 60 {
            return configured
        }
        if let age = age, age > 0 {
            return agePredictedMaxHR(age: age)
        }
        return 190.0
    }

    static func effectiveRestingHR(measuredRestingHR: Double?) -> Double {
        if let measured = measuredRestingHR, measured > 30 {
            return measured
        }
        return 60.0
    }
}
