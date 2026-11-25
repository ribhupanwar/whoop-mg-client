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
    /// Diagnostic HR flags (inner[28]). In real physical WHOOP captures (32,663 records),
    /// bit 7 is unset (0) for 100% of samples while valid RR is present. Never gate RR on bit 7.
    let hrQualityFlags: Int?
    let spo2CandidateRaw: Int?
    let spo2CandidatePct: Int?
    let spo2CandidateKind: Spo2CandidateKind
    let signalQualityLogVariance: Double?
    /// Signed optical pSNR (dB); -128 means unavailable, not low quality or sample rejection.
    let psnrB: Int?
    let psnrA: Int?
    /// Diagnostic quality flag: true when all unused trailing RR slots are zero-padded.
    /// Unused padding is never used to discard valid declared beats.
    let rrPaddingValid: Bool

    init(
        header: BandRecordHeader,
        heartRate: Int,
        rrIntervalsMS: [Int] = [],
        dynamicAccelG: Double? = nil,
        gravityXG: Double? = nil,
        gravityYG: Double? = nil,
        gravityZG: Double? = nil,
        stepCounter: Int? = nil,
        stepCadence: Int? = nil,
        activityClass: Int? = nil,
        skinTempC: Double? = nil,
        tempAux1C: Double? = nil,
        tempAux2C: Double? = nil,
        sleepStateByte: Int? = nil,
        sleepState: Int? = nil,
        cardiacFlags: Int? = nil,
        hrQualityFlags: Int? = nil,
        spo2CandidateRaw: Int? = nil,
        spo2CandidatePct: Int? = nil,
        spo2CandidateKind: Spo2CandidateKind = .absent,
        signalQualityLogVariance: Double? = nil,
        psnrB: Int? = nil,
        psnrA: Int? = nil,
        rrPaddingValid: Bool = true
    ) {
        self.header = header
        self.heartRate = heartRate
        self.rrIntervalsMS = rrIntervalsMS
        self.dynamicAccelG = dynamicAccelG
        self.gravityXG = gravityXG
        self.gravityYG = gravityYG
        self.gravityZG = gravityZG
        self.stepCounter = stepCounter
        self.stepCadence = stepCadence
        self.activityClass = activityClass
        self.skinTempC = skinTempC
        self.tempAux1C = tempAux1C
        self.tempAux2C = tempAux2C
        self.sleepStateByte = sleepStateByte
        self.sleepState = sleepState
        self.cardiacFlags = cardiacFlags
        self.hrQualityFlags = hrQualityFlags
        self.spo2CandidateRaw = spo2CandidateRaw
        self.spo2CandidatePct = spo2CandidatePct
        self.spo2CandidateKind = spo2CandidateKind
        self.signalQualityLogVariance = signalQualityLogVariance
        self.psnrB = psnrB
        self.psnrA = psnrA
        self.rrPaddingValid = rrPaddingValid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.header = try container.decode(BandRecordHeader.self, forKey: .header)
        self.heartRate = try container.decode(Int.self, forKey: .heartRate)
        self.rrIntervalsMS = try container.decodeIfPresent([Int].self, forKey: .rrIntervalsMS) ?? []
        self.dynamicAccelG = try container.decodeIfPresent(Double.self, forKey: .dynamicAccelG)
        self.gravityXG = try container.decodeIfPresent(Double.self, forKey: .gravityXG)
        self.gravityYG = try container.decodeIfPresent(Double.self, forKey: .gravityYG)
        self.gravityZG = try container.decodeIfPresent(Double.self, forKey: .gravityZG)
        self.stepCounter = try container.decodeIfPresent(Int.self, forKey: .stepCounter)
        self.stepCadence = try container.decodeIfPresent(Int.self, forKey: .stepCadence)
        self.activityClass = try container.decodeIfPresent(Int.self, forKey: .activityClass)
        self.skinTempC = try container.decodeIfPresent(Double.self, forKey: .skinTempC)
        self.tempAux1C = try container.decodeIfPresent(Double.self, forKey: .tempAux1C)
        self.tempAux2C = try container.decodeIfPresent(Double.self, forKey: .tempAux2C)
        self.sleepStateByte = try container.decodeIfPresent(Int.self, forKey: .sleepStateByte)
        self.sleepState = try container.decodeIfPresent(Int.self, forKey: .sleepState)
        self.cardiacFlags = try container.decodeIfPresent(Int.self, forKey: .cardiacFlags)
        self.hrQualityFlags = try container.decodeIfPresent(Int.self, forKey: .hrQualityFlags)
        self.spo2CandidateRaw = try container.decodeIfPresent(Int.self, forKey: .spo2CandidateRaw)
        self.spo2CandidatePct = try container.decodeIfPresent(Int.self, forKey: .spo2CandidatePct)
        self.spo2CandidateKind = try container.decodeIfPresent(Spo2CandidateKind.self, forKey: .spo2CandidateKind) ?? .absent
        self.signalQualityLogVariance = try container.decodeIfPresent(Double.self, forKey: .signalQualityLogVariance)
        self.psnrB = try container.decodeIfPresent(Int.self, forKey: .psnrB)
        self.psnrA = try container.decodeIfPresent(Int.self, forKey: .psnrA)
        self.rrPaddingValid = try container.decodeIfPresent(Bool.self, forKey: .rrPaddingValid) ?? true
    }

    var unix: Int { Int(header.unix) }
    var wearing: Bool {
        if heartRate <= 0 { return false }
        // Filter confirmed tabletop artifacts: ambient cold temperature + complete stillness
        if let temp = skinTempC, temp < 25.0, (dynamicAccelG ?? 0) < 0.005 {
            return false
        }
        return true
    }
    var wristContactState: WristContactState {
        wearing ? .onWrist : .offWrist
    }
}

