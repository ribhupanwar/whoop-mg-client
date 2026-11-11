import Foundation

/// Everything the UI can show from one captured sample window. Computed once
/// per capture so screens read plain values instead of re-deriving metrics.
struct CaptureSummary: Codable, Equatable {
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
    /// Four-class estimate for the most recent detected period. Nil on
    /// captures stored before staging existed; a refusal arrives as a reason,
    /// not as fabricated light sleep.
    let sleepStaging: SleepStaging?
    let activities: [ActivitySession]
    /// Awake 5-minute stress share against the awake baseline. nil when the
    /// capture predates the baseline or the field (older persisted summary).
    let awakeStress: StressSplit?
    /// Same, with detected workout windows removed.
    let outsideWorkoutStress: StressSplit?
    /// Per-window awake stress series for the through-the-day chart. nil until
    /// the awake baseline unlocks or on summaries stored before this field.
    let stressSeries: [StressPoint]?
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
        sleepPeriods: [], sleepStaging: nil, activities: [], awakeStress: nil, outsideWorkoutStress: nil,
        stressSeries: nil,
        skinTempMean: nil, skinTempMin: nil,
        skinTempMax: nil, motionMeanG: nil, steps: nil, strain: nil
    )

    static func make(
        samples: [V18Sample],
        sex: Sex,
        maxHR: Double?,
        awakeBaseline: Baseline? = nil
    ) -> CaptureSummary {
        let ordered = samples.sorted { $0.unix < $1.unix }
        guard !ordered.isEmpty else { return .empty }
        let wearing = ordered.filter { $0.wearing }
        let heartRates = wearing.map { Double($0.heartRate) }
        // Skin temperature is only meaningful while worn. Off-wrist samples
        // can reflect room temperature and corrupt the nightly baseline.
        // Band v18 offset 65 is a skin-contact sensor candidate. Ignore
        // disconnected/invalid temperatures; don't substitute phone weather
        // or ambient sensors. This is not core body temperature.
        let skinTemps = wearing.compactMap { sample -> Double? in
            guard let temp = sample.skinTempC, temp.isFinite,
                  (20.0...43.0).contains(temp) else { return nil }
            return temp
        }
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

        let steps = StepCounter.total(ordered)

        let periods = SleepDetect.detect(ordered)
        let staging = periods.last.map {
            SleepStager.stage(samples: ordered, period: $0)
        }
        let activities = ActivityDetect.detect(ordered, sleepPeriods: periods)
        let sleepWindows = periods.map { (start: $0.startUnix, end: $0.endUnix) }
        let workoutWindows = sleepWindows + activities.map { (start: $0.startUnix, end: $0.endUnix) }
        let stressSeries = StressWindows.series(
            samples: ordered, baseline: awakeBaseline, excluded: sleepWindows
        )

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
            sleepPeriods: periods,
            sleepStaging: staging,
            activities: activities,
            awakeStress: StressWindows.share(
                samples: ordered, baseline: awakeBaseline, excluded: sleepWindows
            ),
            outsideWorkoutStress: StressWindows.share(
                samples: ordered, baseline: awakeBaseline, excluded: workoutWindows
            ),
            stressSeries: stressSeries.isEmpty ? nil : stressSeries,
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
            let dayPeriods = periods.filter {
                let end = Date(timeIntervalSince1970: TimeInterval($0.endUnix))
                return JournalStore.dayKey(for: end, calendar: calendar) == key
            }
            // Physiological daily RHR/HRV must come from the preceding night,
            // not an arbitrary daytime quiet window or a day split at midnight.
            let overnight = ordered.filter { sample in
                dayPeriods.contains { $0.startUnix <= sample.unix && sample.unix <= $0.endUnix }
            }
            // Prefer the longest primary sleep session: a short nap must not
            // displace the night's RHR or HRV. Require real temporal coverage,
            // not merely a count of duplicated or densely sampled records.
            let primary = dayPeriods.max { $0.durationS < $1.durationS }
            let primarySamples = ordered.filter { sample in
                guard let primary else { return false }
                return sample.unix >= primary.startUnix && sample.unix <= primary.endUnix
            }
            let validSeconds = Set(primarySamples.filter {
                $0.wearing && (35...220).contains($0.heartRate)
            }.map(\.unix)).count
            let enoughCoverage = validSeconds >= 300
            // NOOP-compatible five-minute sustained floor, instead of the
            // former one-minute minimum. Keep missing data as nil.
            let resting: Double? = enoughCoverage
                ? Hrv.restingHeartRate(primarySamples, windowS: 300) : nil
            let restingHrv = enoughCoverage
                ? Hrv.restingHRV(primarySamples) : (.empty, 0)
            let sleepHours = dayPeriods.reduce(0.0) { $0 + $1.hours }
            let longest = dayPeriods.max { $0.durationS < $1.durationS }
            var strain: Double?
            if let maxHR, let resting, maxHR > resting {
                strain = Hrv.strainScore(
                    Hrv.trimp(daySamples, maxHR: maxHR, restingHR: resting, sex: sex)
                )
            }
            let steps = StepCounter.total(daySamples)
            result.append(
                DayMetrics(
                    dateKey: key,
                    state: sleepHours >= 3 ? "sleep" : "awake",
                    restingHR: resting,
                    lnRMSSD: restingHrv.result.lnRMSSD,
                    hrvWindowSeconds: restingHrv.windowSeconds,
                    sleepHours: sleepHours,
                    sleepStartUnix: longest?.startUnix,
                    sleepEndUnix: longest?.endUnix,
                    strain: strain,
                    steps: steps
                )
            )
        }
        return result.sorted { $0.dateKey < $1.dateKey }
    }

    /// Baseline from paired daily values. Days without both resting HR and
    /// HRV are skipped, so the two series stay aligned. Pass already-filtered
    /// days: stress needs awake days, sleep stress needs nights.
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
