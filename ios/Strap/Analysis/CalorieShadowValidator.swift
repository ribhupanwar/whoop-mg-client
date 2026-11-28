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
            /// Gap 4–30 s: production bills up to 30 s; recovered engine caps at 3 s and skips.
            case shortGap
            /// Gap > 30 s: both engines treat as BLE outage / pause — no energy billed.
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

        /// recovered.activeKcal − production.activeKcal.
        /// Positive = recovered estimates more above-resting energy.
        /// Nil when either model failed.
        var activeKcalDelta: Double? {
            guard let p = production.activeKcal, let r = recovered.activeKcal else { return nil }
            return r - p
        }

        var longGapCount: Int { gapAnnotations.filter { $0.kind == .longGap }.count }
        var shortGapCount: Int { gapAnnotations.filter { $0.kind == .shortGap }.count }
        var duplicateCount: Int { gapAnnotations.filter { $0.kind == .duplicate }.count }

        /// Single-line summary for diagnostic logs.
        var summaryLine: String {
            let p = production.activeKcal.map { String(format: "%.1f", $0) } ?? "—"
            let r = recovered.activeKcal.map { String(format: "%.1f", $0) } ?? "—"
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
        /// Energy above resting rate (or above Keytel gate for production).
        let activeKcal: Double?
        /// Resting energy for covered window (BMR × coveredSeconds).
        let restingKcalForWindow: Double?
        let coveredSeconds: Double
        let excludedIntervals: Int
        /// Non-nil when the model could not produce a result.
        let failureReason: String?
        var segments: [SegmentEnergy] = []
    }

    // MARK: - Main entry point

    /// Run a shadow comparison on the same timestamped HR samples.
    ///
    /// - Parameters:
    ///   - samples: HR observations. May contain nil bpm (BLE gaps), duplicates, and
    ///              out-of-order entries — these are sorted and annotated without crashing.
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

        let sorted = samples.sorted { $0.unix < $1.unix }
        let totalSamples = sorted.count
        let validSamples = sorted.filter {
            guard let bpm = $0.bpm else { return false }
            return bpm.isFinite && (35...220).contains(bpm)
        }.count

        let gaps = annotateGaps(sorted)
        let prodResult = runProduction(sorted: sorted, context: context)
        let recResult  = runRecovered(sorted: sorted, context: context, tailPolicy: tailPolicy)

        // Cadence fallback only fires when the HR path produced zero covered seconds.
        let cadenceFallback: Double?
        if (prodResult.coveredSeconds > 0) {
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

        let valid: [(unix: Int, bpm: Double)] = sorted.compactMap { s in
            guard let bpm = s.bpm, bpm.isFinite, (35...220).contains(bpm) else { return nil }
            return (s.unix, bpm)
        }

        var activeKcal = 0.0
        var grossKcal  = 0.0
        var coveredS   = 0.0
        var excluded   = 0
        var segments   = [SegmentEnergy]()
        let basalPerS  = bmr / 86400.0

        for i in 0..<(valid.count - 1) {
            let curr = valid[i], next = valid[i + 1]
            let gap = Double(next.unix - curr.unix)
            // Skip duplicate timestamps, missing gaps, and gaps > 30 s.
            guard gap > 0, gap <= 30.0,
                  next.bpm.isFinite, (35...220).contains(next.bpm) else {
                excluded += 1; continue
            }
            let keytelPerS = Calories.keytelKcalPerS(
                hr: curr.bpm, maxHR: context.maxHR,
                weightKg: p.weightKg, age: p.age, sex: p.sex
            )
            let segActive  = curr.bpm >= gate ? max(0, keytelPerS - basalPerS) * gap : 0.0
            let segGross   = keytelPerS * gap
            let segResting = basalPerS * gap
            activeKcal += segActive
            grossKcal  += segGross
            coveredS   += gap
            segments.append(SegmentEnergy(
                startUnix: curr.unix, endUnix: next.unix,
                coveredSeconds: gap, grossKcal: segGross,
                activeKcal: segActive, netAboveRestingKcal: segGross - segResting
            ))
        }
        if valid.isEmpty { excluded = sorted.count }

        let restingForCovered = basalPerS * coveredS
        return ModelResult(
            name: "production",
            grossKcal: coveredS > 0 ? grossKcal : nil,
            activeKcal: coveredS > 0 ? activeKcal : nil,
            restingKcalForWindow: coveredS > 0 ? restingForCovered : nil,
            coveredSeconds: coveredS,
            excludedIntervals: excluded,
            failureReason: coveredS > 0 ? nil : "no covered intervals",
            segments: segments
        )
    }

    // MARK: - Internal: Recovered (HB, 30 % HRR, 3 s cap)

    private static func runRecovered(
        sorted: [HRSample],
        context: WorkoutContext,
        tailPolicy: WhoopRecoveredCalories.TailPolicy
    ) -> ModelResult {

        let p = context.profile
        guard let baseline = WhoopRecoveredCalories.Baseline(rawValue: p.recoveredBaseline) else {
            // rawValue out of range: fall back to raw2Mean (mean of both formulae).
            return runRecoveredWith(baseline: .raw2Mean, sorted: sorted,
                                   context: context, tailPolicy: tailPolicy)
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

        let hrStream: [Double?] = sorted.map { $0.bpm }
        let tsStream: [Double?] = sorted.map { Double($0.unix) }

        do {
            let r = try WhoopRecoveredCalories.integrate(
                heartRates: hrStream,
                timestamps: tsStream,
                profile: recProfile,
                restingHR: context.restingHR,
                maxHR: context.maxHR,
                referenceRate: refRate,
                tailPolicy: tailPolicy
            )
            return ModelResult(
                name: "recovered",
                grossKcal: r.integratedKcal,
                activeKcal: r.netAboveRestingKcal,
                restingKcalForWindow: r.restingKcalForCoveredSeconds,
                coveredSeconds: r.coveredSeconds,
                excludedIntervals: r.excludedIntervals,
                failureReason: nil
            )
        } catch let e as WhoopRecoveredCalories.Failure {
            return failed(name: "recovered", reason: "\(e)")
        } catch {
            return failed(name: "recovered", reason: "unexpected: \(error)")
        }
    }

    // MARK: - Internal: Cadence fallback (Tudor-Locke MET)

    /// Production sessionActiveKcal cadence/MET path. Only invoked when the
    /// timestamped HR path has zero covered seconds (HR permanently below gate,
    /// or all samples missing).
    private static func computeCadenceFallback(context: WorkoutContext) -> Double? {
        guard context.steps > 0 else { return nil }
        let p = context.profile
        let durationMin = Double(context.endUnix - context.startUnix) / 60.0
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
            let gap = sorted[i + 1].unix - sorted[i].unix
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
