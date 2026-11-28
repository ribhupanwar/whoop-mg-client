import Foundation

// MARK: - CalorieShadowValidator
//
// Diagnostic-only shadow validator. Zero production call sites. No historical
// records are modified. Both production `Calories` and experimental
// `WhoopRecoveredCalories` run from the same timestamped HR input so their
// outputs can be compared sample-for-sample under identical workout conditions.
//
// Output type: CalorieShadowReport (Codable). Attach to workout diagnostics.
// Frozen algorithms: Calories.swift, WhoopRecoveredCalories.swift — UNCHANGED.

enum CalorieShadowValidator {

    // MARK: - Input types

    /// A single HR observation with a Unix timestamp in seconds.
    /// Pass nil bpm for BLE gap markers or missing-data placeholders.
    struct HRSample: Codable, Equatable {
        /// Unix timestamp in whole seconds.
        let unix: Int
        /// nil = missing / BLE gap. Non-finite or out-of-(35...220) also excluded.
        let bpm: Double?
        // Recorder observations retain fractional receipt timestamps and explicit continuity breaks.
        var preciseUnix: Double? = nil
        var segment: Int = 0
        var time: Double { preciseUnix ?? Double(unix) }
    }

    /// Body profile required by both calculators.
    struct BodyProfile: Codable, Equatable {
        let weightKg: Double
        /// Height in centimetres (production Calories.swift uses cm).
        let heightCm: Double
        let age: Double
        let sex: Sex
        /// Recovered-engine baseline code: 0=male HB, 1=female HB, 2=mean.
        /// Pass 2 (mean) when the WHOOP sex mapping for the enum is unresolved.
        let recoveredBaseline: Int
    }

    /// Workout metadata.
    struct WorkoutContext: Codable, Equatable {
        let kind: WorkoutKind
        let startUnix: Int
        let endUnix: Int
        /// Total steps for cadence/MET fallback; 0 when unavailable.
        let steps: Int
        /// Resting HR measured before this workout (last-night or cycle value).
        let restingHR: Double
        /// Maximum HR anchor. User-configured or observed peak — never invented.
        let maxHR: Double
        let profile: BodyProfile
        var activeSeconds: Double? = nil
    }

    enum WorkoutKind: String, Codable, CaseIterable {
        case run, treadmill, walk, strength, cardio, unknown
    }

    // MARK: - Gap and pause annotation

    /// Classified interval between two adjacent sorted HR samples.
    struct IntervalAnnotation: Codable, Equatable {
        enum Kind: String, Codable {
            /// Normal coverage (gap ≤ 3 s — both engines can bill it).
            case normal
            /// Duplicate timestamp (zero duration).
            case duplicate
            /// Gap 4–30 s: recorder bills the interval; recovered engine caps at 3 s.
            case shortGap
            /// Gap > 30 s: recorder rejects; recovered caps at 3 s unless an explicit break.
            case longGap
        }
        let startUnix: Int
        let endUnix: Int
        let gapSeconds: Int
        let kind: Kind
    }

    // MARK: - Per-segment breakdown (optional detail)

    struct SegmentEnergy: Codable, Equatable {
        let startUnix: Int
        let endUnix: Int
        let coveredSeconds: Double
        let grossKcal: Double
        let activeKcal: Double
        /// gross − resting for the covered window.
        let netAboveRestingKcal: Double
    }

    // MARK: - Shadow report (top-level output)

    struct CalorieShadowReport: Codable, Equatable {
        let context: WorkoutContext
        let totalSamples: Int
        let validSamples: Int
        let gapAnnotations: [IntervalAnnotation]

        /// Production Calories (Keytel 2005, Mifflin-St Jeor, 40 % HRR, 30 s gap cap).
        let production: ModelResult

        /// Recovered WhoopRecoveredCalories (HB Harris-Benedict, 30 % HRR, 3 s cap).
        let recovered: ModelResult

        /// Non-nil only when the HR path produced no covered intervals and
        /// the workout had measurable cadence (Tudor-Locke MET fallback).
        let cadenceFallbackKcal: Double?

        /// Recovered net minus production active; distinct model coverage may differ.
        /// Positive = recovered estimates more above-resting energy.
        /// Nil when either model failed.
        var activeKcalDelta: Double? {
            guard let p = production.activeKcal, let r = recovered.reportedNetAboveRestingKcal else { return nil }
            return r - p
        }

