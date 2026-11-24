import Foundation

/// HDCZA-inspired wrist orientation inactivity evidence. Research-only.
/// GGIR's validated method uses calibrated high-frequency raw acceleration;
/// these 1 Hz gravity vectors are an approximation, not equivalent input.
/// Never use this output as a standalone sleep/wake classifier.
enum WristAngleInactivityExperiment {
    struct Window: Equatable {
        let startUnix: Int
        let endUnix: Int
        let validSamples: Int
        let maxAngleChangeDegrees: Double
        let inactive: Bool
    }

    /// A gravity-derived z angle in degrees, rejecting absent/invalid vectors.
    static func zAngleDegrees(_ sample: V18Sample) -> Double? {
        guard let x = sample.gravityXG, let y = sample.gravityYG,
              let z = sample.gravityZG, x.isFinite, y.isFinite, z.isFinite else {
            return nil
        }
        let magnitude = sqrt(x * x + y * y + z * z)
        guard (0.7...1.3).contains(magnitude) else { return nil }
        return atan2(z, sqrt(x * x + y * y)) * 180 / .pi
    }

    /// Compare the observed angle range over a 5-minute window. Require
    /// dense samples and sufficient coverage; never impute packet gaps.
    static func evaluate(_ samples: [V18Sample], startUnix: Int,
                         durationSeconds: Int = 300,
                         thresholdDegrees: Double = 5,
                         minimumCoverage: Double = 0.8) -> Window? {
        guard durationSeconds >= 60, thresholdDegrees > 0,
              (0...1).contains(minimumCoverage) else { return nil }
        let rows = samples.filter {
            $0.unix >= startUnix && $0.unix < startUnix + durationSeconds && $0.wearing
        }
        let angles = rows.compactMap { sample -> (Int, Double)? in
            guard let angle = zAngleDegrees(sample) else { return nil }
            return (sample.unix, angle)
        }
        let unique = Dictionary(angles, uniquingKeysWith: { a, _ in a })
        guard Double(unique.count) / Double(durationSeconds) >= minimumCoverage,
              let lo = unique.values.min(), let hi = unique.values.max() else {
            return nil
        }
        let spread = hi - lo
        return Window(startUnix: startUnix,
                      endUnix: startUnix + durationSeconds - 1,
                      validSamples: unique.count,
                      maxAngleChangeDegrees: spread,
                      inactive: spread < thresholdDegrees)
    }
}
