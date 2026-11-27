import Foundation

/// Shape identified from OpenStrap protocol facts (fbadb5b, gen5_records.dart).
/// Motion diagnostics only: no HR, RR, wear, sleep-stage or oxygen interpretation.
struct Gen5IMUBuffer: Equatable {
    let version: UInt8
    let recordIndex: UInt32
    let unix: UInt32
    let rawSubsecond: UInt16
    let accelerationG: [[Double]]
    let angularVelocityDPS: [[Double]]

    struct BlockFeatures: Equatable {
        let magnitudeVariationG: Double
        let adjacentMagnitudeChangeRMSG: Double?
        let meanAngularSpeedDPS: Double
    }

    /// Per-block features only; independent accel/gyro sample counts are kept.
    /// A one-second block is too short for a reliable gait cadence estimate.
    var blockFeatures: BlockFeatures? {
        func magnitudes(_ axes: [[Double]]) -> [Double]? {
            guard axes.count == 3, let n = axes.first?.count, n > 0,
                  axes.allSatisfy({ $0.count == n && $0.allSatisfy { $0.isFinite } }) else { return nil }
            var result: [Double] = []
            result.reserveCapacity(n)
            for i in 0..<n {
                let x = axes[0][i]
                let y = axes[1][i]
                let z = axes[2][i]
                let xy = x * x + y * y
                result.append(sqrt(xy + z * z))
            }
            return result
        }
        guard let a = magnitudes(accelerationG), let g = magnitudes(angularVelocityDPS) else { return nil }
        let mean = a.reduce(0, +) / Double(a.count)
        var squaredDeviation = 0.0
        for value in a {
            let delta = value - mean
            squaredDeviation += delta * delta
        }
        let variation = sqrt(squaredDeviation / Double(a.count))
        let changes = zip(a.dropFirst(), a).map { pair in
            let d = pair.0 - pair.1
            return d * d
        }
        let adjacent = changes.isEmpty ? nil : sqrt(changes.reduce(0, +) / Double(changes.count))
        return BlockFeatures(magnitudeVariationG: variation, adjacentMagnitudeChangeRMSG: adjacent,
                             meanAngularSpeedDPS: g.reduce(0, +) / Double(g.count))
    }

    static func decode(_ bytes: [UInt8]) -> Gen5IMUBuffer? {
        // Only packet routes verified by the reference. Type 0x34 has no
        // established framing here and must remain a retained raw frame.
        guard bytes.count == 1232, bytes[0] == 0x2F || bytes[0] == 0x2B else { return nil }
        func word(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8 }
        func dword(_ offset: Int) -> UInt32 { UInt32(word(offset)) | UInt32(word(offset + 2)) << 16 }
        let accelCount = Int(word(16)), gyroCount = Int(word(622))
        guard (1...100).contains(accelCount), (1...100).contains(gyroCount) else { return nil }
        func axes(_ offsets: [Int], count: Int, scale: Double) -> [[Double]] {
            offsets.map { offset in
                (0..<count).map { index in Double(Int16(bitPattern: word(offset + index * 2))) * scale }
            }
        }
        return Gen5IMUBuffer(version: bytes[1], recordIndex: dword(3), unix: dword(7),
            rawSubsecond: word(11), accelerationG: axes([20, 220, 420], count: accelCount, scale: 1.0 / 4096),
            angularVelocityDPS: axes([632, 832, 1032], count: gyroCount, scale: 2000.0 / 32768))
    }
}


/// Bounded, historical rhythm candidate. Full 100 Hz blocks only, no inferred
/// missing samples; no physiological or step-count consumer. The 6-second
/// window and correlation threshold are provisional research settings.
struct IMURhythmWindow: Equatable {
    struct Candidate: Equatable {
        let endUnix: UInt32
        let frequencyHz: Double
        let correlation: Double
    }

    private var blocks: [Gen5IMUBuffer] = []
    private(set) var candidate: Candidate?

    mutating func ingest(_ record: Gen5IMUBuffer) {
        guard record.version == 21,
              record.accelerationG.count == 3,
              record.accelerationG.allSatisfy({ $0.count == 100 && $0.allSatisfy { $0.isFinite } }) else {
            blocks.removeAll()
            candidate = nil
            return
        }
        if let last = blocks.last {
            // Older/replayed seconds cannot advance a continuous window.
            if record.unix <= last.unix { return }
            if UInt64(record.unix) != UInt64(last.unix) + 1 ||
                record.rawSubsecond != last.rawSubsecond ||
                record.recordIndex != last.recordIndex &+ 1 {
                blocks.removeAll()
                candidate = nil
            }
        }
        blocks.append(record)
        guard blocks.count == 6 else { return }
        defer { blocks = [record] }
        var magnitudes: [Double] = []
        for block in blocks {
            for j in 0..<100 {
                let x = block.accelerationG[0][j]
                let y = block.accelerationG[1][j]
                let z = block.accelerationG[2][j]
                let xy = x * x + y * y
                magnitudes.append(sqrt(xy + z * z))
            }
        }
        let mean = magnitudes.reduce(0, +) / Double(magnitudes.count)
        let centered = magnitudes.map { $0 - mean }
        let energy = centered.reduce(0.0) { $0 + $1 * $1 }
        guard energy > 1e-9 else { candidate = nil; return }
        // 29...83 samples corresponds approximately to 1.2...3.5 Hz.
        var correlations: [Double] = []
        for lag in 28...84 {
            var cross = 0.0
            for j in lag..<centered.count { cross += centered[j] * centered[j - lag] }
            correlations.append(cross / energy)
        }
        var bestIndex: Int?
        for j in 1..<(correlations.count - 1) {
            guard correlations[j] >= 0.2,
                  correlations[j] > correlations[j - 1],
                  correlations[j] >= correlations[j + 1] else { continue }
            if bestIndex.map({ correlations[j] > correlations[$0] }) ?? true { bestIndex = j }
        }
        guard let bestIndex else { candidate = nil; return }
        candidate = Candidate(endUnix: record.unix, frequencyHz: 100.0 / Double(28 + bestIndex),
                              correlation: correlations[bestIndex])
    }
}
