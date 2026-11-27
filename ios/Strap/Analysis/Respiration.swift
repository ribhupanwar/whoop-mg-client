import Foundation

/// Respiratory-rate estimate from R-R via respiratory sinus arrhythmia, ported
/// from `whoop/health.py`. The gen5 v18 wire carries no respiration ADC: the
/// only signal is how beat-to-beat timing modulates with breathing. This is an
/// on-device estimate, not a chest-band measurement.
enum Respiration {
    static let resampleHz = 4.0
    static let detrendWindowS = 8.0
    static let minPeakDistanceS = 2.5
    static let windowS = 300.0
    static let gapToleranceS = 3.0
    static let minBreathIntervalS = 2.5   // 24 breaths/min
    static let maxBreathIntervalS = 10.0  // 6 breaths/min
    static let intervalBand = 0.4
    static let plausibleMinBPM = 8.0
    static let plausibleMaxBPM = 25.0
    static let minBeats = 30
    static let minimumBeatCoverage = 0.80
    static let rateAgreementRPM = 2.0

    static func estimate(_ samples: [V18Sample]) -> RespRate {
        let segments = beatSegments(samples)
        let totalBeats = segments.reduce(0) { $0 + $1.count }
        guard totalBeats >= minBeats else {
            return RespRate(
                breathsPerMinute: nil,
                reason: "needs at least \(minBeats) R-R beats from a still or sleep window",
                beats: totalBeats,
                windows: 0
            )
        }

        var rates: [Double] = []
        var spectralRates: [Double] = []
        var overcountedSegments = 0
        var undercoveredSegments = 0
        for segment in segments {
            guard segment.count >= minBeats,
                  let first = segment.first, let last = segment.last else { continue }
            let span = Double(last.unix - first.unix + 1)
            let beatSeconds = segment.reduce(0.0) { $0 + Double($1.rr) } / 1000
            // Duplicated/interleaved beats stretch the synthetic RSA time axis.
            // Use the same upper bound as nightly HRV, not a new physiological threshold.
            guard beatSeconds <= span * 1.05 else {
                overcountedSegments += 1
                continue
            }
            // Cumulative RR reconstructs time only when the observed beat duration
            // substantially covers the wall clock. Otherwise it compresses gaps.
            guard beatSeconds >= span * minimumBeatCoverage else {
                undercoveredSegments += 1
                continue
            }
            var times: [Double] = []
            var elapsed = 0.0
            for beat in segment {
                elapsed += Double(beat.rr) / 1000.0
                times.append(elapsed)
            }
            guard let last = times.last, last >= windowS / 2.0 else { continue }
            let grid = resampleBeatTimes(times, values: segment.map { $0.rr })
            guard grid.count >= 8 else { continue }
            let detrended = detrend(grid)
            guard Stats.populationStdev(detrended) > 1e-9 else { continue }
            let medianRRSec = Stats.median(segment.map { Double($0.rr) / 1000.0 })
            spectralRates.append(contentsOf: spectralWindowRates(detrended, medianRRSeconds: medianRRSec))
            rates.append(contentsOf: windowRates(detrended))
        }

        // A plausible time-domain peak train alone can be a harmonic or noise.
        // Use the spectral candidate, and corroborate thin spectral evidence.
        let activeRates = spectralRates
        if !activeRates.isEmpty {
            let center = Stats.median(activeRates)
            let agreeing = activeRates.filter { abs($0 - center) <= rateAgreementRPM }.count
            let corroborated = !rates.isEmpty && abs(Stats.median(rates) - center) <= rateAgreementRPM
            guard agreeing * 2 >= activeRates.count,
                  activeRates.count >= 3 || corroborated else {
                return RespRate(breathsPerMinute: nil, reason: "RSA windows disagree or lack independent peak-train corroboration",
                                beats: totalBeats, windows: activeRates.count)
            }
        }
        guard !activeRates.isEmpty else {
            return RespRate(
                breathsPerMinute: nil,
                reason: overcountedSegments > 0
                    ? "no usable RSA peak train — RR beat duration exceeded elapsed recording time"
                    : (undercoveredSegments > 0
                        ? "no usable RSA peak train — insufficient RR beat-time coverage"
                        : "no usable RSA peak train — needs a continuous still or sleep R-R window"),
                beats: totalBeats,
                windows: 0
            )
        }
        let median = Stats.median(activeRates)
        guard median >= plausibleMinBPM && median <= plausibleMaxBPM else {
            return RespRate(
                breathsPerMinute: nil,
                reason: String(
                    format: "RSA estimate %.1f/min fell outside the plausible %.0f-%.0f band",
                    median, plausibleMinBPM, plausibleMaxBPM
                ),
                beats: totalBeats,
                windows: activeRates.count
            )
        }
        return RespRate(
            breathsPerMinute: Stats.rounded(median, 1),
            reason: nil,
            beats: totalBeats,
            windows: activeRates.count
        )
    }

