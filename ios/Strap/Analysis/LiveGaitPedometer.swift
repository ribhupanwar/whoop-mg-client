import Foundation

/// Swift adaptation of OpenStrap/analytics live gait-periodicity pedometer.
/// Upstream: lib/src/onehz/motion/steps.dart (AGPL-3.0).
/// This is an optional 50–100 Hz IMU cross-check, NOT a replacement for the
/// band's decoded historical step counter and NOT a 1 Hz step estimator.
enum LiveGaitPedometer {
    struct Result: Equatable {
        let steps: Int
        let durationSeconds: Double
        let cadenceSPM: Double
        let confidence: Double
    }

    private static func correlation(_ values: [Double], lag: Int) -> Double {
        guard lag > 0, lag < values.count else { return 0 }
        let n = values.count - lag
        var dot = 0.0, left = 0.0, right = 0.0
        for i in 0..<n {
            dot += values[i] * values[i + lag]
            left += values[i] * values[i]
            right += values[i + lag] * values[i + lag]
        }
        let denominator = sqrt(left * right)
        return denominator > 0 ? dot / denominator : 0
    }

    /// Takes raw accelerometer magnitude in g. A minimum 8-second contiguous
    /// gait run is required to reject isolated wrist motion.
    static func estimate(magnitude: [Double], sampleRateHz: Double) -> Result {
        guard sampleRateHz.isFinite, (20...200).contains(sampleRateHz),
              magnitude.count >= Int(sampleRateHz * 8),
              magnitude.allSatisfy({ $0.isFinite }) else {
            return Result(steps: 0, durationSeconds: 0, cadenceSPM: 0, confidence: 0)
        }
        // Block-average to approximately 50 Hz for predictable CPU usage.
        let block = max(1, Int((sampleRateHz / 50).rounded()))
        let fs = sampleRateHz / Double(block)
        var raw: [Double] = []
        for start in stride(from: 0, to: magnitude.count - block + 1, by: block) {
            raw.append(magnitude[start..<(start + block)].reduce(0, +) / Double(block))
        }
        func movingMean(_ count: Int) -> [Double] {
            var sum = 0.0
            var output = [Double](repeating: 0, count: raw.count)
            for i in raw.indices {
                sum += raw[i]
                if i >= count { sum -= raw[i - count] }
                output[i] = sum / Double(min(i + 1, count))
            }
            return output
        }
        let short = movingMean(max(1, Int(0.1 * fs)))
        let long = movingMean(max(1, Int(fs)))
        let filtered = zip(short, long).map { $0 - $1 }
        let window = Int(4 * fs)
        let hop = max(1, Int(fs))
        guard filtered.count >= window else {
            return Result(steps: 0, durationSeconds: Double(magnitude.count) / sampleRateHz,
                          cadenceSPM: 0, confidence: 0)
        }
        var run = 0, runSteps = 0.0, totalSteps = 0.0, regularity = 0.0
        var acceptedWindows = 0
        for start in stride(from: 0, through: filtered.count - window, by: hop) {
            let slice = Array(filtered[start..<(start + window)])
            let mean = slice.reduce(0, +) / Double(slice.count)
            let centered = slice.map { $0 - mean }
            let sd = sqrt(centered.reduce(0.0) { $0 + $1 * $1 } / Double(centered.count))
            let lo = max(2, Int(0.25 * fs))
            let hi = min(Int(1.6 * fs), centered.count - Int(0.5 * fs) - 1)
            var candidates: [(lag: Int, ac: Double)] = []
            if hi > lo + 2 {
                let ac = (lo - 1...hi + 1).map { correlation(centered, lag: $0) }
                for lag in lo...hi {
                    let idx = lag - lo + 1
                    if ac[idx] >= ac[idx - 1] && ac[idx] >= ac[idx + 1] {
                        candidates.append((lag, ac[idx]))
                    }
                }
            }
            let best = candidates.map(\.ac).max() ?? 0
            let chosen = candidates.first { $0.ac >= 0.8 * best }
            var stepSeconds: Double?
            var strideAC = 0.0
            if let chosen, best > 0 {
                let half = chosen.lag / 2
                let isStride = Double(chosen.lag) / fs >= 0.9 ||
                    (Double(half) / fs >= 0.25 && correlation(centered, lag: half) > -0.4)
                let stepLag = isStride ? Double(chosen.lag) / 2 : Double(chosen.lag)
                let seconds = stepLag / fs
                if (0.25...1.0).contains(seconds) {
                    stepSeconds = seconds
                    strideAC = correlation(centered, lag: Int((2 * stepLag).rounded()))
                }
            }
            let qualifies = sd >= 0.04 && stepSeconds != nil &&
                strideAC >= (run > 0 ? 0.2 : 0.6)
            if qualifies, let stepSeconds {
                run += 1
                runSteps += Double(hop) / fs / stepSeconds
                regularity += strideAC
                acceptedWindows += 1
            } else {
                if run >= 8 { totalSteps += runSteps }
                run = 0
                runSteps = 0
            }
        }
        if run >= 8 { totalSteps += runSteps }
        let duration = Double(magnitude.count) / sampleRateHz
        let steps = max(0, Int(totalSteps.rounded()))
        return Result(steps: steps, durationSeconds: duration,
                      cadenceSPM: duration > 0 ? Double(steps) * 60 / duration : 0,
                      confidence: acceptedWindows > 0
                        ? min(1, max(0, regularity / Double(acceptedWindows))) : 0)
    }

    static func estimate(x: [Double], y: [Double], z: [Double],
                         sampleRateHz: Double) -> Result {
        let count = min(x.count, y.count, z.count)
        let magnitude = (0..<count).map { i in
            sqrt(x[i] * x[i] + y[i] * y[i] + z[i] * z[i])
        }
        return estimate(magnitude: magnitude, sampleRateHz: sampleRateHz)
    }
}
