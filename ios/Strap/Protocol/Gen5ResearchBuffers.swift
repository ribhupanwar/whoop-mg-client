import Foundation

/// Verified optical geometry only; amplitudes are not calibrated measurements.
/// Facts: OpenStrap/protocol fbadb5b, gen5_records.dart. Original frames remain
/// the recovery source; no optical bytes enter the V18 HR/RR analysis path.
struct Gen5OpticalBuffer: Equatable {
    struct Block: Equatable {
        let metadata: [UInt8]
        let detectorA: [Int32]
        let detectorB: [Int32]
    }
    let header: BandRecordHeader
    let declaredSampleRateHz: UInt16
    let blocks: [Block]
    static func decode(_ bytes: [UInt8]) -> Gen5OpticalBuffer? {
        guard bytes.count == 2128, bytes[0] == 0x2F, bytes[1] == 20,
              let header = V18Decoder.header(of: bytes) else { return nil }
        let counts = (0..<5).map { Int(bytes[18 + $0 * 422]) }
        guard counts.allSatisfy({ $0 <= 50 }) else { return nil }
        func sample(_ offset: Int) -> Int32 {
            let raw = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
                UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
            let masked = Int32(raw & 0xFFFFF)
            return masked & 0x80000 == 0 ? masked : masked - 0x100000
        }
        let blocks = (0..<5).map { block -> Block in
            let start = 18 + block * 422
            return Block(metadata: Array(bytes[(start + 1)..<(start + 21)]),
                detectorA: (0..<counts[block]).map { sample(start + 21 + $0 * 4) },
                detectorB: (0..<counts[block]).map { sample(start + 221 + $0 * 4) })
        }
        return Gen5OpticalBuffer(header: header, declaredSampleRateHz: UInt16(bytes[15]) | UInt16(bytes[16]) << 8, blocks: blocks)
    }
}

/// Research framing and original body only. A known layout tag is not proof
/// of physiological validity; unnamed fields stay unnamed and uninterpreted.
struct Gen5ResearchBuffer: Equatable {
    let header: BandRecordHeader
    let tag: UInt8
    let originalBody: [UInt8]
    var hasDocumentedLayout: Bool { (1...6).contains(tag) }
    static func decode(_ bytes: [UInt8]) -> Gen5ResearchBuffer? {
        guard bytes.count == 176, bytes[0] == 0x2F, bytes[1] == 22,
              let header = V18Decoder.header(of: bytes) else { return nil }
        return Gen5ResearchBuffer(header: header, tag: bytes[13], originalBody: Array(bytes[13...]))
    }
}
