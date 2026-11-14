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
    var sleepStaging: SleepStaging?
    /// Versioned, window-bound results; nil on older saved captures.
    var sleepSessions: [SleepSession]? = nil

    var latestSleepSession: SleepSession? { sleepSessions?.last }
    let activities: [ActivitySession]
    /// Awake 5-minute stress share against the awake baseline. nil when the
    /// capture predates the baseline or the field (older persisted summary).
    var awakeStress: StressSplit?
    /// Same, with detected workout windows removed.
    var outsideWorkoutStress: StressSplit?
    /// Per-window awake stress series for the through-the-day chart. nil until
    /// the awake baseline unlocks or on summaries stored before this field.
    var stressSeries: [StressPoint]?
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
        awakeBaseline: Baseline? = nil,
        sleepCorrections: [String: [Int]] = [:]
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

        let periods = SleepDetect.detect(ordered)
        // Nighttime resting HR is not exercise load. Exclude detected sleep
        // windows before integrating awake training impulse.
        let awakeSamples = ordered.filter { sample in
            !periods.contains { $0.startUnix <= sample.unix && sample.unix <= $0.endUnix }
        }
        var strain: Double?
        if let maxHR, let resting, maxHR > resting {
            strain = Hrv.strainScore(
                Hrv.trimp(awakeSamples, maxHR: maxHR, restingHR: resting, sex: sex)
            )
        }

        let steps = StepCounter.total(ordered)
        let sessions = SleepSession.makeAll(samples: ordered, periods: periods, overrides: sleepCorrections)
        let staging = sessions.last?.staging
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
            sleepSessions: sessions,
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
        calendar: Calendar = .current,
        sleepCorrections: [String: [Int]] = [:],
        analyzedSleepSessions: [SleepSession]? = nil
    ) -> [DayMetrics] {
        let ordered = samples.sorted { $0.unix < $1.unix }
        guard !ordered.isEmpty else { return [] }

        var byDay: [String: [V18Sample]] = [:]
        for sample in ordered {
            let date = Date(timeIntervalSince1970: TimeInterval(sample.unix))
            byDay[JournalStore.dayKey(for: date, calendar: calendar), default: []].append(sample)
        }
        let detectedPeriods = SleepDetect.detect(ordered)
        let sleepSessions = analyzedSleepSessions ?? SleepSession.makeAll(
            samples: ordered, periods: detectedPeriods, overrides: sleepCorrections
        )
        // Sleep duration, nightly biometrics and awake load must share the
        // canonical edited bounds. The measurements remain sensor-derived.
        let periods = sleepSessions.map {
            SleepPeriod(startUnix: $0.startUnix, endUnix: $0.endUnix - 1,
                        quietFraction: 0, meanHR: 0, wakeEvents: $0.movementBouts)
        }
        // Saved/edited nights can outlive raw retention; still update their dated
        // duration and reliability even when that day has no retained samples.
        for session in sleepSessions {
            let end = Date(timeIntervalSince1970: TimeInterval(session.endUnix - 1))
            let key = JournalStore.dayKey(for: end, calendar: calendar)
            if byDay[key] == nil { byDay[key] = [] }
        }

        var result: [DayMetrics] = []
        for (key, daySamples) in byDay {
            let dayPeriods = periods.filter {
                let end = Date(timeIntervalSince1970: TimeInterval($0.endUnix))
                return JournalStore.dayKey(for: end, calendar: calendar) == key
            }
            // NOOP-style per-sleep-session aggregation: derive each validated
            // session independently, then weight HRV by session duration.
            // Never join R-R beats across gaps or unrelated sleep sessions.
            let sessions: [(period: SleepPeriod, hrv: HrvResult, window: Int, rhr: Double?)] =
                dayPeriods.compactMap { period in
                    let segment = ordered.filter {
                        $0.unix >= period.startUnix && $0.unix <= period.endUnix
                    }
                    let validSeconds = Set(segment.filter {
                        $0.wearing && (35...220).contains($0.heartRate)
                    }.map(\.unix)).count
                    guard validSeconds >= 300 else { return nil }
                    let result = Hrv.restingHRV(segment, minWindowS: 300)
                    let rhr = Hrv.restingHeartRate(segment, windowS: 300)
                    return (period: period, hrv: result.result,
                            window: result.windowSeconds, rhr: rhr)
                }
            // Use the primary (longest) sleep session, so a low-HR nap cannot
            // change the overnight reference. RHR does not require R-R beats.
            let resting = sessions.max { $0.period.durationS < $1.period.durationS }?.rhr
            let weightedHRV: Double? = {
                let values = sessions.compactMap { session -> (Double, Double)? in
                    guard let rmssd = session.hrv.rmssdMS,
                          rmssd.isFinite, rmssd > 0 else { return nil }
                    guard session.window >= 300, session.hrv.nnBeats >= 20 else { return nil }
                    // Weight by the verified quiet R-R window, not time in bed.
                    return (rmssd, Double(session.window))
                }
                let weight = values.reduce(0.0) { $0 + $1.1 }
                guard weight > 0 else { return nil }
                return values.reduce(0.0) { $0 + $1.0 * $1.1 } / weight
            }()
            let nightlyLnRMSSD = weightedHRV.map { log($0) }
            let nightlyWindowSeconds = sessions.reduce(0) { $0 + $1.window }
            let daySleep = sleepSessions.filter {
                JournalStore.dayKey(
                    for: Date(timeIntervalSince1970: TimeInterval($0.endUnix - 1)),
                    calendar: calendar
                ) == key
            }
            let sleepHours = daySleep.reduce(0.0) { $0 + ($1.asleepHours ?? 0) }
            let sleepReliable = !daySleep.isEmpty && daySleep.allSatisfy(\.isComplete)
            let longest = daySleep.max { $0.timeInBedHours < $1.timeInBedHours }
            // Training load needs a measured resting reference, not sleep stages
            // or R-R intervals. A verified five-minute daytime rest can supply it.
            let awakeDaySamples = daySamples.filter { sample in
                !periods.contains { $0.startUnix <= sample.unix && sample.unix <= $0.endUnix }
            }
            let awakeWindow = Hrv.restingHRV(awakeDaySamples, minWindowS: 300)
            let awakeResting = Hrv.restingHeartRate(awakeDaySamples, windowS: 300)
            let strainResting = resting ?? Hrv.restingHeartRate(daySamples, windowS: 300)
            var strain: Double?
            var zoneSeconds: [Int]?
            if let maxHR, let strainResting, maxHR > strainResting {
                let zoneSamples = awakeDaySamples.filter { $0.wearing && (35...220).contains($0.heartRate) }
                if !zoneSamples.isEmpty, let zones = Karvonen.zones(restingHR: strainResting, maxHR: maxHR) {
                    let points = zoneSamples.map {
                        LiveSample(unix: $0.unix, heartRate: $0.heartRate, rrIntervalsMS: [])
                    }
                    zoneSeconds = LiveZones.seconds(samples: points, zones: zones)
                }
                strain = Hrv.strainScore(
                    Hrv.trimp(awakeDaySamples, maxHR: maxHR, restingHR: strainResting, sex: sex)
                )
            }
            let steps = StepCounter.total(daySamples)
            result.append(
                DayMetrics(
                    dateKey: key,
                    state: daySleep.isEmpty ? "awake" : "sleep",
                    restingHR: resting,
                    lnRMSSD: nightlyLnRMSSD,
                    hrvWindowSeconds: nightlyWindowSeconds,
                    sleepHours: sleepHours,
                    sleepStartUnix: longest?.startUnix,
                    sleepEndUnix: longest.map { $0.endUnix - 1 },
                    strain: strain,
                    steps: steps,
                    sleepDurationReliable: sleepReliable,
                    zoneSeconds: zoneSeconds,
                    awakeLnRMSSD: awakeWindow.result.lnRMSSD,
                    awakeRestingHR: awakeResting
                )
            )
        }
        return result.sorted { $0.dateKey < $1.dateKey }
    }

    /// Sleep measurements cannot stand in for an awake-quiet stress baseline.
    static func awakeBaseline(from days: [DayMetrics]) -> Baseline? {
        let pairs = days.compactMap { day -> (Double, Double)? in
            guard let ln = day.awakeLnRMSSD, ln.isFinite,
                  let rhr = day.awakeRestingHR, rhr.isFinite, rhr > 0 else { return nil }
            return (ln, rhr)
        }
        return Baseline.fromDaily(lnRMSSD: pairs.map { $0.0 }, rhr: pairs.map { $0.1 })
    }

    /// Shared by Home and Health. Stage coverage is independent of a validated
    /// five-minute nightly R-R measurement; missing stages must not hide HRV.
    static func latestNightHRV(from days: [DayMetrics]) -> Double? {
        for day in days.sorted(by: { $0.dateKey > $1.dateKey }) {
            guard day.state == "sleep", day.hrvWindowSeconds >= 300,
                  let ln = day.lnRMSSD else { continue }
            let value = exp(ln)
            if value.isFinite && value > 0 { return value }
        }
        return nil
    }

    /// Rolling partial archives cannot replace a saved full night with its tail.
    /// Explicit user edits may change the bounds even when old raw data has expired.
    static func replacesSleep(
        previous: DayMetrics, fresh: DayMetrics, coverageStart: Int?, coverageEnd: Int?,
        isEdited: Bool = false
    ) -> Bool {
        guard fresh.sleepDurationReliable != nil else { return false }
        if isEdited && fresh.sleepStartUnix != nil { return true }
        guard let start = previous.sleepStartUnix, let end = previous.sleepEndUnix else {
            return fresh.sleepStartUnix != nil
        }
        guard let first = coverageStart, let last = coverageEnd else { return false }
        return first <= start && end <= last
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
