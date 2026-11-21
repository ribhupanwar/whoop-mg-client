import Foundation

/// A single dated assessment for Home and all locally calculated trends.
struct DatedRecovery: Encodable {
    let dateKey: String
    struct BaselineDay: Encodable {
        let dateKey: String
        let lnRMSSD: Double
        let restingHR: Double
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
        let result = Recovery.score(lnRMSSD: matchedDay?.lnRMSSD, rhr: matchedDay?.restingHR,
                                    sleepHours: matchedDay?.reliableSleepHours,
                                    sleepNeedHours: sleepNeedHours, baseline: baseline)
        let inputs = baselineCandidates.compactMap { day -> BaselineDay? in
            guard let lnRMSSD = day.lnRMSSD, let rhr = day.restingHR else { return nil }
            return BaselineDay(dateKey: day.dateKey, lnRMSSD: lnRMSSD, restingHR: rhr)
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

        init?(assessment: DatedRecovery) {
            guard assessment.result.score != nil, let baseline = assessment.baseline,
                  let lnRMSSD = assessment.day?.lnRMSSD, let rhr = assessment.day?.restingHR else { return nil }
            rmssdMS = exp(lnRMSSD)
            hrvZ = baseline.lnRMSSDSD > 0 ? (lnRMSSD - baseline.lnRMSSDMean) / baseline.lnRMSSDSD : 0
            rhrZ = baseline.rhrSD > 0 ? (baseline.rhrMean - rhr) / baseline.rhrSD : 0
            hrvPoints = Recovery.logistic(hrvZ) * Recovery.hrvWeight
            rhrPoints = Recovery.logistic(rhrZ) * Recovery.rhrWeight
            sleepPoints = assessment.result.sleepComponent.flatMap { _ in
                assessment.day?.reliableSleepHours.map { 100 * min(1, $0 / assessment.sleepNeedHours) * Recovery.sleepWeight }
            }
            activeWeight = Recovery.hrvWeight + Recovery.rhrWeight + (sleepPoints == nil ? 0 : Recovery.sleepWeight)
            unroundedScore = (hrvPoints + rhrPoints + (sleepPoints ?? 0)) / activeWeight
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
        let notes = [
            "Assessment uses persisted daily measurements. Window diagnostics are independently recomputed from the current archive.",
            "Legacy Home replay uses the earlier day-row selection with today's retained history. It cannot recover deleted or subsequently changed inputs.",
            "Recovery uses paired prior-night log RMSSD and RHR, plus reliable sleep duration relative to the configured need when available.",
            "Respiratory rate, sleep performance, stage totals, SpO₂, temperature and strain are not direct inputs to this score.",
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
