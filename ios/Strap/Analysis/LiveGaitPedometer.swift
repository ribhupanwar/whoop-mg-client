import Foundation

/// Swift adaptation of OpenStrap/analytics live gait-periodicity pedometer.
/// Upstream: lib/src/onehz/motion/steps.dart (AGPL-3.0).
/// This is an optional 50–100 Hz IMU cross-check, NOT a replacement for the
/// band's decoded historical step counter and NOT a 1 Hz step estimator.
enum LiveGaitPedometer {
    struct WindowCredit: Equatable {
        // Relative end second of the four-second analysis window.
        let endSecond: Int
        let steps: Double
    }

    struct Result: Equatable {
        let steps: Int
        let durationSeconds: Double
        let cadenceSPM: Double
        let confidence: Double
        var fractionalSteps: Double = 0
        var qualifiedWindows: [WindowCredit] = []
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
    static func estimate(magnitude: [Double], sampleRateHz: Double, latestSecondOnly: Bool = false) -> Result {
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
        var latestSecondSteps = 0.0
        var pendingWindows: [WindowCredit] = []
        var qualifiedWindows: [WindowCredit] = []
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
                latestSecondSteps = run >= 8 ? Double(hop) / fs / stepSeconds : 0
                let steps = Double(hop) / fs / stepSeconds
                runSteps += steps
                pendingWindows.append(WindowCredit(endSecond: (start + window) / hop - 1, steps: steps))
                regularity += strideAC
                acceptedWindows += 1
            } else {
                latestSecondSteps = 0
                if run >= 8 {
                    totalSteps += runSteps
                    qualifiedWindows.append(contentsOf: pendingWindows)
                }
                pendingWindows.removeAll(keepingCapacity: true)
                run = 0
                runSteps = 0
            }
        }
        if run >= 8 {
            totalSteps += runSteps
            qualifiedWindows.append(contentsOf: pendingWindows)
        }
        let duration = Double(magnitude.count) / sampleRateHz
        let count = latestSecondOnly ? latestSecondSteps : totalSteps
        let steps = max(0, Int(count.rounded()))
        return Result(steps: steps, durationSeconds: duration,
                      cadenceSPM: duration > 0 ? Double(steps) * 60 / duration : 0,
                      confidence: acceptedWindows > 0
                        ? min(1, max(0, regularity / Double(acceptedWindows))) : 0,
                      fractionalSteps: count, qualifiedWindows: qualifiedWindows)
    }

    static func estimate(x: [Double], y: [Double], z: [Double],
                         sampleRateHz: Double) -> Result {
        let count = min(x.count, min(y.count, z.count))
        var magnitude = [Double]()
        magnitude.reserveCapacity(count)
        for i in 0..<count {
            let xx = x[i] * x[i]
            let yy = y[i] * y[i]
            let zz = z[i] * z[i]
            magnitude.append(sqrt(xx + yy + zz))
        }
        return estimate(magnitude: magnitude, sampleRateHz: sampleRateHz)
    }
}

struct LiveWorkoutStepReading: Equatable {
    let count: Int
    let observedAt: Date
}

/// The rolling estimator may reclassify overlapping windows. Never credit a
/// previously credited absolute window end, even after a gap or reconnect.
struct LiveGaitCreditLedger {
    private var lastCreditedEnd: UInt32?

    mutating func accept(_ windows: [LiveGaitPedometer.WindowCredit], endingAt end: UInt32) -> [(second: UInt32, steps: Double)] {
        var accepted: [(second: UInt32, steps: Double)] = []
        // Live buffers contain exactly eleven one-second blocks.
        for window in windows.sorted(by: { $0.endSecond < $1.endSecond }) {
            guard (3...10).contains(window.endSecond), window.steps.isFinite, window.steps > 0 else { continue }
            let age = UInt32(10 - window.endSecond)
            guard end >= age else { continue }
            let second = end - age
            guard lastCreditedEnd.map({ second > $0 }) ?? true else { continue }
            accepted.append((second, window.steps))
            lastCreditedEnd = second
        }
        return accepted
    }
}

/// Owns each decoded second exactly once. Gaps reset estimation context.
struct LiveWorkoutStepAccumulator {
    private var lastBlock: Gen5IMUBuffer?
    private var magnitude: [Double] = []
    private var total = 0.0
    private var credits = LiveGaitCreditLedger()
    private var highWaterUnix: UInt32?

    mutating func interrupt() {
        magnitude.removeAll(keepingCapacity: true)
    }

    mutating func reconnect() {
        interrupt()
        lastBlock = nil
    }

    mutating func ingest(_ block: Gen5IMUBuffer, at date: Date) -> LiveWorkoutStepReading? {
        guard block.version == 21, block.accelerationG.count == 3,
              block.accelerationG.allSatisfy({ $0.count == 100 && $0.allSatisfy(\.isFinite) }) else {
            interrupt()
            return nil
        }
        if let highWaterUnix, block.unix <= highWaterUnix { return nil }
        if let previous = lastBlock {
            if block.unix - previous.unix != 1 || block.recordIndex != previous.recordIndex &+ 1
                || block.rawSubsecond != previous.rawSubsecond {
                interrupt()
            }
        }
        highWaterUnix = block.unix
        lastBlock = block
        let axes = block.accelerationG
        for i in 0..<100 {
            let (x, y, z) = (axes[0][i], axes[1][i], axes[2][i])
            magnitude.append(sqrt(x * x + y * y + z * z))
        }
        if magnitude.count > 1100 { magnitude.removeFirst(magnitude.count - 1100) }
        guard magnitude.count == 1100 else { return nil }
        let estimate = LiveGaitPedometer.estimate(magnitude: magnitude, sampleRateHz: 100)
        for credit in credits.accept(estimate.qualifiedWindows, endingAt: block.unix) {
            total += credit.steps
        }
        return LiveWorkoutStepReading(count: Int(total.rounded()), observedAt: date)
    }
}
