import Foundation

/// Experimental, diagnostic-only alternatives. No production score or band
/// command depends on these. Thresholds are predeclared research choices,
/// not a reproduction of WHOOP or a verbatim OpenStrap implementation.
enum OpenStrapAdoptionResearch {
    struct RespiratoryWindow: Codable, Equatable {
        let startUnix: Int
        let endUnixExclusive: Int
        let beatCount: Int
        let beatSeconds: Double
        let rpm: Double?
        let explainedVariance: Double?
        let reason: String?
    }

    struct RespiratoryReport: Codable, Equatable {
        let timingSource: String
        let attemptedWindows: Int
        let agreeingWindows: Int
        let candidateRPM: Double?
        let windows: [RespiratoryWindow]
    }

    /// Native irregular-sample harmonic regression (floating-mean
    /// Lomb–Scargle family). RR times below are reconstructed, NOT verified
    /// device beat timestamps. Only use contiguous, duration-checked runs.
    static func spectralPeak(times: [Double], rrMS: [Double]) -> (rpm: Double, power: Double)? {
        guard times.count == rrMS.count, times.count >= 120,
              times.allSatisfy({ $0.isFinite }),
              rrMS.allSatisfy({ $0.isFinite && (300...2000).contains($0) }),
              zip(times.dropFirst(), times).allSatisfy({ $0.0 > $0.1 }),
              let first = times.first, let last = times.last, last - first >= 235 else { return nil }
        let n = Double(times.count)
        let mean = rrMS.reduce(0, +) / n
        let y = rrMS.map { $0 - mean }
        let total = y.reduce(0) { $0 + $1 * $1 }
        guard total > n else { return nil }
        let nyquist = min(0.5, 500.0 / Stats.median(rrMS))
        guard nyquist >= 0.4 else { return nil }
        let t = times.map { $0 - first }
        let step = 1.0 / 300.0
        let upper = Int(floor((nyquist - 0.15) / step))
        guard upper >= 6 else { return nil }
        var powers: [(hz: Double, power: Double)] = []
        for k in 0...upper {
            let hz = 0.15 + Double(k) * step
            let omega = 2 * Double.pi * hz
            var s = 0.0, c = 0.0, ss = 0.0, cc = 0.0, sc = 0.0, sy = 0.0, cy = 0.0
            for i in t.indices {
                let a = sin(omega * t[i]), b = cos(omega * t[i])
                s += a; c += b; ss += a*a; cc += b*b; sc += a*b
                sy += a*y[i]; cy += b*y[i]
            }
            ss -= s*s/n; cc -= c*c/n; sc -= s*c/n
            let determinant = ss*cc-sc*sc
            guard determinant > 1e-9 else { continue }
            let explained = (cc*sy*sy - 2*sc*sy*cy + ss*cy*cy) / determinant / total
            if explained.isFinite { powers.append((hz, max(0, min(1, explained)))) }
        }
        guard let best = powers.max(by: { $0.power < $1.power }),
              best.power >= 0.15, best.hz >= 0.15 + 2*step,
              best.hz <= nyquist - 2*step else { return nil }
        // Reject two similarly strong, separated peaks instead of choosing
        // whichever happens to lie on a marginally more favorable grid bin.
        if powers.contains(where: { abs($0.hz-best.hz) >= 0.03 && $0.power >= 0.9*best.power }) {
            return nil
        }
        return (best.hz * 60, best.power)
    }

