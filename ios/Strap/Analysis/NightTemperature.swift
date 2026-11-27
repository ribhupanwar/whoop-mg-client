import Foundation

enum NightTemperature {
    static let source = "v18-offset65-candidate"
    struct Measurement { let celsius: Double?; let seconds: Int }

    /// Mutually exclusive first-failure counts, over canonical in-session seconds.
    /// The diagnostic does not relax the measurement quality gates.
    struct Funnel: Codable, Equatable {
        var hasSession = false
        var inputRecords = 0
        var inSessionRecords = 0
        var uniqueSeconds = 0
        var rejectedWearing = 0
        var rejectedHR = 0
        var rejectedMissingMotion = 0
        var rejectedInvalidMotion = 0
        var rejectedActiveMotion = 0
        var rejectedMissingTemperature = 0
        var rejectedInvalidTemperature = 0
        var eligibleSeconds = 0
        var candidateCelsius: Double? = nil
        var minimumEligibleSeconds = 300
    }

    /// A night-bound, motion-verified sensor candidate, not a clinical reading.
    static func measure(_ samples: [V18Sample], session: SleepSession?) -> Measurement {
        let result = funnel(samples, session: session)
        return Measurement(celsius: result.candidateCelsius, seconds: result.eligibleSeconds)
    }

    static func funnel(_ samples: [V18Sample], session: SleepSession?) -> Funnel {
        var result = Funnel()
        result.inputRecords = samples.count
        guard let session else { return result }
        result.hasSession = true
        let inSession = samples.filter {
            session.startUnix <= $0.unix && $0.unix < session.endUnix
        }
        result.inSessionRecords = inSession.count
        let unique = HistoricalCaptureRecovery.merged(inSession)
        result.uniqueSeconds = unique.count
        var values: [Double] = []
        for row in unique.values {
            guard row.wearing else { result.rejectedWearing += 1; continue }
            guard (35...220).contains(row.heartRate) else { result.rejectedHR += 1; continue }
            guard let motion = row.dynamicAccelG else { result.rejectedMissingMotion += 1; continue }
            guard motion.isFinite, motion >= 0 else { result.rejectedInvalidMotion += 1; continue }
            guard motion <= Hrv.restingQuietAccelG else { result.rejectedActiveMotion += 1; continue }
            guard let temp = row.skinTempC else { result.rejectedMissingTemperature += 1; continue }
            guard temp.isFinite, (20...43).contains(temp) else { result.rejectedInvalidTemperature += 1; continue }
            values.append(temp)
        }
        result.eligibleSeconds = values.count
        if values.count >= result.minimumEligibleSeconds {
            result.candidateCelsius = Stats.median(values)
        }
        return result
    }
}