        var longGapCount: Int { gapAnnotations.filter { $0.kind == .longGap }.count }
        var shortGapCount: Int { gapAnnotations.filter { $0.kind == .shortGap }.count }
        var duplicateCount: Int { gapAnnotations.filter { $0.kind == .duplicate }.count }

        /// Single-line summary for diagnostic logs.
        var summaryLine: String {
            let p = production.activeKcal.map { String(format: "%.1f", $0) } ?? "—"
            let r = recovered.reportedNetAboveRestingKcal.map { String(format: "%.1f", $0) } ?? "—"
            let d = activeKcalDelta.map { String(format: "%+.1f", $0) } ?? "—"
            return "[\(context.kind.rawValue)] prod=\(p) rec=\(r) delta=\(d) kcal" +
                   " samples=\(validSamples)/\(totalSamples)" +
                   " gaps(long=\(longGapCount) short=\(shortGapCount) dup=\(duplicateCount))"
        }
    }

    struct ModelResult: Codable, Equatable {
        let name: String
        /// Total energy including resting metabolic rate for covered seconds.
        let grossKcal: Double?
        /// Production active estimate; nil for recovered (export semantics unverified).
        let activeKcal: Double?
        /// Resting energy for covered window (BMR × coveredSeconds).
        let restingKcalForWindow: Double?
        let coveredSeconds: Double
        let excludedIntervals: Int
        /// Non-nil when the model could not produce a result.
        let failureReason: String?
        var segments: [SegmentEnergy] = []
        // Signed mathematical difference, not verified WHOOP active-energy semantics.
        var netAboveRestingKcal: Double? {
            guard let grossKcal, let restingKcalForWindow else { return nil }
            return grossKcal - restingKcalForWindow
        }
        // Explicitly encode net as a separate field in reports.
        var reportedNetAboveRestingKcal: Double? = nil
    }

    // MARK: - Main entry point

    /// Run a shadow comparison on the same timestamped HR samples.
    ///
    /// - Parameters:
    ///   - samples: HR observations in arrival order, with optional invalid HR and break markers.
    ///   - context: Workout metadata and body profile.
    ///   - tailPolicy: Tail handling for the recovered engine. `.observedIntervalsOnly`
    ///                 is the conservative default; the binary count predicate for
    ///                 `.repeatFinalInterval` remains unresolved.
    ///
    /// This function has **no** production call site. Call it only from
    /// diagnostics / test harnesses.
    static func compare(
        samples: [HRSample],
        context: WorkoutContext,
        tailPolicy: WhoopRecoveredCalories.TailPolicy = .observedIntervalsOnly
    ) -> CalorieShadowReport {

        // Keep arrival order: never sort a replayed/clock-reversed observation into invented coverage.
        let sorted = samples.filter { $0.time.isFinite && $0.time >= Double(context.startUnix) && $0.time <= Double(context.endUnix) }
        let monotonic = zip(sorted, sorted.dropFirst()).allSatisfy { $0.0.time <= $0.1.time }
        let gaps = annotateGaps(sorted)
        guard monotonic else {
            return CalorieShadowReport(context: context, totalSamples: samples.count, validSamples: 0,
                gapAnnotations: gaps, production: failed(name: "production", reason: "out-of-order observations"),
                recovered: failed(name: "recovered", reason: "out-of-order observations"), cadenceFallbackKcal: nil)
        }
        let totalSamples = samples.count
        let validSamples = sorted.filter {
            guard let bpm = $0.bpm else { return false }
            return bpm.isFinite && (35...220).contains(bpm)
        }.count

        let normalized = normalizeDuplicates(sorted)
        let prodResult = runProduction(sorted: normalized, context: context)
        let recResult = runRecovered(sorted: normalized, context: context, tailPolicy: tailPolicy)

        // Cadence fallback only fires when the HR path produced zero covered seconds.
        let cadenceFallback: Double?
        if prodResult.coveredSeconds > 0 && (prodResult.activeKcal ?? 0) > 0 {
            cadenceFallback = nil
        } else {
            cadenceFallback = computeCadenceFallback(context: context)
        }

        return CalorieShadowReport(
            context: context,
            totalSamples: totalSamples,
            validSamples: validSamples,
            gapAnnotations: gaps,
            production: prodResult,
            recovered: recResult,
            cadenceFallbackKcal: cadenceFallback
        )
    }