/// Stable choice when replayed history contains multiple records in one second.
/// Preserve a usable HR value before preferring richer auxiliary channels.
enum HistoricalRecordSelection {
    static func prefers(_ candidate: V18Sample, over current: V18Sample) -> Bool {
        let candidateHRValid = (V18Decoder.minHR...V18Decoder.maxHR).contains(candidate.heartRate)
        let currentHRValid = (V18Decoder.minHR...V18Decoder.maxHR).contains(current.heartRate)
        if candidateHRValid != currentHRValid { return candidateHRValid }
        if candidate.rrIntervalsMS.count != current.rrIntervalsMS.count {
            return candidate.rrIntervalsMS.count > current.rrIntervalsMS.count
        }
        let candidateHasMotion = candidate.dynamicAccelG != nil
        let currentHasMotion = current.dynamicAccelG != nil
        if candidateHasMotion != currentHasMotion { return candidateHasMotion }
        if candidate.header.recordIndex != current.header.recordIndex {
            return candidate.header.recordIndex < current.header.recordIndex
        }
        return false
    }
}

enum V18Decoder {
    static let version = 18
    static let minReadable = 109
    static let minRRMS = 200
    static let maxRRMS = 3000
    static let maxRRCount = 4  // V18 RR block capacity: 8 bytes (offsets 16..<24)
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
        var paddingValid = true
        // Only the declared RR slots are beats. Unused trailing bytes are not
        // independently verified as zero padding on every firmware revision.
        // Frame checksums are validated by Gen5Frame before this decoder runs;
        // do not discard valid declared beats because of opaque unused bytes.
        if declared <= maxRRCount {
            for index in 0..<declared {
                if let value = i16(inner, 16 + 2 * index),
                   (minRRMS...maxRRMS).contains(value) {
                    rr.append(value)
                }
            }
            let unusedStart = 16 + 2 * declared
            for offset in unusedStart..<24 {
                if offset < inner.count && inner[offset] != 0 {
                    paddingValid = false
                    break
                }
            }
        } else {
            paddingValid = false
        }

        var dyn = f32(inner, 33)
        if let value = dyn, !(0...fullScaleG).contains(value) {
            dyn = nil
        }

