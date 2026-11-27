import Foundation

/// A single dated assessment for Home and all locally calculated trends.
struct DatedRecovery: Encodable {
    let dateKey: String
    struct BaselineDay: Encodable {
        let dateKey: String
        let recordedState: String
        let hrvWindowSeconds: Int
        let restingHRWindowSeconds: Int?
        let lnRMSSD: Double
        let restingHR: Double
        let respiratoryRate: Double?
    }

    let day: DayMetrics?
    let baselineDays: [BaselineDay]
    let baseline: Baseline?
    let sleepNeedHours: Double
    let result: RecoveryResult

    static func evaluate(day: DayMetrics?, priorDays: [DayMetrics], date: Date,
                         sleepNeedHours: Double, calendar: Calendar = .current) -> DatedRecovery {
        let dateKey = JournalStore.dayKey(for: date, calendar: calendar)
        let unique = Dictionary(priorDays.filter { $0.dateKey < dateKey }
            .map { ($0.dateKey, $0) }, uniquingKeysWith: { _, latest in latest })
        let pairs = Array(unique.values.filter {
            $0.lnRMSSD?.isFinite == true && $0.restingHR.map { $0.isFinite && $0 > 0 } == true
        }.sorted { $0.dateKey < $1.dateKey }.suffix(DailyAnalysis.rollingBaselineDays))
        return assessment(day: day, dateKey: dateKey, baselineCandidates: pairs, sleepNeedHours: sleepNeedHours)
    }

    /// Replay the former Home row selection for the diagnostic export only.
    static func replayLegacyHome(day: DayMetrics?, priorDays: [DayMetrics], dateKey: String,
                                 sleepNeedHours: Double) -> DatedRecovery {
        let candidates = Array(priorDays.filter { $0.dateKey < dateKey }.suffix(DailyAnalysis.rollingBaselineDays))
        return assessment(day: day, dateKey: dateKey, baselineCandidates: candidates, sleepNeedHours: sleepNeedHours)
    }

    private static func assessment(day: DayMetrics?, dateKey: String, baselineCandidates: [DayMetrics],
                                   sleepNeedHours: Double) -> DatedRecovery {
        let baseline = DailyAnalysis.baseline(from: baselineCandidates)
        let matchedDay = day.flatMap { $0.dateKey == dateKey ? $0 : nil }
        let validRespRates = baselineCandidates.compactMap(\.respiratoryRate).filter { $0.isFinite && $0 > 0 }
        let respBaseline: Double? = validRespRates.count >= Recovery.minBaselineDays ? Stats.mean(validRespRates) : nil
        let result = Recovery.score(
            lnRMSSD: matchedDay?.lnRMSSD,
            rhr: matchedDay?.restingHR,
            sleepHours: matchedDay?.reliableSleepHours,
            sleepNeedHours: sleepNeedHours,
            baseline: baseline,
            respiratoryRate: matchedDay?.respiratoryRate,
            respiratoryRateBaseline: respBaseline,
            sleepPerformance: matchedDay?.sleepPerformancePct
        )
        let inputs = baselineCandidates.compactMap { day -> BaselineDay? in
            guard let lnRMSSD = day.lnRMSSD, let rhr = day.restingHR else { return nil }
            return BaselineDay(dateKey: day.dateKey, recordedState: day.state,
                               hrvWindowSeconds: day.hrvWindowSeconds,
                               restingHRWindowSeconds: day.restingHRWindowSeconds,
                               lnRMSSD: lnRMSSD, restingHR: rhr,
                               respiratoryRate: day.respiratoryRate)
        }
        return DatedRecovery(dateKey: dateKey, day: matchedDay,
                             baselineDays: inputs, baseline: baseline, sleepNeedHours: sleepNeedHours, result: result)
    }
}

enum RecoveryDiagnostics {
    struct Breakdown: Encodable {
        let rmssdMS: Double
        let hrvZ: Double
        let rhrZ: Double
        let hrvPoints: Double
        let rhrPoints: Double
        let sleepPoints: Double?
        let activeWeight: Double
        let unroundedScore: Double
        let respiratoryRate: Double?
        let respiratoryBaseline: Double?
        let respiratoryPenaltyApplied: Bool