    // MARK: - Beat train

    /// Split the beat stream wherever R-R is missing or the record clock jumps.
    /// Stitching across a dropout puts a step into the tachogram that the peak
    /// picker would read as a breath, so only short gaps are tolerated.
    static func beatSegments(_ samples: [V18Sample]) -> [[(unix: Int, rr: Int)]] {
        // Keep every record in clock order. Filtering to only still records
        // before segmentation hides motion/missing-RR gaps and can stitch
        // unrelated beats into a false respiration peak train.
        // Offload/reconnect may replay a timestamp. Keep the most complete
        // second rather than letting duplicates break an otherwise valid
        // continuous breathing window or double-count R-R beats.
        var uniqueBySecond: [Int: V18Sample] = [:]
        for sample in samples {
            if let previous = uniqueBySecond[sample.unix],
               !Hrv.preferRetransmittedRR(sample.rrIntervalsMS, over: previous.rrIntervalsMS) {
                continue
            }
            uniqueBySecond[sample.unix] = sample
        }
        let ordered = uniqueBySecond.values.sorted { $0.unix < $1.unix }
        var segments: [[(unix: Int, rr: Int)]] = []
        var current: [(unix: Int, rr: Int)] = []
        var lastUnix: Int?
        var lastSpanS = 0.0
        for sample in ordered {
            guard sample.wearing,
                  let motion = sample.dynamicAccelG,
                  motion.isFinite, (0...0.10).contains(motion) else {
                if !current.isEmpty { segments.append(current); current = [] }
                lastUnix = nil
                lastSpanS = 0
                continue
            }
            let rr = sample.rrIntervalsMS.filter {
                $0 >= V18Decoder.minRRMS && $0 <= V18Decoder.maxRRMS
            }
            // A missing RR second must break the train: otherwise a dropout
            // can be mistaken for an uninterrupted breathing modulation.
            guard !rr.isEmpty else {
                if !current.isEmpty { segments.append(current); current = [] }
                lastUnix = nil
                lastSpanS = 0
                continue
            }
            if let lastUnix, (sample.unix <= lastUnix ||
                Double(sample.unix - lastUnix) - lastSpanS > gapToleranceS) {
                if !current.isEmpty { segments.append(current) }
                current = []
            }
            for value in rr { current.append((unix: sample.unix, rr: value)) }
            lastUnix = sample.unix
            lastSpanS = rr.reduce(0.0) { $0 + Double($1) } / 1000.0
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    static func resampleBeatTimes(_ times: [Double], values: [Int]) -> [Double] {
        let dt = 1.0 / resampleHz
        let count = Int(times[times.count - 1] / dt) + 1
        var grid: [Double] = []
        grid.reserveCapacity(count)
        var segment = 0
        for index in 0..<count {
            let time = Double(index) * dt
            while segment < times.count - 2 && times[segment + 1] < time { segment += 1 }
            let t0 = times[segment]
            let t1 = times[segment + 1]
            let v0 = Double(values[segment])
            let v1 = Double(values[segment + 1])
            if t1 <= t0 {
                grid.append(v0)
            } else {
                let fraction = min(max((time - t0) / (t1 - t0), 0.0), 1.0)
                grid.append(v0 + fraction * (v1 - v0))
            }
        }
        return grid
    }

    static func detrend(_ values: [Double]) -> [Double] {
        let half = max(1, Int((detrendWindowS * resampleHz / 2.0).rounded()))
        var output: [Double] = []
        output.reserveCapacity(values.count)
        for index in 0..<values.count {
            let low = max(0, index - half)
            let high = min(values.count - 1, index + half)
            let window = values[low...high]
            output.append(values[index] - window.reduce(0.0, +) / Double(window.count))
        }
        return output
    }

    /// Local maxima above zero, thinned greedily by height like scipy's picker.
    static func findPeaks(_ values: [Double], minDistance: Int) -> [Int] {
        guard values.count >= 3 else { return [] }
        let candidates = (1..<(values.count - 1)).filter {
            values[$0] > 0 && values[$0] > values[$0 - 1] && values[$0] >= values[$0 + 1]
        }
        guard !candidates.isEmpty else { return [] }
        let ordered = candidates.sorted {
            values[$0] != values[$1] ? values[$0] > values[$1] : $0 < $1
        }
        var kept: [Int] = []
        for index in ordered where kept.allSatisfy({ abs(index - $0) >= minDistance }) {
            kept.append(index)
        }
        return kept.sorted()
    }

    static func windowRates(_ detrended: [Double]) -> [Double] {
        let minDistance = max(2, Int((minPeakDistanceS * resampleHz).rounded()))
        let windowSamples = max(minDistance * 3, Int((windowS * resampleHz).rounded()))
        let dt = 1.0 / resampleHz
        var rates: [Double] = []
        var start = 0
        while start < detrended.count {
            let end = min(start + windowSamples, detrended.count)
            let window = Array(detrended[start..<end])
            start += windowSamples
            // A short trailing fragment can contain three accidental peaks and yield
            // a plausible but unsupported nightly breathing rate. Require at
            // least half of the intended 5-minute window before estimating.
            guard window.count >= Int(windowS * resampleHz / 2.0) else { continue }
            let peaks = findPeaks(window, minDistance: minDistance)
            guard peaks.count >= 3 else { continue }
            var intervals = (1..<peaks.count).map {
                Double(peaks[$0] - peaks[$0 - 1]) * dt
            }
            intervals = intervals.filter {
                $0 >= minBreathIntervalS && $0 <= maxBreathIntervalS
            }
            guard intervals.count >= 2 else { continue }
            let median = Stats.median(intervals)
            guard median > 0 else { continue }
            let anchored = intervals.filter { abs($0 - median) <= intervalBand * median }
            let meanInterval = anchored.isEmpty ? median : Stats.mean(anchored)
            if meanInterval > 0 { rates.append(60.0 / meanInterval) }
        }
        return rates
    }

    /// Hann-windowed spectral RSA peak estimator over the 0.15–0.40 Hz HF band
    /// (Nyquist-bounded by `0.5 / medianRRSeconds`) with SNR >= 2.0 gating.
    /// Avoids the high-frequency jitter bias of time-domain peak picking.
    static func spectralWindowRates(_ detrended: [Double], medianRRSeconds: Double) -> [Double] {
        let ceilingHz = medianRRSeconds > 0 ? min(0.40, 0.5 / medianRRSeconds) : 0.40
        guard ceilingHz > 0.16 else { return [] }
        let windowSamples = Int((windowS * resampleHz).rounded())
        let minSamples = Int((windowS * resampleHz / 2.0).rounded())
        var rates: [Double] = []
        var start = 0
        while start < detrended.count {
            let end = min(start + windowSamples, detrended.count)
            let n = end - start
            start += windowSamples
            guard n >= minSamples else { continue }
            var windowed = [Double](repeating: 0, count: n)
            let denom = Double(max(1, n - 1))
            for i in 0..<n {
                let hann = 0.5 * (1.0 - cos(2.0 * .pi * Double(i) / denom))
                windowed[i] = detrended[start - windowSamples + i] * hann
            }
            var bestPower = -1.0
            var bestFreq = 0.0
            var totalPower = 0.0
            var bins = 0
            var freq = 0.05
            while freq <= ceilingHz + 1e-6 {
                // Goertzel algorithm: 1 cos + 1 sin per frequency bin instead of 2*N trig calls.
                let omega = 2.0 * .pi * freq / resampleHz
                let cosW = cos(omega)
                let sinW = sin(omega)
                let coeff = 2.0 * cosW
                var s1 = 0.0
                var s2 = 0.0
                for i in 0..<n {
                    let s0 = windowed[i] + coeff * s1 - s2
                    s2 = s1
                    s1 = s0
                }
                let re = s1 - s2 * cosW
                let im = s2 * sinW
                let power = re * re + im * im
                totalPower += power
                bins += 1
                if power > bestPower {
                    bestPower = power
                    bestFreq = freq
                }
                freq += 0.005
            }
            let meanPower = bins > 0 ? totalPower / Double(bins) : 0.0
            if meanPower > 0, (bestPower / meanPower) >= 2.0,
               bestFreq >= 0.133, bestFreq <= 0.417,
               bestFreq + 0.005 <= ceilingHz + 1e-6 {
                rates.append(bestFreq * 60.0)
            }
        }
        return rates
    }
}
