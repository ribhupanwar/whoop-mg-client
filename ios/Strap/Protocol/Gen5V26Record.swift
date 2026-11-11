import Foundation

/// WHOOP Gen5 v26 optical PPG waveform (OpenStrap gen5_records.dart).
/// This is NOT a heart-rate or R-R record and must never enter HRV analysis.
struct Gen5V26Record: Equatable {
    let header: BandRecordHeader
    let pipStateCounter: UInt16
    let firstSampleADC: Int32
    let opticalDeltas: [Int16]
    let channelStateWord: UInt16
    let primaryFlagsByte: UInt8
    let morphologyByte: UInt8
    let alignedTailByte: UInt8

    static func decode(_ bytes: [UInt8]) -> Gen5V26Record? {
        guard bytes.count == 76, bytes[0] == 0x2F, bytes[1] == 26,
              let header = V18Decoder.header(of: bytes) else { return nil }
        func u16(_ i: Int) -> UInt16 {
            UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8)
        }
        func u32(_ i: Int) -> UInt32 {
            UInt32(bytes[i]) | (UInt32(bytes[i + 1]) << 8) |
                (UInt32(bytes[i + 2]) << 16) | (UInt32(bytes[i + 3]) << 24)
        }
        let deltas: [Int16] = (0..<24).map {
            Int16(bitPattern: u16(19 + 2 * $0))
        }
        return Gen5V26Record(
            header: header, pipStateCounter: u16(13),
            firstSampleADC: Int32(bitPattern: u32(15)),
            opticalDeltas: deltas, channelStateWord: u16(71),
            primaryFlagsByte: bytes[73], morphologyByte: bytes[74],
            alignedTailByte: bytes[75])
    }
}
