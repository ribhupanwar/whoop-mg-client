import Foundation

/// Everything the UI can show from one captured sample window. Computed once
/// per capture so screens read plain values instead of re-deriving metrics.
struct CaptureSummary: Equatable {
    let sampleCount: Int
    let wearingCount: Int
    let firstUnix: Int?
    let lastUnix: Int?
    let spanSeconds: Int
    let lastHeartRate: Int?
    let heartRateMin: Int?
    let heartRateMax: Int?
    let heartRateMean: Double?
    /// Per-minute means of on-wrist heart rate, in chronological order.
    let heartRateSeries: [Double]
    let restingHeartRate: Double?
    let hrv: HrvResult
    let hrvWindowSeconds: Int
    let respiration: RespRate
    let spo2: Spo2Summary
    let sleepPeriods: [SleepPeriod]
    let activities: [ActivitySession]
    let skinTempMean: Double?
    let skinTempMin: Double?
    let skinTempMax: Double?
    let motionMeanG: Double?
    let steps: Int?
    /// Local 0-21 strain from Banister TRIMP. nil until sex and a max HR are set.
    let strain: Double?

    static let empty = CaptureSummary(
        sampleCount: 0, wearingCount: 0, firstUnix: nil, lastUnix: nil,
        spanSeconds: 0, lastHeartRate: nil, heartRateMin: nil, heartRateMax: nil,
        heartRateMean: nil, heartRateSeries: [], restingHeartRate: nil,
        hrv: .empty, hrvWindowSeconds: 0,
        respiration: RespRate(breathsPerMinute: nil, reason: nil, beats: 0, windows: 0),
        spo2: Spo2Summary(pct: nil, readings: 0, saturated: 0, diagnostic: 0, reason: nil),
        sleepPeriods: [], activities: [], skinTempMean: nil, skinTempMin: nil,
        skinTempMax: nil, motionMeanG: nil, steps: nil, strain: nil
    )

    static func make(
        samples: [V18Sample],
        sex: Sex,
        maxHR: Double?
    ) -> CaptureSummary {
        let ordered = samples.sorted { $0.unix < $1.unix }
        guard !ordered.isEmpty else { return .empty }
        let wearing = ordered.filter { $0.wearing }
        let heartRates = wearing.map { Double($0.heartRate) }
        let skinTemps = ordered.compactMap { $0.skinTempC }
        let motion = ordered.compactMap { $0.dynamicAccelG }

        var minuteBuckets: [Int: [Double]] = [:]
        for sample in wearing {
            minuteBuckets[sample.unix / 60, default: []].append(Double(sample.heartRate))
        }
        let series = minuteBuckets.keys.sorted().map { Stats.mean(minuteBuckets[$0]!) }

        let resting = Hrv.restingHeartRate(ordered)
        let restingWindow = Hrv.restingHRV(ordered)

        var strain: Double?
        if let maxHR, let resting, maxHR > resting {
            strain = Hrv.strainScore(
                Hrv.trimp(ordered, maxHR: maxHR, restingHR: resting, sex: sex)
            )
        }

        let counters = ordered.compactMap { $0.stepCounter }
        var steps: Int?
        if let first = counters.first, let last = counters.last, last >= first {
            steps = (last - first) & 0xFFFF
        }

        return CaptureSummary(
            sampleCount: ordered.count,
            wearingCount: wearing.count,
            firstUnix: ordered.first?.unix,
            lastUnix: ordered.last?.unix,
            spanSeconds: ordered.last!.unix - ordered.first!.unix,
            lastHeartRate: ordered.last(where: { $0.wearing })?.heartRate,
            heartRateMin: heartRates.min().map { Int($0) },
            heartRateMax: heartRates.max().map { Int($0) },
            heartRateMean: heartRates.isEmpty ? nil : Stats.mean(heartRates),
            heartRateSeries: series,
            restingHeartRate: resting,
            hrv: restingWindow.result,
            hrvWindowSeconds: restingWindow.windowSeconds,
            respiration: Respiration.estimate(ordered),
            spo2: Recovery.spo2Summary(ordered),
            sleepPeriods: SleepDetect.detect(ordered),
            activities: ActivityDetect.detect(ordered),
            skinTempMean: skinTemps.isEmpty ? nil : Stats.mean(skinTemps),
            skinTempMin: skinTemps.min(),
            skinTempMax: skinTemps.max(),
            motionMeanG: motion.isEmpty ? nil : Stats.mean(motion),
            steps: steps,
            strain: strain
        )
    }
}

/// Per-local-day metrics, the input a personal baseline is built from.
enum DailyAnalysis {
    static func metrics(
        from samples: [V18Sample],
        sex: Sex,
        maxHR: Double?,
        calendar: Calendar = .current
    ) -> [DayMetrics] {
        let ordered = samples.sorted { $0.unix < $1.unix }
        guard !ordered.isEmpty else { return [] }

        var byDay: [String: [V18Sample]] = [:]
        for sample in ordered {
            let date = Date(timeIntervalSince1970: TimeInterval(sample.unix))
            byDay[JournalStore.dayKey(for: date, calendar: calendar), default: []].append(sample)
        }
        let periods = SleepDetect.detect(ordered)

        var result: [DayMetrics] = []
        for (key, daySamples) in byDay {
            let resting = Hrv.restingHeartRate(daySamples)
            let restingHrv = Hrv.restingHRV(daySamples)
            let sleepHours = periods.reduce(0.0) { total, period in
                let end = Date(timeIntervalSince1970: TimeInterval(period.endUnix))
                return JournalStore.dayKey(for: end, calendar: calendar) == key
                    ? total + period.hours
                    : total
            }
            var strain: Double?
            if let maxHR, let resting, maxHR > resting {
                strain = Hrv.strainScore(
                    Hrv.trimp(daySamples, maxHR: maxHR, restingHR: resting, sex: sex)
                )
            }
            let counters = daySamples.compactMap { $0.stepCounter }
            var steps: Int?
            if let first = counters.first, let last = counters.last, last >= first {
                steps = (last - first) & 0xFFFF
            }
            result.append(
                DayMetrics(
                    dateKey: key,
                    restingHR: resting,
                    lnRMSSD: restingHrv.result.lnRMSSD,
                    hrvWindowSeconds: restingHrv.windowSeconds,
                    sleepHours: sleepHours,
                    strain: strain,
                    steps: steps
                )
            )
        }
        return result.sorted { $0.dateKey < $1.dateKey }
    }

    /// Baseline from paired daily values. Days without both resting HR and
    /// HRV are skipped, so the two series stay aligned.
    static func baseline(from days: [DayMetrics]) -> Baseline? {
        let pairs = days.compactMap { day -> (lnRMSSD: Double, rhr: Double)? in
            guard let hrv = day.lnRMSSD, let rhr = day.restingHR else { return nil }
            return (hrv, rhr)
        }
        return Baseline.fromDaily(
            lnRMSSD: pairs.map { $0.lnRMSSD },
            rhr: pairs.map { $0.rhr }
        )
    }
}
