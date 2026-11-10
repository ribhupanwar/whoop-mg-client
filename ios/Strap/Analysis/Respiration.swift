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
        for segment in segments {
            guard segment.count >= minBeats else { continue }
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
            rates.append(contentsOf: windowRates(detrended))
        }

        guard !rates.isEmpty else {
            return RespRate(
                breathsPerMinute: nil,
                reason: "no usable RSA peak train — needs a continuous still or sleep R-R window",
                beats: totalBeats,
                windows: 0
            )
        }
        let median = Stats.median(rates)
        guard median >= plausibleMinBPM && median <= plausibleMaxBPM else {
            return RespRate(
                breathsPerMinute: nil,
                reason: String(
                    format: "RSA estimate %.1f/min fell outside the plausible %.0f-%.0f band",
                    median, plausibleMinBPM, plausibleMaxBPM
                ),
                beats: totalBeats,
                windows: rates.count
            )
        }
        return RespRate(
            breathsPerMinute: Stats.rounded(median, 1),
            reason: nil,
            beats: totalBeats,
            windows: rates.count
        )
    }

    // MARK: - Beat train

    /// Split the beat stream wherever R-R is missing or the record clock jumps.
    /// Stitching across a dropout puts a step into the tachogram that the peak
    /// picker would read as a breath, so only short gaps are tolerated.
    static func beatSegments(_ samples: [V18Sample]) -> [[(unix: Int, rr: Int)]] {
        let ordered = samples.sorted { $0.unix < $1.unix }
        var segments: [[(unix: Int, rr: Int)]] = []
        var current: [(unix: Int, rr: Int)] = []
        var lastUnix: Int?
        var lastSpanS = 0.0
        for sample in ordered {
            let rr = sample.rrIntervalsMS.filter {
                $0 >= V18Decoder.minRRMS && $0 <= V18Decoder.maxRRMS
            }
            guard !rr.isEmpty else { continue }
            if let lastUnix, Double(sample.unix - lastUnix) - lastSpanS > gapToleranceS {
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
            guard window.count >= minDistance * 3 else { continue }
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
}
