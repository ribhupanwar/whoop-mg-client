import Foundation

/// WHOOP Gen5 v22 research / diagnostic telemetry (OpenStrap gen5_records.dart).
/// Revision 22 emits a 176-byte inner payload with body byte 0 (inner[13]) selecting one of
/// six tagged layouts (wide optical, dual-window optical, embedded PIP ring record, or 3-axis accel).
/// This is research telemetry, NOT a 1 Hz biometric summary, and must never enter HRV or sleep analysis.
struct Gen5V22Record: Equatable {
    static let version = 22
    static let innerLength = 176
    static let knownTags: Set<UInt8> = [1, 2, 3, 4, 5, 6]
    static let tagOffset = 13

    let header: BandRecordHeader
    let tag: UInt8
    let rawBody: [UInt8]

    var hasKnownLayout: Bool { Self.knownTags.contains(tag) }

    static func decode(_ bytes: [UInt8]) -> Gen5V22Record? {
        guard bytes.count == innerLength, bytes[0] == 0x2F, bytes[1] == version,
              let header = V18Decoder.header(of: bytes) else { return nil }
        return Gen5V22Record(
            header: header,
            tag: bytes[tagOffset],
            rawBody: Array(bytes[tagOffset..<innerLength])
        )
    }
}
