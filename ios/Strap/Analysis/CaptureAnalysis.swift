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

    var latestSleepSession: SleepSession? {
        sleepSessions?.filter { $0.classification == .overnight && $0.endUnix > $0.startUnix }
            .max { $0.endUnix < $1.endUnix }
    }
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
    /// Local 0-21 WHOOP-derived strain estimate; not yet device-validated.
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
        sleepCorrections: [String: [Int]] = [:],
        analysisCache: HistoryAnalysisCache? = nil,
        sleepProgress: ((Int, Int, Bool) -> Void)? = nil
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
        let sessions = SleepSession.makeAll(samples: ordered, periods: periods, overrides: sleepCorrections,
                                            cache: analysisCache, progress: sleepProgress)
        // Sleep duration, nightly biometrics and awake load must share the
        // canonical edited bounds. The measurements remain sensor-derived.
        let canonicalPeriods = sessions.map {
            SleepPeriod(startUnix: $0.startUnix, endUnix: $0.endUnix - 1,
                        quietFraction: 0, meanHR: 0, wakeEvents: $0.movementBouts)
        }
        let awakeSamples = ordered.filter { sample in
            !canonicalPeriods.contains { $0.startUnix <= sample.unix && sample.unix <= $0.endUnix }
        }
        var strain: Double?
        if let maxHR, let resting, maxHR > resting {
            strain = WhoopDerivedStrain.score(awakeSamples, restingHR: resting, maxHR: maxHR)
        }

        let steps = StepCounter.total(ordered)
        let staging = sessions.last?.staging
        let activities = ActivityDetect.detect(
            ordered, sleepPeriods: canonicalPeriods, restingHR: resting, maxHR: maxHR
        )
        let sleepWindows = canonicalPeriods.map { (start: $0.startUnix, end: $0.endUnix) }
        let workoutWindows = sleepWindows + activities.map { (start: $0.startUnix, end: $0.endUnix) }
        let stressSeries = StressWindows.series(
            samples: ordered, baseline: awakeBaseline, excluded: sleepWindows
        )

        let firstUnix = ordered.first?.unix
        let lastUnix = ordered.last?.unix
        let span = (firstUnix != nil && lastUnix != nil) ? max(0, lastUnix! - firstUnix!) : 0

        return CaptureSummary(
            sampleCount: ordered.count,
            wearingCount: wearing.count,
            firstUnix: firstUnix,
            lastUnix: lastUnix,
            spanSeconds: span,
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
    /// Canonical rolling baseline window discovered from WHOOP `GetRestingHeartRateBaselineRequest` (`0x1099623a0`).
    /// WHOOP evaluates baseline statistics over a rolling buffer of 28 eligible days.
    static let rollingBaselineDays = 28

    /// Use a single canonical session for all nightly biometrics. Prefer the
    /// existing overnight classification when present; keep the established
    /// longest-session fallback for days without an overnight classification.
    static func primaryNight(_ sessions: [SleepSession]) -> SleepSession? {
        let valid = sessions.filter { $0.endUnix > $0.startUnix }
        let overnight = valid.filter { $0.classification == .overnight }
        return (overnight.isEmpty ? valid : overnight).max {
            if $0.timeInBedHours != $1.timeInBedHours { return $0.timeInBedHours < $1.timeInBedHours }
            return $0.startUnix > $1.startUnix
        }
    }
    /// Inclusive range in the chronologically sorted archive. Preserve all
    /// records at either boundary, including replayed seconds.
    static func rows(in ordered: [V18Sample], from start: Int, through end: Int) -> ArraySlice<V18Sample> {
        guard start <= end else { return ordered.prefix(0) }
        func partition(where precedes: (Int) -> Bool) -> Int {
            var lower = 0
            var upper = ordered.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if precedes(ordered[middle].unix) { lower = middle + 1 } else { upper = middle }
            }
            return lower
        }
        let first = partition { $0 < start }
        let last = partition { $0 <= end }
        return ordered[first..<last]
    }

    static func metrics(
        from samples: [V18Sample],
        sex: Sex,
        maxHR: Double?,
        calendar: Calendar = .current,
        sleepCorrections: [String: [Int]] = [:],
        analyzedSleepSessions: [SleepSession]? = nil,
        analysisCache: HistoryAnalysisCache? = nil,
        shouldContinue: () -> Bool = { true },
        diagnostic: ((String, String, Int) -> Void)? = nil,
        progress: ((Int, Int, Bool) -> Void)? = nil
    ) -> [DayMetrics] {
        let ordered = samples.sorted { $0.unix < $1.unix }
        guard !ordered.isEmpty else { return [] }

        var byDay: [String: [V18Sample]] = [:]
        var currentDayKey = ""
        var currentDayStartUnix = Int.max
        var currentDayEndUnix = Int.min

        for sample in ordered {
            if sample.unix >= currentDayStartUnix && sample.unix < currentDayEndUnix {
                byDay[currentDayKey, default: []].append(sample)
            } else {
                let date = Date(timeIntervalSince1970: TimeInterval(sample.unix))
                let key = JournalStore.dayKey(for: date, calendar: calendar)
                currentDayKey = key
                if let interval = calendar.dateInterval(of: .day, for: date) {
                    currentDayStartUnix = Int(interval.start.timeIntervalSince1970)
                    currentDayEndUnix = Int(interval.end.timeIntervalSince1970)
                } else {
                    currentDayStartUnix = sample.unix
                    currentDayEndUnix = sample.unix + 1
                }
                byDay[key, default: []].append(sample)
            }
        }
        let sleepSessions = analyzedSleepSessions ?? SleepSession.makeAll(
            samples: ordered, periods: SleepDetect.detect(ordered), overrides: sleepCorrections
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
        for key in byDay.keys.sorted() {
            guard shouldContinue() else { break }
            var stageStart = DispatchTime.now().uptimeNanoseconds
            func mark(_ stage: String) {
                let now = DispatchTime.now().uptimeNanoseconds
                diagnostic?(key, stage, Int((now - stageStart) / 1_000_000))
                stageStart = now
            }
            mark("begin")
            let daySamples = byDay[key]!
            let dayPeriods = periods.filter {
                let end = Date(timeIntervalSince1970: TimeInterval($0.endUnix))
                return JournalStore.dayKey(for: end, calendar: calendar) == key
            }
            struct DayContext: Codable {
                let key: String
                let sex: Sex
                let maxHR: Double?
                let calendar: String
                let zone: String
                let sessions: [SleepSession]
                let primarySelectionRecipe: Int
            }
            // A night ending today can begin yesterday. Include its earlier
            // packets and every canonical bound that excludes today's awake load.
            let first = daySamples.first?.unix ?? dayPeriods.first?.startUnix ?? 0
            let last = daySamples.last?.unix ?? dayPeriods.last?.endUnix ?? first
            let related = sleepSessions.filter { session in
                (session.startUnix <= last && first < session.endUnix)
                    || dayPeriods.contains { $0.startUnix == session.startUnix && $0.endUnix == session.endUnix - 1 }
            }
            let ticket = analysisCache.flatMap { cache in
                let lower = min(first, dayPeriods.map(\.startUnix).min() ?? first)
                let upper = max(last, dayPeriods.map(\.endUnix).max() ?? last)
                let inputs = rows(in: ordered, from: lower, through: upper).filter { row in
                    (first <= row.unix && row.unix <= last)
                        || dayPeriods.contains { $0.startUnix <= row.unix && row.unix <= $0.endUnix }
                }
                let context = DayContext(key: key, sex: sex, maxHR: maxHR,
                                         calendar: String(describing: calendar.identifier),
                                         zone: calendar.timeZone.identifier, sessions: related, primarySelectionRecipe: 1)
                return cache.ticket(key: HistoryAnalysisCache.dailyKey(key), samples: inputs, context: context)
            }
            if let saved = analysisCache?.load(DayMetrics.self, ticket: ticket) {
                mark("cache hit")
                result.append(saved)
                progress?(result.count, byDay.count, true)
                continue
            }
            mark("cache miss; starting nightly biometrics")
            let daySleep = sleepSessions.filter {
                JournalStore.dayKey(
                    for: Date(timeIntervalSince1970: TimeInterval($0.endUnix - 1)),
                    calendar: calendar
                ) == key
            }
            // Select the canonical session BEFORE examining available RR/HR.
            // Missing overnight measurements cannot be replaced by a nap.
            let longest = primaryNight(daySleep)
            let primaryRows = longest.map {
                Array(rows(in: ordered, from: $0.startUnix, through: $0.endUnix - 1))
            } ?? []
            let validSeconds = Set(primaryRows.filter {
                $0.wearing && (35...220).contains($0.heartRate)
            }.map(\.unix)).count
            let deepEpochs = longest?.staging.segments.filter { $0.stage == .deep }
                .compactMap { $0.endUnix > $0.startUnix ? ($0.startUnix...($0.endUnix - 1)) : nil } ?? []
            let primary = validSeconds >= 300
                ? Hrv.windowedSleepHRV(primaryRows, deepEpochs: deepEpochs, windowSeconds: 300) : nil
            let resting = validSeconds >= 300 ? Hrv.restingHeartRate(primaryRows, windowS: 300) : nil
            let primaryRMSSD: Double? = {
                guard let primary, let rmssd = primary.result.rmssdMS,
                      rmssd.isFinite, rmssd > 0,
                      primary.windowSeconds >= 300, primary.result.nnBeats >= 20 else { return nil }
                return rmssd
            }()
            let nightlyLnRMSSD = primaryRMSSD.map { log($0) }
            let nightlyWindowSeconds = primary?.windowSeconds ?? 0
            let sleepHours = daySleep.reduce(0.0) { $0 + ($1.asleepHours ?? 0) }
            let sleepReliable = !daySleep.isEmpty && daySleep.allSatisfy(\.isComplete)
            let temperature = NightTemperature.measure(primaryRows, session: longest)
            // Training load needs a measured resting reference, not sleep stages
            // or R-R intervals. A verified five-minute daytime rest can supply it.
            let overlappingPeriods = periods.filter { $0.startUnix <= last && $0.endUnix >= first }
            let awakeDaySamples = daySamples.filter { sample in
                !overlappingPeriods.contains { $0.startUnix <= sample.unix && sample.unix <= $0.endUnix }
            }
            mark("nightly biometrics; starting awake HRV")
            let awakeWindow = Hrv.restingHRV(awakeDaySamples, minWindowS: 300)
            mark("awake HRV; starting awake RHR")
            let awakeResting = Hrv.restingHeartRate(awakeDaySamples, windowS: 300)
            mark("awake RHR")
            let strainResting = awakeResting
            var strain: Double?
            var zoneSeconds: [Int]?
            let zoneSamples = awakeDaySamples.filter { $0.wearing && (35...220).contains($0.heartRate) }
            // Zone calibration can use a verified overnight RHR even when the
            // day has no five-minute quiet awake run. Strain keeps its own gate.
            if let maxHR, let zoneResting = resting ?? awakeResting {
                if !zoneSamples.isEmpty, let zones = Karvonen.zones(restingHR: zoneResting, maxHR: maxHR) {
                    let points = zoneSamples.map {
                        LiveSample(unix: $0.unix, heartRate: $0.heartRate, rrIntervalsMS: [])
                    }
                    zoneSeconds = LiveZones.seconds(samples: points, zones: zones)
                }
            }
            if let maxHR, let strainResting, maxHR > strainResting {
                strain = WhoopDerivedStrain.score(awakeDaySamples, restingHR: strainResting, maxHR: maxHR)
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
                    awakeRestingHR: awakeResting,
                    restingHRWindowSeconds: resting == nil ? nil : 300,
                    skinTemperatureC: temperature.celsius,
                    skinTemperatureSeconds: temperature.seconds,
                    skinTemperatureSource: temperature.celsius == nil ? nil : NightTemperature.source,
                    oxygenCandidatePct: Recovery.spo2Summary(primaryRows).pct,
                    zoneCoverageStartUnix: zoneSeconds == nil ? nil : zoneSamples.first?.unix,
                    zoneCoverageEndUnix: zoneSeconds == nil ? nil : zoneSamples.last.map { $0.unix + 1 }
                )
            )
            mark("daily metrics; saving checkpoint")
            if let day = result.last { analysisCache?.save(day, ticket: ticket) }
            mark("checkpoint complete")
            progress?(result.count, byDay.count, false)
        }
        return result.sorted { $0.dateKey < $1.dateKey }
    }

    /// A corrected night owns its biometric inputs, including unavailable ones.
    /// Keep unrelated recorded totals when a partial sync cannot replace them.
    static func mergeDay(previous: DayMetrics, fresh: DayMetrics, replacesSleep: Bool) -> DayMetrics {
        return DayMetrics(
                dateKey: fresh.dateKey,
                state: fresh.state == "sleep" ? fresh.state : previous.state,
                restingHR: replacesSleep ? fresh.restingHR : previous.restingHR,
                lnRMSSD: replacesSleep ? fresh.lnRMSSD : previous.lnRMSSD,
                hrvWindowSeconds: replacesSleep ? fresh.hrvWindowSeconds : previous.hrvWindowSeconds,
                // Recomputed sleep is authoritative when a detected night is present.
                // A max() merge would permanently preserve the older inflated value.
                sleepHours: replacesSleep ? fresh.sleepHours : previous.sleepHours,
                sleepStartUnix: replacesSleep ? fresh.sleepStartUnix : previous.sleepStartUnix,
                sleepEndUnix: replacesSleep ? fresh.sleepEndUnix : previous.sleepEndUnix,
                // Strain is a recomputed score, not an additive counter.
                // Keeping the historical maximum permanently locks in an
                // overestimated value after HR/sleep quality improves.
                // Prefer a fresh, valid recomputation; preserve the prior
                // score only when this capture cannot calculate one.
                strain: fresh.strain.flatMap { $0.isFinite && (0...21).contains($0) ? $0 : nil }
                    ?? previous.strain,
                steps: fresh.steps == nil && previous.steps == nil ? nil :
                    max(fresh.steps ?? 0, previous.steps ?? 0),
                sleepDurationReliable: replacesSleep ? fresh.sleepDurationReliable : previous.sleepDurationReliable,
                respiratoryRate: replacesSleep ? fresh.respiratoryRate : previous.respiratoryRate,
                sleepPerformancePct: replacesSleep ? fresh.sleepPerformancePct : previous.sleepPerformancePct,
                zoneSeconds: fresh.zoneSeconds ?? previous.zoneSeconds,
                awakeLnRMSSD: fresh.awakeLnRMSSD ?? previous.awakeLnRMSSD,
                awakeRestingHR: fresh.awakeRestingHR ?? previous.awakeRestingHR,
                restingHRWindowSeconds: replacesSleep ? fresh.restingHRWindowSeconds : previous.restingHRWindowSeconds,
                respiratoryWindows: replacesSleep ? fresh.respiratoryWindows : previous.respiratoryWindows,
                skinTemperatureC: replacesSleep ? fresh.skinTemperatureC : previous.skinTemperatureC,
                skinTemperatureSeconds: replacesSleep ? fresh.skinTemperatureSeconds : previous.skinTemperatureSeconds,
                skinTemperatureSource: replacesSleep ? fresh.skinTemperatureSource : previous.skinTemperatureSource,
                oxygenCandidatePct: replacesSleep ? fresh.oxygenCandidatePct : previous.oxygenCandidatePct,
                zoneCoverageStartUnix: fresh.zoneSeconds == nil ? previous.zoneCoverageStartUnix : fresh.zoneCoverageStartUnix,
                zoneCoverageEndUnix: fresh.zoneSeconds == nil ? previous.zoneCoverageEndUnix : fresh.zoneCoverageEndUnix
            )
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
        isEdited: Bool = false,
        previousIsEdited: Bool = false
    ) -> Bool {
        guard fresh.sleepDurationReliable != nil else { return false }
        if isEdited && fresh.sleepStartUnix != nil { return true }
        if previousIsEdited && !isEdited { return false }
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
