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
    // Metadata is diagnostic only. Existing scales and acceptance gates stay fixed.
    var rawMetadata: RawMetadata? = nil

    struct RawMetadata: Equatable {
        // Preserve exact unclassified header bytes. Do not label them as ODR,
        // sensor range or bias until the parser load widths/offsets are verified.
        let accelPrefix: [UInt8] // inner 13..<20
        let gyroPrefix: [UInt8] // inner 620..<632

        var summary: String {
            func hex(_ bytes: [UInt8]) -> String {
                bytes.map { String(format: "%02X", Int($0)) }.joined(separator: " ")
            }
            return "A[13–19] " + hex(accelPrefix) + " · G[620–631] " + hex(gyroPrefix)
        }
    }

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
            angularVelocityDPS: axes([632, 832, 1032], count: gyroCount, scale: 2000.0 / 32768),
            rawMetadata: RawMetadata(accelPrefix: Array(bytes[13..<20]), gyroPrefix: Array(bytes[620..<632])))
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


/// Dedicated Type 51/52 candidate layout (NOOP and whoop-rs). Input is
/// CRC-validated padded Gen5 inner, not a complete frame. The physical
/// scale, signedness, cadence and timestamp are not independently verified.
struct DedicatedIMURawRecord: Equatable {
    let packetType: UInt8
    let accelerometer: [[UInt16]]
    let gyroscope: [[UInt16]]
    let alignmentBytes: [UInt8]

    static func decodeVerifiedInner(_ bytes: [UInt8]) -> Self? {
        guard bytes.count >= 20, bytes.count <= 65_520,
              bytes[0] == 51 || bytes[0] == 52 else { return nil }
        func word(_ index: Int) -> UInt16 {
            UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
        }
        // Complete-frame offsets 24/26/28 -> inner 16/18/20.
        let a = Int(word(16)), g = Int(word(18))
        guard a > 0 || g > 0 else { return nil }
        let gyroStart = 20 + 6 * a
        let end = gyroStart + 6 * g
        let aligned = (end + 3) / 4 * 4
        guard aligned == bytes.count else { return nil }
        func axes(_ start: Int, _ count: Int) -> [[UInt16]] {
            (0..<3).map { axis in
                (0..<count).map { j in word(start + 2 * (axis * count + j)) }
            }
        }
        return Self(packetType: bytes[0], accelerometer: axes(20, a),
                    gyroscope: axes(gyroStart, g), alignmentBytes: Array(bytes[end..<aligned]))
    }
}


/// Compact per-second observations for comparing native motion with the
/// existing classifiers. A dense buffer is required; no imputed seconds.
/// The mean-axis angle is a GGIR-inspired proxy, not the GGIR classifier.
struct NativeIMUClassifierEvidence: Equatable {
    struct Second: Equatable {
        let unix: Int
        let recordIndex: UInt32
        let subsecond: UInt16
        let zAngle: Double?
        let maxMagnitudeDelta: Double
        let magnitudeVariation: Double
        let meanRotation: Double

        init?(_ record: Gen5IMUBuffer) {
            guard record.accelerationG.count == 3,
                  record.accelerationG.allSatisfy({ $0.count == 100 }),
                  record.angularVelocityDPS.count == 3,
                  record.angularVelocityDPS.allSatisfy({ $0.count == 100 }),
                  let features = record.blockFeatures else { return nil }
            unix = Int(record.unix)
            recordIndex = record.recordIndex
            subsecond = record.rawSubsecond
            var maxDelta = 0.0
            var previous: Double?
            for index in 0..<100 {
                let x = record.accelerationG[0][index]
                let y = record.accelerationG[1][index]
                let z = record.accelerationG[2][index]
                let magnitude = sqrt(x*x + y*y + z*z)
                if let previous { maxDelta = max(maxDelta, abs(magnitude - previous)) }
                previous = magnitude
            }
            maxMagnitudeDelta = maxDelta
            magnitudeVariation = features.magnitudeVariationG
            meanRotation = features.meanAngularSpeedDPS
            let x = Stats.mean(record.accelerationG[0])
            let y = Stats.mean(record.accelerationG[1])
            let z = Stats.mean(record.accelerationG[2])
            let magnitude = sqrt(x*x + y*y + z*z)
            zAngle = (0.7...1.3).contains(magnitude) ? atan2(z, sqrt(x*x + y*y)) * 180 / .pi : nil
        }
    }

    struct Report: Equatable {
        let pairedSeconds: Int
        let motionComparisonSeconds: Int
        let motionMeanAbsoluteDifferenceG: Double?
        let sleepPairedSeconds: Int
        let sleepAngleWindows: Int
        let inactiveSleepWindows: Int
        let activityPairedSeconds: Int
        let activityHRAndMotionSeconds: Int
    }

