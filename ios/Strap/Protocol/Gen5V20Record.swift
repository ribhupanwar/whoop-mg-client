import Foundation

/// WHOOP Gen5 v20 raw optical deep buffer (OpenStrap gen5_records.dart / NOOP Whoop5RawOptical).
/// Carries five 422/423-byte optical blocks (AFE channel configurations + 20-bit photodiode ADC samples).
/// This is raw optical telemetry, NOT a 1 Hz biometric summary, and must never enter HRV or sleep analysis.
struct Gen5V20Record: Equatable {
    static let version = 20
    static let innerLength = 2128
    static let numBlocks = 5
    static let blockLength = 423
    static let bodyStart = 13

    let header: BandRecordHeader
    let rawBody: [UInt8]

    static func decode(_ bytes: [UInt8]) -> Gen5V20Record? {
        guard bytes.count == innerLength, bytes[0] == 0x2F, bytes[1] == version,
              let header = V18Decoder.header(of: bytes) else { return nil }
        return Gen5V20Record(header: header, rawBody: Array(bytes[bodyStart..<innerLength]))
    }
}
