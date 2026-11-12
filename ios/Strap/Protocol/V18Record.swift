import Foundation

/// Shared gen5 historical-record header, inner-relative.
struct BandRecordHeader: Equatable, Codable {
    let version: Int
    let flags: Int
    let recordIndex: UInt32
    let unix: UInt32
    let subsecQ15: Int

    var timestamp: Double { Double(unix) + Double(subsecQ15) / 32_768.0 }
    var ppgSampleRateHz: Int { flags & 0x80 != 0 ? 25 : 50 }

    /// A lost band RTC can timestamp historical records in 1970/1971.
    /// Reject those records from metrics, but keep their raw frames on disk.
    static func plausibleHistoricalUnix(_ unix: UInt32, now: Date = Date()) -> Bool {
        let seconds = TimeInterval(unix)
        return seconds >= 1_577_836_800 && seconds <= now.timeIntervalSince1970 + 48 * 3600
    }
}

enum Spo2CandidateKind: String, Codable {
    case absent
    case pct
    case saturated
    case diagnostic
}

/// One second of v18 biometrics. Every field can be absent; an implausible
/// value is dropped on its own rather than discarding the whole second.
struct V18Sample: Equatable, Codable {
    let header: BandRecordHeader
    let heartRate: Int
    let rrIntervalsMS: [Int]
    let dynamicAccelG: Double?
    let gravityXG: Double?
    let gravityYG: Double?
    let gravityZG: Double?
    let stepCounter: Int?
    let stepCadence: Int?
    let activityClass: Int?
    let skinTempC: Double?
    let tempAux1C: Double?
    let tempAux2C: Double?
    let sleepStateByte: Int?
    /// Bits 4-5 of the sleep-state byte. The enum is NOT established, so it is
    /// reported but never named or used to decide sleep.
    let sleepState: Int?
    let cardiacFlags: Int?
    let hrQualityFlags: Int?
    let spo2CandidateRaw: Int?
    let spo2CandidatePct: Int?
    let spo2CandidateKind: Spo2CandidateKind
    let signalQualityLogVariance: Double?
    /// Signed optical pSNR (dB); -128 means unavailable, not low quality.
    let psnrB: Int?
    let psnrA: Int?

    var unix: Int { Int(header.unix) }
    var wearing: Bool { heartRate > 0 }
}

enum V18Decoder {
    static let version = 18
    static let minReadable = 109
    static let minRRMS = 200
    static let maxRRMS = 3000
    static let minHR = 25
    static let maxHR = 230
    static let fullScaleG = 16.0
    static let spo2CandidateMin = 70
    static let spo2CandidateMax = 100
    static let spo2SaturatedBit = 0x80

    /// Tri-mode byte: 70-100 is the band's own candidate percentage, bit 7 is
    /// a saturation sentinel, any other nonzero value is a diagnostic code.
    /// It is a candidate, never a clinical SpO2 and never a score input.
    static func spo2Candidate(raw: Int?) -> (pct: Int?, kind: Spo2CandidateKind) {
        guard let raw, raw != 0 else { return (nil, .absent) }
        if raw >= spo2CandidateMin && raw <= spo2CandidateMax {
            return (raw, .pct)
        }
        if raw & spo2SaturatedBit != 0 {
            return (nil, .saturated)
        }
        return (nil, .diagnostic)
    }

    static func decode(_ inner: [UInt8]) -> V18Sample? {
        guard inner.count >= minReadable, inner[0] == 0x2F, inner[1] == version else {
            return nil
        }
        guard let header = header(of: inner) else { return nil }

        let hrRaw = Int(inner[14])
        let hr = (minHR...maxHR).contains(hrRaw) ? hrRaw : 0

        var rr: [Int] = []
        let declared = Int(inner[15])
        if declared <= 4 {
            for index in 0..<declared {
                if let value = i16(inner, 16 + 2 * index),
                   (minRRMS...maxRRMS).contains(value) {
                    rr.append(value)
                }
            }
        }

        var dyn = f32(inner, 33)
        if let value = dyn, !(0...fullScaleG).contains(value) {
            dyn = nil
        }

        let axes = (f32(inner, 37), f32(inner, 41), f32(inner, 45))
        var gravity: (Double, Double, Double)?
        if let x = axes.0, let y = axes.1, let z = axes.2,
           abs(x) <= fullScaleG, abs(y) <= fullScaleG, abs(z) <= fullScaleG {
            gravity = (round(x, 4), round(y, 4), round(z, 4))
        }

        let sleepByte = inner.count > 73 ? Int(inner[73]) : nil
        let spo2Raw = inner.count > 74 ? Int(inner[74]) : nil
        let spo2 = spo2Candidate(raw: spo2Raw)

        return V18Sample(
            header: header,
            heartRate: hr,
            rrIntervalsMS: rr,
            dynamicAccelG: dyn.map { round($0, 4) },
            gravityXG: gravity?.0,
            gravityYG: gravity?.1,
            gravityZG: gravity?.2,
            stepCounter: u16(inner, 49),
            stepCadence: inner.count > 51 ? Int(inner[51]) : nil,
            activityClass: inner.count > 55 ? Int(inner[55]) : nil,
            skinTempC: temp(inner, 65, scale: 100.0),
            tempAux1C: temp(inner, 61, scale: 10.0),
            tempAux2C: temp(inner, 63, scale: 10.0),
            sleepStateByte: sleepByte,
            sleepState: sleepByte.map { ($0 >> 4) & 0x03 },
            cardiacFlags: inner.count > 25 ? Int(inner[25]) : nil,
            hrQualityFlags: inner.count > 28 ? Int(inner[28]) : nil,
            spo2CandidateRaw: spo2Raw,
            spo2CandidatePct: spo2.pct,
            spo2CandidateKind: spo2.kind,
            signalQualityLogVariance: f32(inner, 105).map { round($0, 4) },
            psnrB: signedByte(inner, 100),
            psnrA: signedByte(inner, 101)
        )
    }