        init?(assessment: DatedRecovery) {
            guard assessment.result.score != nil, let baseline = assessment.baseline,
                  let lnRMSSD = assessment.day?.lnRMSSD, let rhr = assessment.day?.restingHR else { return nil }
            rmssdMS = exp(lnRMSSD)
            hrvZ = baseline.lnRMSSDSD > 0 ? (lnRMSSD - baseline.lnRMSSDMean) / baseline.lnRMSSDSD : 0
            rhrZ = baseline.rhrSD > 0 ? (baseline.rhrMean - rhr) / baseline.rhrSD : 0
            hrvPoints = Recovery.logistic(hrvZ) * Recovery.hrvWeight
            rhrPoints = Recovery.logistic(rhrZ) * Recovery.rhrWeight
            sleepPoints = assessment.result.sleepComponent.flatMap { _ in
                let perf = assessment.day?.sleepPerformancePct.flatMap { $0.isFinite && $0 >= 0 ? min(100.0, $0) : nil }
                let ratio = perf ?? assessment.day?.reliableSleepHours.map { 100 * min(1, $0 / assessment.sleepNeedHours) }
                return ratio.map { $0 * Recovery.sleepWeight }
            }
            activeWeight = Recovery.hrvWeight + Recovery.rhrWeight + (sleepPoints == nil ? 0 : Recovery.sleepWeight)
            var baseScore = (hrvPoints + rhrPoints + (sleepPoints ?? 0)) / activeWeight
            let resp = assessment.day?.respiratoryRate
            let respDays = assessment.baselineDays.compactMap(\.respiratoryRate).filter { $0.isFinite && $0 > 0 }
            let rBaseline = respDays.count >= Recovery.minBaselineDays ? Stats.mean(respDays) : nil
            let penaltyApplied: Bool
            if let resp, let rBaseline, resp.isFinite, rBaseline.isFinite, rBaseline > 0, (resp - rBaseline) >= 1.2 {
                penaltyApplied = true
                let excess = (resp - rBaseline) - 1.0
                let damping = max(0.0, min(0.25, 0.10 * excess))
                baseScore *= (1.0 - damping)
            } else {
                penaltyApplied = false
            }
            unroundedScore = baseScore
            respiratoryRate = resp
            respiratoryBaseline = rBaseline
            respiratoryPenaltyApplied = penaltyApplied
        }
    }

    /// Observation-only five-minute breakdown. Does not select a preferred
    /// score, alter the estimator, or modify stored recovery.
    struct HRVWindowEvidence: Encodable {
        let startUnix: Int
        let endUnixExclusive: Int
        let observedSeconds: Int
        let eligibleQuietSeconds: Int
        let bandState2Seconds: Int
        let bandState3Seconds: Int
        let estimatedDeepSeconds: Int
        let estimatedWakeSeconds: Int
        let rawBeats: Int
        let cleanBeats: Int
        let rrDurationSeconds: Double
        let rrDurationCoverage: Double?
        let candidateRMSSD: Double?
        let productionBucketGate: String
    }

