import Foundation

enum NightTemperature {
    static let source = "v18-offset65-candidate"
    struct Measurement { let celsius: Double?; let seconds: Int }
    /// A night-bound, motion-verified sensor candidate. This does not establish
    /// calibration or convert the candidate into a clinical temperature sensor.
    static func measure(_ samples: [V18Sample], session: SleepSession?) -> Measurement {
        guard let session else { return Measurement(celsius: nil, seconds: 0) }
        let unique = HistoricalCaptureRecovery.merged(samples.filter {
            session.startUnix <= $0.unix && $0.unix < session.endUnix
        })
        let values = unique.values.compactMap { row -> Double? in
            guard (35...220).contains(row.heartRate), let motion = row.dynamicAccelG,
                  motion.isFinite, motion >= 0, motion <= Hrv.restingQuietAccelG,
                  let temp = row.skinTempC, temp.isFinite, (20...43).contains(temp) else { return nil }
            return temp
        }
        return Measurement(celsius: values.count >= 300 ? Stats.median(values) : nil, seconds: values.count)
    }
}