    /// Convenience builder from V18Sample records for a detected activity window.
    ///
    /// Pass the samples already trimmed to `session.startUnix...session.endUnix`.
    /// Duplicate-timestamp semantics: `ActivityDetect.detect` pre-deduplicates by
    /// quality before calling this, but raw duplicate entries are safely annotated
    /// as `.duplicate` intervals without crashing.
    static func compare(
        activitySamples: [V18Sample],
        session: ActivitySession,
        restingHR: Double,
        maxHR: Double,
        profile: BodyProfile,
        tailPolicy: WhoopRecoveredCalories.TailPolicy = .observedIntervalsOnly
    ) -> CalorieShadowReport {

        let hrSamples: [HRSample] = activitySamples.map { s in
            let plausible = s.wearing && (35...220).contains(s.heartRate)
            return HRSample(unix: s.unix, bpm: plausible ? Double(s.heartRate) : nil)
        }
        let kind: WorkoutKind
        switch session.kind {
        case "run":     kind = .run
        case "walk":    kind = .walk
        case "workout": kind = .strength
        case "cardio":  kind = .cardio
        default:        kind = .unknown
        }
        let context = WorkoutContext(
            kind: kind,
            startUnix: session.startUnix,
            endUnix: session.endUnix,
            steps: session.steps,
            restingHR: restingHR,
            maxHR: maxHR,
            profile: profile
        )
        return compare(samples: hrSamples, context: context, tailPolicy: tailPolicy)
    }

    // MARK: - Internal: Production (Keytel/Mifflin, 40 % HRR, 30 s cap)

    private static func runProduction(sorted: [HRSample], context: WorkoutContext) -> ModelResult {
        let p = context.profile

        guard let bmr = Calories.bmrKcalPerDay(
            weightKg: p.weightKg, heightCm: p.heightCm, age: p.age, sex: p.sex
        ) else {
            return failed(name: "production", reason: "invalid profile for Mifflin-St Jeor")
        }
        guard let gate = Calories.gateHR(restingHR: context.restingHR, maxHR: context.maxHR) else {
            return failed(name: "production", reason: "invalid HR anchors for 40% HRR gate")
        }

        var activeKcal = 0.0
        var coveredS = 0.0
        var excluded = 0
        let basalPerS = bmr / 86400
        for (curr, next) in zip(sorted, sorted.dropFirst()) {
            let gap = next.time - curr.time
            guard curr.segment == next.segment, gap > 0, gap <= 30,
                  let hr = validBPM(curr.bpm), validBPM(next.bpm) != nil else {
                excluded += 1; continue
            }
            let rate = Calories.keytelKcalPerS(hr: hr, maxHR: context.maxHR,
                weightKg: p.weightKg, age: p.age, sex: p.sex)
            activeKcal += hr >= gate ? max(0, rate - basalPerS) * gap : 0
            coveredS += gap
        }
        guard coveredS > 0 else { return failed(name: "production", reason: "no covered intervals") }
        let basal = basalPerS * coveredS
        return ModelResult(name: "production", grossKcal: basal + activeKcal,
            activeKcal: activeKcal, restingKcalForWindow: basal, coveredSeconds: coveredS,
            excludedIntervals: excluded, failureReason: nil, reportedNetAboveRestingKcal: activeKcal)
    }

    // MARK: - Internal: Recovered (HB, 30 % HRR, 3 s cap)

    private static func runRecovered(
        sorted: [HRSample],
        context: WorkoutContext,
        tailPolicy: WhoopRecoveredCalories.TailPolicy
    ) -> ModelResult {

        let p = context.profile
        guard let baseline = WhoopRecoveredCalories.Baseline(rawValue: p.recoveredBaseline) else {
            return failed(name: "recovered", reason: "unknown baseline code")
        }
        return runRecoveredWith(baseline: baseline, sorted: sorted,
                               context: context, tailPolicy: tailPolicy)
    }