    static func header(of inner: [UInt8]) -> BandRecordHeader? {
        guard inner.count >= 13, inner[0] == 0x2F else { return nil }
        guard let index = u32(inner, 3), let unix = u32(inner, 7),
              let subsec = u16(inner, 11) else { return nil }
        return BandRecordHeader(
            version: Int(inner[1]),
            flags: Int(inner[2]),
            recordIndex: index,
            unix: unix,
            subsecQ15: subsec
        )
    }

    private static func signedByte(_ bytes: [UInt8], _ offset: Int) -> Int? {
        guard bytes.indices.contains(offset) else { return nil }
        let raw = Int(bytes[offset])
        return raw >= 128 ? raw - 256 : raw
    }

    // MARK: - Little-endian readers

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> Int? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
    }

    private static func i16(_ bytes: [UInt8], _ offset: Int) -> Int? {
        guard let raw = u16(bytes, offset) else { return nil }
        return raw >= 0x8000 ? raw - 0x1_0000 : raw
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func f32(_ bytes: [UInt8], _ offset: Int) -> Double? {
        guard let raw = u32(bytes, offset) else { return nil }
        let value = Float(bitPattern: raw)
        guard value.isFinite else { return nil }
        return Double(value)
    }

    private static func temp(_ bytes: [UInt8], _ offset: Int, scale: Double) -> Double? {
        guard let raw = i16(bytes, offset) else { return nil }
        return round(Double(raw) / scale, 2)
    }

    private static func round(_ value: Double, _ digits: Int) -> Double {
        let scale = pow(10.0, Double(digits))
        return (value * scale).rounded() / scale
    }
}

 
/// OpenStrap Gen5 deep-buffer record layouts. Optical v20 is deliberately
/// kept separate from per-second HR/RR; its ADC data is NOT RR milliseconds.
enum Gen5DeepBuffer {
    struct OpticalV20 {
        let header: BandRecordHeader
        let sampleRateHz: Int
        let rawInner: [UInt8]
        let blocks: [OpticalBlock]
    }
    struct OpticalBlock {
        let sampleCount: Int
        let channel0ADC: [Int]
        let channel1ADC: [Int]
        let sharedMetadata: [UInt8]
        let channel0Metadata: [UInt8]
        let channel1Metadata: [UInt8]
    }
    struct MotionV21 {
        let header: BandRecordHeader
        let accelXG: [Double]
        let accelYG: [Double]
        let accelZG: [Double]
        let gyroXDPS: [Double]
        let gyroYDPS: [Double]
        let gyroZDPS: [Double]
    }
    private static func u16(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) | Int(b[i+1]) << 8
    }
    private static func axis(_ b: [UInt8], _ offset: Int, _ count: Int, _ scale: Double) -> [Double] {
        (0..<count).map { n in
            let raw = u16(b, offset + n * 2)
            let signed = raw >= 32768 ? raw - 65536 : raw
            return Double(signed) * scale
        }
    }
    private static func opticalChannel(_ bytes: [UInt8], _ start: Int, _ count: Int) -> [Int] {
        (0..<count).map { index in
            let offset = start + 4 * index
            let raw = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
                | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
            let value = raw & 0xFFFFF
            return value & 0x80000 != 0 ? value - 0x100000 : value
        }
    }
    static func opticalV20(_ inner: [UInt8]) -> OpticalV20? {
        guard inner.count == 2128, inner[0] == 0x2F, inner[1] == 20,
              let header = V18Decoder.header(of: inner) else { return nil }
        let rate = u16(inner, 15)
        guard (1...200).contains(rate) else { return nil }
        let blocks: [OpticalBlock] = (0..<5).map { index in
            let start = 18 + index * 422
            let count = Int(inner[start]) <= 50 ? Int(inner[start]) : 0
            return OpticalBlock(sampleCount: count,
                channel0ADC: opticalChannel(inner, start + 21, count),
                channel1ADC: opticalChannel(inner, start + 221, count),
                sharedMetadata: Array(inner[(start + 1)..<(start + 7)]),
                channel0Metadata: Array(inner[(start + 7)..<(start + 14)]),
                channel1Metadata: Array(inner[(start + 14)..<(start + 21)]))
        }
        return OpticalV20(header: header, sampleRateHz: rate, rawInner: inner, blocks: blocks)
    }
    static func motionV21(_ inner: [UInt8]) -> MotionV21? {
        guard inner.count == 1232, (inner[0] == 0x2F || inner[0] == 0x2B),
              inner[1] == 21, let header = V18Decoder.header(of: inner) else { return nil }
        let accelCount = u16(inner, 16), gyroCount = u16(inner, 622)
        guard (1...100).contains(accelCount), (1...100).contains(gyroCount) else { return nil }
        return MotionV21(header: header,
            accelXG: axis(inner, 20, accelCount, 1.0 / 4096.0),
            accelYG: axis(inner, 220, accelCount, 1.0 / 4096.0),
            accelZG: axis(inner, 420, accelCount, 1.0 / 4096.0),
            gyroXDPS: axis(inner, 632, gyroCount, 2000.0 / 32768.0),
            gyroYDPS: axis(inner, 832, gyroCount, 2000.0 / 32768.0),
            gyroZDPS: axis(inner, 1032, gyroCount, 2000.0 / 32768.0))
    }
}
