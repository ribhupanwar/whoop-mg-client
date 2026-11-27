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
