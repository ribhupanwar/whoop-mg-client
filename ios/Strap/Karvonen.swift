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
}