    /// Diagnostic fixed-wall-clock windows. Missing windows are attempts,
    /// not silently removed from consensus. Reuse existing RR replay and
    /// motion segmentation, without changing that implementation.
    static func respiratoryReport(samples: [V18Sample], startUnix: Int, endUnix: Int) -> RespiratoryReport {
        let source = "cumulative RR within duration-checked contiguous segments; not native beat timestamps"
        guard startUnix >= 0, endUnix > startUnix, endUnix - startUnix <= 86400 else {
            return RespiratoryReport(timingSource: source, attemptedWindows: 0,
                                     agreeingWindows: 0, candidateRPM: nil, windows: [])
        }
        let runs = Respiration.beatSegments(samples.filter { startUnix <= $0.unix && $0.unix < endUnix })
        var windows: [RespiratoryWindow] = []
        for start in stride(from: startUnix, to: endUnix, by: 300) {
            let end = start + 300
            guard end <= endUnix else { break }
            let eligible = runs.map { $0.filter { start <= $0.unix && $0.unix < end } }.filter { !$0.isEmpty }
            let run = eligible.max(by: { $0.count < $1.count }) ?? []
            let duration = run.reduce(0.0) { $0 + Double($1.rr)/1000 }
            let span = run.first.flatMap { a in run.last.map { $0.unix - a.unix + 1 } } ?? 0
            var peak: (rpm: Double, power: Double)?
            if span >= 240, duration >= 240, duration <= Double(span)*1.05,
               duration >= Double(span)*0.8, run.allSatisfy({ (300...2000).contains($0.rr) }) {
                var elapsed = 0.0
                let times = run.map { beat -> Double in elapsed += Double(beat.rr)/1000; return elapsed }
                peak = spectralPeak(times: times, rrMS: run.map { Double($0.rr) })
            }
            windows.append(RespiratoryWindow(startUnix: start, endUnixExclusive: end,
                beatCount: run.count, beatSeconds: duration, rpm: peak?.rpm,
                explainedVariance: peak?.power, reason: peak == nil ? "insufficient contiguous coverage or unambiguous spectral evidence" : nil))
        }
        let rates = windows.compactMap { $0.rpm }
        let center = rates.isEmpty ? nil : Stats.median(rates)
        let agreeing = center.map { c in rates.filter { abs($0-c) <= 2 }.count } ?? 0
        let candidate = agreeing >= 3 && agreeing * 2 >= windows.count ? center : nil
        return RespiratoryReport(timingSource: source, attemptedWindows: windows.count,
            agreeingWindows: agreeing, candidateRPM: candidate, windows: windows)
    }

    struct StepCalibrationRun: Equatable {
        let deviceID: String
        let wearingLocation: String
        let sessionID: String
        let referenceCount: Int
        let rawBandCount: Int
    }

    /// Optional controlled, manually counted walk calibration. Does not
    /// change raw band counts, the daily ledger, or live workout estimates.
    static func stepCalibrationFactor(_ runs: [StepCalibrationRun],
                                      deviceID: String, wearingLocation: String) -> Double? {
        guard !deviceID.isEmpty, !wearingLocation.isEmpty else { return nil }
        let grouped = Dictionary(grouping: runs.filter {
            $0.deviceID == deviceID && $0.wearingLocation == wearingLocation
        }, by: { $0.sessionID })
        let usable = grouped.values.compactMap { group -> Double? in
            guard let row = group.first, !row.sessionID.isEmpty,
                  group.allSatisfy({ $0 == row }),
                  (200...10000).contains(row.referenceCount),
                  (100...20000).contains(row.rawBandCount) else { return nil }
            let ratio = Double(row.referenceCount)/Double(row.rawBandCount)
            return (0.5...2.0).contains(ratio) ? ratio : nil
        }
        guard usable.count >= 3 else { return nil }
        let center = Stats.median(usable)
        guard usable.allSatisfy({ abs($0-center) <= 0.10*center }) else { return nil }
        return (center*Double(usable.count)+3)/(Double(usable.count)+3)
    }

    struct Regularity: Codable, Equatable {
        let observedPairs: Int
        let agreementFraction: Double
        let index: Double
    }

    /// SRI-style paired-day comparison. Caller must supply consecutive
    /// 24-hour local-day arrays aligned to the same clock time and validated
    /// time-zone offset; skip DST transitions, missing/off-wrist epochs.
    /// nil is unknown; false is OBSERVED awake, never inferred from absence.
    static func regularity(previous: [Bool?], following: [Bool?]) -> Regularity? {
        guard previous.count == 2880, following.count == 2880 else { return nil }
        var observed = 0, agreement = 0
        for (a,b) in zip(previous, following) {
            guard let a, let b else { continue }
            observed += 1
            if a == b { agreement += 1 }
        }
        guard observed >= 2304 else { return nil }
        let fraction = Double(agreement)/Double(observed)
        return Regularity(observedPairs: observed, agreementFraction: fraction, index: 200*fraction-100)
    }
}