        let axes = (f32(inner, 37), f32(inner, 41), f32(inner, 45))
        var gravity: (Double, Double, Double)?
        if let x = axes.0, let y = axes.1, let z = axes.2,
           abs(x) <= fullScaleG, abs(y) <= fullScaleG, abs(z) <= fullScaleG {
            gravity = (round4(x), round4(y), round4(z))
        }

        let sleepByte = inner.count > 73 ? Int(inner[73]) : nil
        let spo2Raw = inner.count > 74 ? Int(inner[74]) : nil
        let spo2 = spo2Candidate(raw: spo2Raw)

        return V18Sample(
            header: header,
            heartRate: hr,
            rrIntervalsMS: rr,
            dynamicAccelG: dyn.map { round4($0) },
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
            signalQualityLogVariance: f32(inner, 105).map { round4($0) },
            psnrB: signedByte(inner, 100),
            psnrA: signedByte(inner, 101),
            rrPaddingValid: paddingValid
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

    static func f32(_ bytes: [UInt8], _ offset: Int) -> Double? {
        guard let raw = u32(bytes, offset) else { return nil }
        let value = Float(bitPattern: raw)
        guard value.isFinite else { return nil }
        return Double(value)
    }

    private static func temp(_ bytes: [UInt8], _ offset: Int, scale: Double) -> Double? {
        guard let raw = i16(bytes, offset) else { return nil }
        return round2(Double(raw) / scale)
    }

    static func round4(_ value: Double) -> Double {
        (value * 10_000.0).rounded() / 10_000.0
    }

    private static func round2(_ value: Double) -> Double {
        (value * 100.0).rounded() / 100.0
    }

    private static func round(_ value: Double, _ digits: Int) -> Double {
        let scale: Double
        switch digits {
        case 1: scale = 10.0
        case 2: scale = 100.0
        case 3: scale = 1_000.0
        case 4: scale = 10_000.0
        default: scale = pow(10.0, Double(digits))
        }
        return (value * scale).rounded() / scale
    }
}


/// Research-only decoder for OpenWHOOP's historical optical k=21 array layout.
/// Input is the unwrapped 1244-byte optical record body, NOT the BLE frame.
/// This does not identify a red wavelength or calculate calibrated SpO2.
struct HistoricalOpticalK21: Equatable {
    let green: [[Int16]]
    let infrared: [[Int16]]
}

/// Optical signal diagnostics only. These raw ADC counts cannot be converted
/// into calibrated SpO2 without verified wavelength mapping and calibration.
enum OpticalSignalValidity: Equatable {
    case missing, flatline, clipped, variable
}

extension HistoricalOpticalK21 {
    var signalValidity: OpticalSignalValidity {
        let channels = green + infrared
        guard channels.count == 6, channels.allSatisfy({ $0.count == 100 }) else { return .missing }
        // Signed ADC rails are not valid oxygen saturation measurements.
        if channels.contains(where: { $0.contains(Int16.min) || $0.contains(Int16.max) }) {
            return .clipped
        }
        if channels.allSatisfy({ channel in
            guard let first = channel.first else { return true }
            return channel.allSatisfy { $0 == first }
        }) { return .flatline }
        return .variable
    }
}

enum HistoricalOpticalK21Decoder {
    static let expectedBodyBytes = 1244
    static let samplesPerChannel = 100
    private static let greenOffsets = [20, 220, 420]
    private static let infraredOffsets = [632, 832, 1032]

    static func decode(body: [UInt8]) -> HistoricalOpticalK21? {
        guard body.count == expectedBodyBytes else { return nil }
        func channel(at offset: Int) -> [Int16]? {
            guard offset >= 0, offset + samplesPerChannel * 2 <= body.count else { return nil }
            return (0..<samplesPerChannel).map { index in
                let position = offset + index * 2
                let bits = UInt16(body[position]) | (UInt16(body[position + 1]) << 8)
                return Int16(bitPattern: bits)
            }
        }
        let green = greenOffsets.compactMap { channel(at: $0) }
        let infrared = infraredOffsets.compactMap { channel(at: $0) }
        guard green.count == 3, infrared.count == 3 else { return nil }
        return HistoricalOpticalK21(green: green, infrared: infrared)
    }
}