    static func hrvWindowEvidence(samples: [V18Sample], session: SleepSession) -> [HRVWindowEvidence] {
        guard session.startUnix < session.endUnix else { return [] }
        var unique: [Int: V18Sample] = [:]
        for row in samples where session.startUnix <= row.unix && row.unix < session.endUnix {
            if let old = unique[row.unix],
               !Hrv.preferRetransmittedRR(row.rrIntervalsMS, over: old.rrIntervalsMS) { continue }
            unique[row.unix] = row
        }
        let groups = Dictionary(grouping: unique.values, by: { $0.unix / 300 })
        return groups.keys.sorted().compactMap { bucket -> HRVWindowEvidence? in
            guard let rows = groups[bucket] else { return nil }
            let start = max(session.startUnix, bucket * 300)
            let end = min(session.endUnix, (bucket + 1) * 300)
            let eligible = rows.filter {
                $0.wearing && (35...220).contains($0.heartRate)
                    && $0.dynamicAccelG.map { $0.isFinite && (0...Hrv.restingQuietAccelG).contains($0) } == true
            }.sorted { $0.unix < $1.unix }
            let rrDurationMS = eligible.reduce(0) { sum, row in
                sum + row.rrIntervalsMS.filter {
                    (V18Decoder.minRRMS...V18Decoder.maxRRMS).contains($0)
                }.reduce(0, +)
            }
            let rrDuration = Double(rrDurationMS) / 1000
            let elapsed = eligible.first.flatMap { first in
                eligible.last.map { $0.unix - first.unix + 1 }
            } ?? 0
            let result = Hrv.fromSamples(eligible)
            let gate: String
            if eligible.count < 150 || elapsed < 150 { gate = "insufficient_quiet_coverage" }
            else if rrDuration < 75 { gate = "insufficient_rr_duration" }
            else if rrDurationMS > elapsed * 1050 { gate = "excess_rr_duration" }
            else if result.nnBeats < 21 || result.rmssdMS.map({ $0.isFinite && $0 > 0 }) != true {
                gate = "insufficient_clean_nn"
            } else { gate = "qualifies_primary_bucket" }
            func stageSeconds(_ stage: SleepStage) -> Int {
                rows.filter { row in session.staging.segments.contains {
                    $0.stage == stage && $0.startUnix <= row.unix && row.unix < $0.endUnix
                } }.count
            }
            return HRVWindowEvidence(startUnix: start, endUnixExclusive: end,
                observedSeconds: rows.count, eligibleQuietSeconds: eligible.count,
                bandState2Seconds: rows.filter { $0.sleepState == 2 }.count,
                bandState3Seconds: rows.filter { $0.sleepState == 3 }.count,
                estimatedDeepSeconds: stageSeconds(.deep), estimatedWakeSeconds: stageSeconds(.wake),
                rawBeats: result.beats, cleanBeats: result.nnBeats,
                rrDurationSeconds: rrDuration,
                rrDurationCoverage: elapsed > 0 ? rrDuration / Double(elapsed) : nil,
                candidateRMSSD: result.rmssdMS, productionBucketGate: gate)
        }
    }

    struct Report: Encodable {
        let calculationVersion = "strap-dated-recovery-v1"
        let createdAt = Date()
        let buildRevision: String?
        let timezone: String
        let lastCompletedHistorySync: Date?
        let assessment: DatedRecovery
        let breakdown: Breakdown?
        let legacyHomeReplay: DatedRecovery
        let legacyHomeBreakdown: Breakdown?
        let session: SleepSession
        let archiveFirstUnix: Int?
        let archiveLastUnix: Int?
        let archiveFirstRecordIndex: UInt32?
        let archiveLastRecordIndex: UInt32?
        let archiveSampleCount: Int
        let recomputedHRV: HrvResult
        let recomputedHRVWindowSeconds: Int
        let recomputedHRVUsedDeepSleep: Bool
        let quietWindows: [Hrv.RestingWindowDiagnostic]
        let deepQuietWindows: [Hrv.RestingWindowDiagnostic]
        let recomputedRHR: Double?
        var shadowHrvCandidates: [Hrv.ShadowCandidateSummary]? = nil
        var hrvWindowEvidence: [HRVWindowEvidence]? = nil
        var sleepAnalysis: SleepAnalysis? = nil
        var upcomingSleepPlan: SleepRecommendation? = nil
        var respiratoryRate: Double? = nil
        var respiratoryBaseline: Double? = nil
        var sleepPerformancePct: Double? = nil
        var skinTemperatureC: Double? = nil
        var oxygenCandidatePct: Double? = nil
        var temperatureFunnel: NightTemperature.Funnel? = nil
        var oxygenCandidateSummary: Spo2Summary? = nil
        let notes = [
            "Assessment uses persisted daily measurements. Window diagnostics are independently recomputed from the current archive.",
            "Legacy Home replay uses the earlier day-row selection with today's retained history. It cannot recover deleted or subsequently changed inputs.",
            "Recovery uses paired prior-night log RMSSD and RHR, plus sleep performance/duration relative to configured need, and validates respiratory rate against personal baseline to penalize acute illness.",
            "SpO₂, temperature and strain are secondary health indicators audited in the report.",
            "A zero baseline standard deviation contributes a neutral z-score. Missing reliable sleep removes its weight."
        ]
    }

    static func write(_ report: Report, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("recovery-\(report.assessment.dateKey)-\(UUID().uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        try encoder.encode(report).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
