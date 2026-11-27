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

    var hasKnownLayout: Bool { Self.knownTags.contains(tag) || queuedOptical != nil }

    /// R22 version 9/subversion 0: numeric channel identity, not wavelength.
    /// Reconstruction wraps modulo 2^32; rail deltas make the suffix ambiguous.
    struct QueuedOptical: Equatable {
        let channel: UInt8
        let sampleBits: [UInt32]
        let firstAmbiguousIndex: Int?
        let packedMetadata: UInt16
        var isRetainedChannel: Bool { channel != 0 }
    }

    var queuedOptical: QueuedOptical? {
        // rawBody begins at inner 13 (frame absolute 21).
        guard rawBody.count == 163, rawBody[0] == 9, rawBody[1] == 0,
              rawBody[120] <= 5 else { return nil }
        func u16(_ i: Int) -> UInt16 {
            UInt16(rawBody[i]) | UInt16(rawBody[i + 1]) << 8
        }
        var value = UInt32(u16(10)) | UInt32(u16(12)) << 16
        var samples = [value]
        var ambiguous: Int?
        for i in 0..<49 {
            let d = Int16(bitPattern: u16(14 + i * 2))
            if ambiguous == nil && (d == Int16.min || d == Int16.max) { ambiguous = i + 1 }
            value = value &+ UInt32(bitPattern: Int32(d))
            samples.append(value)
        }
        return QueuedOptical(channel: rawBody[120], sampleBits: samples,
                             firstAmbiguousIndex: ambiguous, packedMetadata: u16(116))
    }

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