    private static func runRecoveredWith(
        baseline: WhoopRecoveredCalories.Baseline,
        sorted: [HRSample],
        context: WorkoutContext,
        tailPolicy: WhoopRecoveredCalories.TailPolicy
    ) -> ModelResult {
        let p = context.profile
        let recProfile = WhoopRecoveredCalories.Profile(
            weightKg: p.weightKg,
            heightMeters: p.heightCm / 100.0,
            ageYears: p.age,
            baseline: baseline
        )

        guard !sorted.isEmpty else {
            return failed(name: "recovered", reason: "empty HR stream")
        }
        guard let refRate = try? WhoopRecoveredCalories.workoutKcalPerSecond(
            hr: context.maxHR, maxHR: context.maxHR, profile: recProfile
        ) else {
            return failed(name: "recovered", reason: "invalid reference rate at maxHR")
        }

        // Split on explicit pause/disconnect/invalid-reading markers. An unmarked
        // gap is capped by the recovered calculator itself, not silently discarded.
        var hrStream: [Double?] = []
        var tsStream: [Double?] = []
        var previousSegment: Int?
        for sample in sorted {
            if let previousSegment, sample.segment != previousSegment {
                hrStream.append(nil); tsStream.append(nil)
            }
            hrStream.append(validBPM(sample.bpm)); tsStream.append(sample.time)
            previousSegment = sample.segment
        }
        do {
            let r = try WhoopRecoveredCalories.integrate(
                heartRates: hrStream, timestamps: tsStream, profile: recProfile,
                restingHR: context.restingHR, maxHR: context.maxHR,
                referenceRate: refRate, tailPolicy: tailPolicy)
            return ModelResult(name: "recovered", grossKcal: r.integratedKcal,
                activeKcal: nil, restingKcalForWindow: r.restingKcalForCoveredSeconds,
                coveredSeconds: r.coveredSeconds, excludedIntervals: r.excludedIntervals,
                failureReason: nil, reportedNetAboveRestingKcal: r.netAboveRestingKcal)
        } catch {
            return failed(name: "recovered", reason: String(describing: error))
        }
    }

    private static func validBPM(_ bpm: Double?) -> Double? {
        guard let bpm, bpm.isFinite, (35...220).contains(bpm) else { return nil }
        return bpm
    }

    private static func normalizeDuplicates(_ samples: [HRSample]) -> [HRSample] {
        var result: [HRSample] = []
        for sample in samples {
            if let previous = result.last, previous.time == sample.time {
                // Conflicting observations become a break, not an arbitrary HR choice.
                if previous.segment != sample.segment || validBPM(previous.bpm) != validBPM(sample.bpm) {
                    result[result.count - 1] = HRSample(unix: sample.unix, bpm: nil,
                        preciseUnix: sample.preciseUnix, segment: sample.segment)
                }
            } else { result.append(sample) }
        }
        return result
    }

    // MARK: - Internal: Cadence fallback (Tudor-Locke MET)

    /// Production sessionActiveKcal cadence/MET path. Only invoked when the
    /// timestamped HR path has zero covered seconds (HR permanently below gate,
    /// or all samples missing).
    private static func computeCadenceFallback(context: WorkoutContext) -> Double? {
        guard context.kind == .walk, context.steps > 0 else { return nil }
        let p = context.profile
        let durationMin = (context.activeSeconds ?? (Double(context.endUnix) - Double(context.startUnix))) / 60
        guard durationMin > 0 else { return nil }
        return Calories.sessionActiveKcal(
            meanHR: nil,
            steps: context.steps,
            minutes: durationMin,
            restingHR: context.restingHR,
            maxHR: context.maxHR,
            weightKg: p.weightKg,
            heightCm: p.heightCm,
            age: p.age,
            sex: p.sex
        )
    }

    // MARK: - Internal: Gap annotation

    private static func annotateGaps(_ sorted: [HRSample]) -> [IntervalAnnotation] {
        guard sorted.count > 1 else { return [] }
        return (0..<(sorted.count - 1)).map { i in
            let elapsed = sorted[i + 1].time - sorted[i].time
            let gap = Int(min(Double(Int32.max), max(-Double(Int32.max), elapsed.rounded(.up))))
            let kind: IntervalAnnotation.Kind
            switch gap {
            case 0:         kind = .duplicate
            case 1...3:     kind = .normal
            case 4...30:    kind = .shortGap
            default:        kind = .longGap
            }
            return IntervalAnnotation(
                startUnix: sorted[i].unix, endUnix: sorted[i + 1].unix,
                gapSeconds: gap, kind: kind
            )
        }
    }

    // MARK: - Helpers

    private static func failed(name: String, reason: String) -> ModelResult {
        ModelResult(name: name, grossKcal: nil, activeKcal: nil,
                    restingKcalForWindow: nil, coveredSeconds: 0,
                    excludedIntervals: 0, failureReason: reason)
    }
}

// MARK: - JSON export

extension CalorieShadowValidator.CalorieShadowReport {
    /// Compact JSON string for embedding in workout diagnostics exports.
    func jsonString() -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
}


