import Foundation

/// Baseline-relative recovery and stress scores plus the band's SpO2 candidate
/// summary, ported from `whoop/health.py`. None of these are WHOOP scores, and
/// a missing baseline produces no number instead of a fabricated one.
enum Recovery {
    static let minBaselineDays = 7
    static let hrvWeight = 0.5
    static let rhrWeight = 0.2
    static let sleepWeight = 0.3

    static let stressMax = 3.0
    static let stressElevatedSD = 1.0
    static let stressHighSD = 2.0

    /// Baseline-relative 0-100 recovery estimate.
    ///
    /// Higher HRV than your own norm and lower resting HR than your own norm
    /// both push the score up; sleep is scored against your stated need.
    /// Components are renormalised over whatever is available, and fewer than
    /// seven baseline days yields no score at all.
    static func score(
        lnRMSSD: Double?,
        rhr: Double?,
        sleepHours: Double?,
        sleepNeedHours: Double?,
        baseline: Baseline?
    ) -> RecoveryResult {
        guard let baseline, baseline.days >= minBaselineDays else {
            return RecoveryResult(
                score: nil,
                reason: "needs at least \(minBaselineDays) days of baseline",
                hrvComponent: nil, rhrComponent: nil, sleepComponent: nil
            )
        }
        guard let lnRMSSD, let rhr else {
            return RecoveryResult(
                score: nil,
                reason: "needs HRV and resting HR from a rest/sleep window",
                hrvComponent: nil, rhrComponent: nil, sleepComponent: nil
            )
        }

        let hrvZ = baseline.lnRMSSDSD > 0
            ? (lnRMSSD - baseline.lnRMSSDMean) / baseline.lnRMSSDSD
            : 0.0
        let rhrZ = baseline.rhrSD > 0
            ? -(rhr - baseline.rhrMean) / baseline.rhrSD
            : 0.0
        let hrvComponent = logistic(hrvZ)
        let rhrComponent = logistic(rhrZ)

        var weighted = hrvComponent * hrvWeight + rhrComponent * rhrWeight
        var weight = hrvWeight + rhrWeight
        var sleepComponent: Double?
        if let sleepHours, let sleepNeedHours, sleepNeedHours > 0 {
            let sleep = 100.0 * min(sleepHours / sleepNeedHours, 1.0)
            sleepComponent = sleep
            weighted += sleep * sleepWeight
            weight += sleepWeight
        }
        let score = weighted / weight
        return RecoveryResult(
            score: Stats.rounded(score, 1),
            reason: nil,
            hrvComponent: Stats.rounded(hrvComponent, 1),
            rhrComponent: Stats.rounded(rhrComponent, 1),
            sleepComponent: sleepComponent.map { Stats.rounded($0, 1) }
        )
    }

    /// Standard deviations of lnRMSSD below the personal awake-quiet norm,
    /// clipped to 0-3. At or above the norm the index is 0 — HRV above normal
    /// is not "negative stress". The baseline MUST come from awake-quiet
    /// windows: exercise also collapses RMSSD, for metabolic rather than
    /// psychological reasons, so only verified-quiet HRV belongs here.
    static func stressIndex(lnRMSSD: Double?, baseline: Baseline?) -> StressResult {
        guard let baseline, baseline.days >= minBaselineDays else {
            return StressResult(
                index: nil,
                reason: "needs at least \(minBaselineDays) days of awake-quiet baseline"
            )
        }
        guard let lnRMSSD else {
            return StressResult(index: nil, reason: "needs HRV from a verified-quiet window")
        }
        guard baseline.lnRMSSDSD > 0 else {
            return StressResult(index: nil, reason: "baseline has no HRV variation to scale against")
        }
        let deviation = (baseline.lnRMSSDMean - lnRMSSD) / baseline.lnRMSSDSD
        return StressResult(
            index: Stats.rounded(max(0.0, min(stressMax, deviation)), 2),
            reason: nil
        )
    }

    /// Mean of the band's in-band SpO2 candidates, or no value at all.
    ///
    /// NOT a validated SpO2. The band banks one candidate byte per second only
    /// while it records sleep; 70-100 is the candidate range, bit-7 values are
    /// saturation sentinels, other nonzero values are diagnostic codes. It
    /// never feeds a score.
    static func spo2Summary(_ samples: [V18Sample]) -> Spo2Summary {
        let inBand = samples.compactMap { sample -> Double? in
            guard let pct = sample.spo2CandidatePct,
                  pct >= V18Decoder.spo2CandidateMin && pct <= V18Decoder.spo2CandidateMax
            else { return nil }
            return Double(pct)
        }
        let saturated = samples.filter { $0.spo2CandidateKind == .saturated }.count
        let diagnostic = samples.filter { $0.spo2CandidateKind == .diagnostic }.count
        guard !inBand.isEmpty else {
            return Spo2Summary(
                pct: nil,
                readings: 0,
                saturated: saturated,
                diagnostic: diagnostic,
                reason: "the strap banked no in-band (70-100) candidate — no SpO2 % is produced"
            )
        }
        return Spo2Summary(
            pct: Stats.rounded(Stats.mean(inBand), 1),
            readings: inBand.count,
            saturated: saturated,
            diagnostic: diagnostic,
            reason: nil
        )
    }

    static func logistic(_ z: Double) -> Double {
        100.0 / (1.0 + exp(-z))
    }
}
