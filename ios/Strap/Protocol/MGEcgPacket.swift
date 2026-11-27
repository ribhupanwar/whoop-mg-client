import Foundation

/// Passive filtered R17 observations. Layout documented in NOOP PROTOCOL_ECG.md
/// at 2a1de7609843b095505274ad6fc811757210be80. Values retain native units.
struct MGEcgPacket: Equatable {
    let samples: [Int16]
    let status: NativeECGStatus?

    init(samples: [Int16], status: NativeECGStatus? = nil) {
        self.samples = samples
        self.status = status
    }

    static func isMG(model: String?) -> Bool {
        model?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "MG"
    }

    /// Input must come from the Gen5 reassembler after both CRC checks.
    static func decodeVerifiedInner(_ bytes: [UInt8]) -> Self? {
        guard bytes.count == 228, bytes[1] == 17,
              bytes[0] == 43 || bytes[0] == 47,
              bytes[226] == 0, bytes[227] == 0 else { return nil }
        let count = Int(bytes[24]) | Int(bytes[25]) << 8
        guard count <= 100 else { return nil }

        let samples = (0..<count).map { index -> Int16 in
            let offset = 26 + index * 2
            return Int16(bitPattern: UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8)
        }
        return Self(samples: samples, status: NativeECGStatus(inner: bytes))
    }
}


/// Uncalibrated ECG status at inner offsets 13...25. Never use the raw
/// HRV-related word as milliseconds or as overnight recovery HRV.
struct NativeECGStatus: Equatable {
    let qualityCode: UInt8
    let stateBits: UInt8
    let classifierCode: UInt8
    let classifierState: UInt8
    let progressRaw: UInt8
    let flagsRaw: UInt8
    let hrRelatedRaw: UInt8
    let additionalHRRaw: UInt8
    let hrvRelatedRaw: UInt16

    init(inner: [UInt8]) {
        qualityCode = inner[13]
        stateBits = inner[14]
        classifierCode = inner[15]
        classifierState = inner[16]
        progressRaw = inner[17]
        flagsRaw = inner[18]
        hrRelatedRaw = inner[19]
        additionalHRRaw = inner[20]
        hrvRelatedRaw = UInt16(inner[21]) | UInt16(inner[22]) << 8
    }
}

/// R16 native waveform codes. No voltage, clinical quality, or sample
/// frequency inferred. Caller must use the CRC-validated Gen5 inner frame.
struct MGRawECGPacket: Equatable {
    struct Sample: Equatable {
        let code: Int32
        let flagsAndReserved: UInt8
    }
    let status: NativeECGStatus
    let samples: [Sample]
    let leadI: [Int16]
    let leadQ: [Int16]

    static func decodeVerifiedInner(_ b: [UInt8]) -> Self? {
        guard b.count == 1572, b[1] == 16,
              b[0] == 43 || b[0] == 47, b[1571] == 0 else { return nil }
        func word(_ index: Int) -> UInt16 {
            UInt16(b[index]) | UInt16(b[index + 1]) << 8
        }
        let count = Int(word(24))
        let leadCount = Int(b[1526])
        guard count <= 500, leadCount <= 11 else { return nil }
        var samples: [Sample] = []
        samples.reserveCapacity(count)
        for index in 0..<count {
            let i = 26 + 3 * index
            let high = Int32(b[i] & 3) << 16
            let middle = Int32(b[i + 1]) << 8
            let raw = high | middle | Int32(b[i + 2])
            let signed = raw >= 131_072 ? raw - 262_144 : raw
            samples.append(Sample(code: signed, flagsAndReserved: b[i] & 0xFC))
        }
        let iWords = (0..<leadCount).map { Int16(bitPattern: word(1527 + 2 * $0)) }
        let qWords = (0..<leadCount).map { Int16(bitPattern: word(1549 + 2 * $0)) }
        return Self(status: NativeECGStatus(inner: b), samples: samples, leadI: iWords, leadQ: qWords)
    }
}