/// Private diagnostic evidence only; never read by any score or history writer.
struct WorkoutCalorieShadowCapture {
    typealias Validator = CalorieShadowValidator
    struct Anchors: Codable, Equatable {
        let profile: Validator.BodyProfile
        let restingHR: Double
        let maxHR: Double
    }
    struct Evidence: Codable {
        let schema: Int
        let workoutID: UUID
        let activityKind: String
        let startedAt: Date
        let endedAt: Date
        let activeSeconds: Int
        let pauses: [WorkoutExportPause]
        let samples: [Validator.HRSample]
        let savedActiveKcal: Int?
        let anchors: Anchors?
        let report: Validator.CalorieShadowReport?
        let status: String
        let provenance: String
    }
    private(set) var samples: [Validator.HRSample] = []
    private var segment = 0
    private var anchors: Anchors?
    private var observedAnchors = false
    private var changed = false
    private var truncated = false

    mutating func interrupt() { segment += 1 }
    mutating func append(hr: Int, at: Date, anchors: Anchors?) {
        let time = at.timeIntervalSince1970
        guard time.isFinite, abs(time) < 4_000_000_000, (35...220).contains(hr) else {
            interrupt(); return
        }
        guard samples.count < 100_000 else { truncated = true; return }
        if observedAnchors { if self.anchors != anchors { changed = true } }
        else { self.anchors = anchors; observedAnchors = true }
        samples.append(.init(unix: Int(time.rounded(.down)), bpm: Double(hr),
                             preciseUnix: time, segment: segment))
    }

    static func kind(_ activity: String) -> Validator.WorkoutKind {
        switch ActivityKind(rawValue: activity) {
        case .run, .outdoorRun, .trailRun, .intervalRun: return .run
        case .treadmill, .indoorRun: return .treadmill
        case .walk, .indoorWalk, .dogWalking, .strollerWalking: return .walk
        case .lift, .strengthTraining, .weightlifting, .powerlifting, .calisthenics: return .strength
        case .cardio: return .cardio
        default: return .unknown
        }
    }

    func evidence(for session: WorkoutSession) -> Evidence? {
        guard session.phase == .saved, let end = session.endedAt, end > session.startedAt,
              !samples.isEmpty else { return nil }
        let startUnix = session.startedAt.timeIntervalSince1970, endUnix = end.timeIntervalSince1970
        guard startUnix.isFinite, endUnix.isFinite, abs(startUnix) < 4_000_000_000,
              abs(endUnix) < 4_000_000_000 else { return nil }
        let report: Validator.CalorieShadowReport?
        let status: String
        if changed || truncated {
            report = nil; status = changed ? "profile or HR anchors changed during workout" : "sample limit reached"
        } else if let anchors {
            let valid = samples.filter { (startUnix...endUnix).contains($0.time) }
            let context = Validator.WorkoutContext(kind: Self.kind(session.activityKind),
                startUnix: Int(startUnix.rounded(.down)), endUnix: Int(endUnix.rounded(.up)),
                steps: 0, restingHR: anchors.restingHR, maxHR: anchors.maxHR, profile: anchors.profile,
                activeSeconds: Double(session.metrics.elapsedSeconds))
            report = Validator.compare(samples: valid, context: context)
            status = valid.count == samples.count ? "observed receipt timestamps; reference not matched" :
                "out-of-window samples excluded; reference not matched"
        } else {
            report = nil; status = "missing contemporaneous profile or HR anchors"
        }
        return Evidence(schema: 1, workoutID: session.id, activityKind: session.activityKind,
            startedAt: session.startedAt, endedAt: end, activeSeconds: session.metrics.elapsedSeconds,
            pauses: session.exportPauses ?? [], samples: samples, savedActiveKcal: session.metrics.calories,
            anchors: anchors, report: report, status: status,
            provenance: "Local receipt timestamps, not beat waveform. Baseline mapped by profile sex as research assumption; reference rate at maxHR experimental. Recovered net is not verified active energy. Recorded sessions lack a measured step total; no invented cadence. Existing production fallback unchanged.")
    }

    static func directory(support: URL) -> URL {
        support.appendingPathComponent("calorie-shadow", isDirectory: true)
    }

    static func write(_ evidence: Evidence, support: URL) throws {
        let root = directory(support: support)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(evidence).write(to: root.appendingPathComponent(evidence.workoutID.uuidString + ".json"),
                                            options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    static func remove(id: UUID, support: URL) {
        try? FileManager.default.removeItem(at: directory(support: support).appendingPathComponent(id.uuidString + ".json"))
    }
}