    // Store compact values, not high-rate arrays. Bounded per drain.
    static let maximumSeconds = 86_400
    private(set) var rows: [Int: Second] = [:]
    private var conflicts: Set<Int> = []

    mutating func ingest(_ record: Gen5IMUBuffer) {
        guard let row = Second(record), !conflicts.contains(row.unix) else { return }
        if let existing = rows[row.unix] {
            if existing != row {
                rows.removeValue(forKey: row.unix)
                conflicts.insert(row.unix)
            }
            return
        }
        guard rows.count + conflicts.count < Self.maximumSeconds else { return }
        rows[row.unix] = row
    }

    /// The consumer uses the same final edited sleep and detected activity
    /// intervals as the published analysis. Missing/replayed data never
    /// becomes evidence for or against a classification.
    func compare(samples: [V18Sample], sleep: [SleepPeriod],
                 activities: [ActivitySession]) -> Report? {
        guard !rows.isEmpty else { return nil }
        let canonical = HistoricalCaptureRecovery.merged(samples)
        var paired = 0
        var motionErrors: [Double] = []
        var sleepPairs = 0
        var angleBuckets: [Int: [Double]] = [:]
        var activityPairs = 0
        var activityMotion = 0
        for (unix, imu) in rows {
            guard let sample = canonical[unix], sample.wearing,
                  sample.header.recordIndex == imu.recordIndex,
                  sample.header.subsecQ15 == Int(imu.subsecond) else { continue }
            paired += 1
            if let motion = sample.dynamicAccelG, motion.isFinite, motion >= 0 {
                motionErrors.append(abs(motion - imu.maxMagnitudeDelta))
            }
            if let period = sleep.first(where: { $0.startUnix <= unix && unix <= $0.endUnix }) {
                sleepPairs += 1
                // Only fully contained 5-minute windows; do not mix sessions.
                let start = period.startUnix + (unix - period.startUnix) / 300 * 300
                if start + 299 <= period.endUnix, let angle = imu.zAngle {
                    angleBuckets[start, default: []].append(angle)
                }
            }
            if activities.contains(where: { $0.startUnix <= unix && unix <= $0.endUnix }) {
                activityPairs += 1
                // Diagnostic evidence count only. This does not create workouts.
                if sample.heartRate >= 100, imu.maxMagnitudeDelta >= 0.03 {
                    activityMotion += 1
                }
            }
        }
        let eligible = angleBuckets.values.filter { $0.count >= 240 }
        let inactive = eligible.filter { angles in
            guard let minimum = angles.min(), let maximum = angles.max() else { return false }
            return maximum - minimum < 5
        }.count
        return Report(pairedSeconds: paired, motionComparisonSeconds: motionErrors.count,
                      motionMeanAbsoluteDifferenceG: motionErrors.isEmpty ? nil : Stats.mean(motionErrors),
                      sleepPairedSeconds: sleepPairs, sleepAngleWindows: eligible.count,
                      inactiveSleepWindows: inactive, activityPairedSeconds: activityPairs,
                      activityHRAndMotionSeconds: activityMotion)
    }
}


/// Ghidra-verified Maverick/Goose Rev10 layout (`_TtC20WhoopBluetoothLegacy9R10Packet`).
/// Offsets on the wire are 4-byte legacy envelope framed (e.g., HR at packet offset 0x15 = inner 17).
/// Total inner payload is 1932 bytes.
struct Gen5R10RawCandidate: Equatable {
    let packetType: UInt8
    let timestamp: UInt32
    let subsecondQ15: UInt16
    let rawHeartRate: UInt8
    let accelerometer: [[Int16]]
    let gyroscope: [[Int16]]

    static func decodeVerifiedInner(_ bytes: [UInt8]) -> Self? {
        // Match only the source's exact Gen5 payload hypothesis. Compact
        // Type-40 k10, Gen4 R10, and historical revision collisions are not it.
        guard bytes.count == 1932, bytes[1] == 10,
              bytes[0] == 0x28 || bytes[0] == 0x2B else { return nil }
        let ts = UInt32(bytes[7]) | (UInt32(bytes[8]) << 8) | (UInt32(bytes[9]) << 16) | (UInt32(bytes[10]) << 24)
        let sub = UInt16(bytes[11]) | (UInt16(bytes[12]) << 8)
        func axes(_ offsets: [Int]) -> [[Int16]] {
            offsets.map { offset in
                (0..<100).map { index in
                    let p = offset + 2 * index
                    let word = UInt16(bytes[p]) | (UInt16(bytes[p + 1]) << 8)
                    return Int16(bitPattern: word)
                }
            }
        }
        return Self(packetType: bytes[0],
                    timestamp: ts,
                    subsecondQ15: sub,
                    rawHeartRate: bytes[17],
                    accelerometer: axes([85, 285, 485]),
                    gyroscope: axes([688, 888, 1088]))
    }
}
