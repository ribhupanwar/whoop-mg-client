import Foundation

/// Historical Type 47 revision 20. Offsets are relative to the CRC-verified
/// inner frame. The two detector slots share an emitter configuration.
struct Gen5V20Record: Equatable {
    struct Detector: Equatable {
        let selector: UInt8
        let range: UInt32
        let offset: Int16
        // Nil preserves the position of a malformed signed 20-bit container.
        let samples: [Int32?]

        var saturatedSampleCount: Int {
            samples.filter { $0 == -524_288 || $0 == 524_287 }.count
        }

        var isFlatline: Bool {
            guard samples.count > 1, let first = samples[0] else { return false }
            return samples.allSatisfy { $0 == first }
        }
    }

    struct Block: Equatable {
        let sourceA: UInt8
        let driveA: UInt16
        let sourceB: UInt8
        let driveB: UInt16
        let detectorA: Detector
        let detectorB: Detector
        let reserved: UInt8
    }

    static let version = 20
    static let innerLength = 2128
    static let numBlocks = 5
    static let blockLength = 422
    static let bodyStart = 18

    let header: BandRecordHeader
    let rawBody: [UInt8]
    let sampleRateHz: UInt16?
    let blocks: [Block]

    static func decode(_ bytes: [UInt8]) -> Gen5V20Record? {
        guard bytes.count == innerLength, bytes[0] == 0x2F, bytes[1] == version,
              let header = V18Decoder.header(of: bytes) else { return nil }
        func u16(_ index: Int) -> UInt16 {
            UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
        }
        func u32(_ index: Int) -> UInt32 {
            UInt32(u16(index)) | UInt32(u16(index + 2)) << 16
        }

        var blocks: [Block] = []
        for index in 0..<numBlocks {
            let start = bodyStart + index * blockLength
            let count = Int(bytes[start])
            guard count <= 50 else { return nil }
            func detector(metadata: Int, data: Int) -> Detector {
                let samples: [Int32?] = (0..<count).map { index in
                    let sample = Int32(bitPattern: u32(data + index * 4))
                    return (-524_288...524_287).contains(sample) ? sample : nil
                }
                return Detector(selector: bytes[metadata], range: u32(metadata + 1),
                                offset: Int16(bitPattern: u16(metadata + 5)), samples: samples)
            }
            blocks.append(Block(sourceA: bytes[start + 1], driveA: u16(start + 2),
                                sourceB: bytes[start + 4], driveB: u16(start + 5),
                                detectorA: detector(metadata: start + 7, data: start + 21),
                                detectorB: detector(metadata: start + 14, data: start + 221),
                                reserved: bytes[start + 421]))
        }
        let rate = u16(15)
        return Gen5V20Record(header: header, rawBody: Array(bytes[13...]),
                             sampleRateHz: rate == 0 ? nil : rate, blocks: blocks)
    }
}

/// Counts frame observations within a drain, including any repeated records.
struct Gen5V20DrainQuality: Equatable {
    private(set) var frames = 0
    private(set) var invalidSamples = 0
    private(set) var saturatedSamples = 0
    private(set) var flatlineSlots = 0

    mutating func record(_ frame: Gen5V20Record) {
        frames += 1
        for block in frame.blocks {
            for slot in [block.detectorA, block.detectorB] {
                invalidSamples += slot.samples.filter { $0 == nil }.count
                saturatedSamples += slot.saturatedSampleCount
                if slot.isFlatline { flatlineSlots += 1 }
            }
        }
    }
}
