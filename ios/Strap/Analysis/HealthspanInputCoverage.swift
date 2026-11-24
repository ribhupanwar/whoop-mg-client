import Foundation

/// Nine WHOOP-published Healthspan contributors, represented without inventing
/// WHOOP's unpublished server-side age coefficients.
/// Values must be computed from real captured history before being supplied.
enum HealthspanContributor: String, CaseIterable {
    case sleepDuration
    case sleepConsistency
    case steps
    case heartRateZones1To3
    case heartRateZones4To5
    case strengthActivity
    case vo2Max
    case restingHeartRate
    case leanBodyMass
}

/// A value with its actual observed coverage, so missing data is not treated
/// as zero exercise, zero steps, or an adverse physiological measurement.
struct HealthspanObservation: Equatable {
    let value: Double
    let observedDays: Int
    let firstObserved: Date
    let lastObserved: Date

    var isValid: Bool {
        value.isFinite && observedDays > 0 && firstObserved <= lastObserved
    }
}

struct HealthspanInputCoverage {
    let observations: [HealthspanContributor: HealthspanObservation]
    let asOf: Date

    /// WHOOP's public methodology describes approximately six months of
    /// history for Age and a recent 30-day pace comparison.
    /// This is a coverage audit, NOT a reproduction of WHOOP Age.
    func missing(_ metric: HealthspanContributor, minimumDays: Int,
                 windowDays: Int, calendar: Calendar = .current) -> Bool {
        guard minimumDays > 0, windowDays >= minimumDays,
              let observation = observations[metric], observation.isValid,
              let start = calendar.date(byAdding: .day, value: -(windowDays - 1),
                                        to: calendar.startOfDay(for: asOf)) else { return true }
        // The observation may span longer than the requested window. Rejecting
        // every firstObserved < start incorrectly discards long-running history.
        // Without per-day dates, subtract the maximum number of days that
        // could have been observed before the window. This is a conservative
        // lower bound, never an invented count of in-window observations.
        guard observation.lastObserved >= start,
              observation.lastObserved <= asOf,
              observation.firstObserved <= asOf else { return true }
        let firstDay = calendar.startOfDay(for: observation.firstObserved)
        let outsideDays = max(0, calendar.dateComponents([.day], from: firstDay, to: start).day ?? 0)
        let guaranteedInWindow = max(0, observation.observedDays - outsideDays)
        return guaranteedInWindow < minimumDays
    }

    var availableContributors: Set<HealthspanContributor> {
        Set(observations.compactMap { metric, observation in
            observation.isValid ? metric : nil
        })
    }

    var missingContributors: Set<HealthspanContributor> {
        Set(HealthspanContributor.allCases).subtracting(availableContributors)
    }
}
