import Foundation

/// Independent fitness-age comparison, NOT WHOOP Healthspan / WHOOP Age and
/// not a clinical or biological-age measurement.
///
/// The age/RHR/activity coefficients are from the published Nes et al. 2011
/// HUNT non-exercise fitness model, described in NOOP's public FITNESS_AGE.md.
/// This implementation was written for Strap; no NOOP/Aura code is copied.
/// The PA index is an APPROXIMATION derived from captured workouts, not the
/// validated HUNT questionnaire. Display only with sufficient measured data.
struct FitnessAgeSnapshot: Equatable {
    let years: Double
    let chronologicalYears: Int
    let restingHeartRate: Double
    let physicalActivityIndex: Double
    let restingNights: Int
    let capturedDays: Int
    let exerciseDays: Int
    let confidenceNote: String
}

enum FitnessAgeModel {
    static let minRestingNights = 4
    static let minCapturedDays = 4

    /// Comparison reference, not a population-level clinical standard.
    static let referenceRHR = 65.0
    static let referencePA = 5.0

    static func calculate(age: Int, sex: Sex, restingHR: Double,
                          activityIndex: Double) -> Double? {
        guard (20...80).contains(age), restingHR.isFinite,
              (35...110).contains(restingHR), activityIndex.isFinite,
              (0...15).contains(activityIndex) else { return nil }
        let ageCoeff: Double
        let rhrCoeff: Double
        let activityCoeff: Double
        switch sex {
        case .male:
            ageCoeff = 0.296
            rhrCoeff = 0.155
            activityCoeff = 0.226
        case .female:
            ageCoeff = 0.247
            rhrCoeff = 0.114
            activityCoeff = 0.198
        case .unspecified:
            return nil
        }
        let estimate = Double(age)
            + (rhrCoeff * (restingHR - referenceRHR)
               - activityCoeff * (activityIndex - referencePA)) / ageCoeff
        return max(20, min(80, estimate))
    }

    /// HUNT-like frequency × intensity × duration buckets derived from
    /// observed sessions. NOT the original HUNT questionnaire.
    static func activityIndex(activeDays: Int, averageMinutes: Double,
                              highIntensityFraction: Double) -> Double? {
        guard (0...7).contains(activeDays), averageMinutes.isFinite,
              averageMinutes >= 0, highIntensityFraction.isFinite,
              (0...1).contains(highIntensityFraction) else { return nil }
        let frequency: Double
        switch activeDays {
        case 0: frequency = 0
        case 1: frequency = 0.5
        case 2: frequency = 1
        case 3...4: frequency = 2.5
        default: frequency = 5
        }
        let intensity: Double =
            highIntensityFraction < 0.15 ? 1 :
            (highIntensityFraction < 0.5 ? 2 : 3)
        let duration: Double =
            averageMinutes < 15 ? 0.10 :
            (averageMinutes < 30 ? 0.38 :
             (averageMinutes < 60 ? 0.75 : 1))
        return frequency * intensity * duration
    }

    /// Require a populated 7-day window rather than confusing a failed band
    /// sync with a sedentary week. Only measured RHR is accepted; overrides
    /// and design-preview samples never feed this calculation.
    static func snapshot(
        age: Int,
        sex: Sex,
        ageConfirmed: Bool,
        days: [DayMetrics],
        detected: [ActivitySession],
        live: [LiveActivityRecord],
        asOf: Date = Date()
    ) -> FitnessAgeSnapshot? {
        guard ageConfirmed, sex != .unspecified else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: asOf)
        guard let firstDay = calendar.date(byAdding: .day, value: -6, to: today) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let startKey = formatter.string(from: firstDay)
        let endKey = formatter.string(from: today)
        let captured = days.filter { $0.dateKey >= startKey && $0.dateKey <= endKey }
        let resting = captured.compactMap { day -> Double? in
            guard day.state == "sleep", let hr = day.restingHR,
                  hr.isFinite, (35...110).contains(hr) else { return nil }
            return hr
        }
        let capturedSteps = captured.filter { $0.steps != nil }.count
        guard resting.count >= minRestingNights, capturedSteps >= minCapturedDays else {
            return nil
        }
        let medianRHR = Stats.median(resting)
        let predictedMaxHR = 208.0 - 0.7 * Double(age)
        guard predictedMaxHR > medianRHR + 30 else { return nil }
        let cutoff = Int(firstDay.timeIntervalSince1970)
        let end = Int((calendar.date(byAdding: .day, value: 1, to: today)
                       ?? asOf).timeIntervalSince1970)
        var sessions: [(start: Int, minutes: Double, highMinutes: Double)] = []
        let acceptedDetected = detected.filter {
            $0.startUnix >= cutoff && $0.startUnix < end
                && $0.durationS >= 600 && $0.meanHR != nil
        }
        for item in acceptedDetected {
            guard let hr = item.meanHR else { continue }
            let high = (hr - medianRHR) / (predictedMaxHR - medianRHR) >= 0.75
            sessions.append((item.startUnix, item.minutes, high ? item.minutes : 0))
        }
        for item in live {
            guard item.startedUnix >= cutoff, item.startedUnix < end,
                  item.seconds >= 600, let hr = item.meanHR else { continue }
            // Live recording and stored-band detection can describe the same
            // workout. Never count both in the weekly activity index.
            let duplicated = acceptedDetected.contains { detected in
                let overlap = min(detected.endUnix, item.endedUnix)
                    - max(detected.startUnix, item.startedUnix)
                return Double(max(0, overlap))
                    >= 0.5 * Double(min(detected.durationS, item.seconds))
            }
            if duplicated { continue }
            let highMinutes: Double
            if item.zoneSeconds.count >= 5 {
                highMinutes = Double(item.zoneSeconds[3] + item.zoneSeconds[4]) / 60.0
            } else {
                highMinutes = (hr - medianRHR) / (predictedMaxHR - medianRHR) >= 0.75
                    ? item.minutes : 0
            }
            sessions.append((item.startedUnix, item.minutes, highMinutes))
        }
        guard !sessions.isEmpty else { return nil }
        let exerciseDays = Set(sessions.map {
            formatter.string(from: Date(timeIntervalSince1970: TimeInterval($0.start)))
        }).count
        let totalMinutes = sessions.reduce(0.0) { $0 + $1.minutes }
        guard totalMinutes > 0 else { return nil }
        let highMinutes = sessions.reduce(0.0) { $0 + $1.highMinutes }
        guard let pa = activityIndex(
            activeDays: exerciseDays,
            averageMinutes: totalMinutes / Double(exerciseDays),
            highIntensityFraction: min(1, highMinutes / totalMinutes)
        ), let years = calculate(age: age, sex: sex,
                                 restingHR: medianRHR, activityIndex: pa) else {
            return nil
        }
        return FitnessAgeSnapshot(
            years: years,
            chronologicalYears: age,
            restingHeartRate: medianRHR,
            physicalActivityIndex: pa,
            restingNights: resting.count,
            capturedDays: capturedSteps,
            exerciseDays: exerciseDays,
            confidenceNote: "Exploratory fitness comparison · ±5 years is a display band, not a validated confidence interval."
        )
    }
}
