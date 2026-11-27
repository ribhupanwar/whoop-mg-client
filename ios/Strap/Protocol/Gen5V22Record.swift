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

    struct OpticalWindow: Equatable {
        let innerOffset: Int
        let firstADC: Int32
        let deltas: [Int16]
        var firstAmbiguousIndex: Int? {
            deltas.firstIndex { $0 == Int16.min || $0 == Int16.max }.map { $0 + 1 }
        }
        var approximateCodes: [Int64] {
            var code = Int64(firstADC)
            var result = [code]
            for delta in deltas {
                code += Int64(delta)
                result.append(code)
            }
            return result
        }
    }

    struct TaggedFields: Equatable {
        let windows: [OpticalWindow]
        let embeddedUnix: UInt32?
        let motionDeltaRaw: Double?
        let channelStateRaw: UInt16?
        let primaryFlagsRaw: UInt8?
        let accelerationAxesG: [[Double]]
    }

    /// Capture-backed layouts 1...6 from OpenStrap. Treat a nonzero
    /// subversion as opaque. In particular, tag 5 carries the earlier PIP
    /// record's timestamp and must not reuse metadata from its stale tail.
    var taggedFields: TaggedFields? {
        guard rawBody.count == 163, rawBody[1] == 0, Self.knownTags.contains(tag) else { return nil }
        func byte(_ inner: Int) -> UInt8 { rawBody[inner - 13] }
        func u16(_ inner: Int) -> UInt16 {
            UInt16(byte(inner)) | UInt16(byte(inner + 1)) << 8
        }
        func u32(_ inner: Int) -> UInt32 {
            UInt32(u16(inner)) | UInt32(u16(inner + 2)) << 16
        }
        func float(_ inner: Int) -> Double? {
            let value = Double(Float(bitPattern: u32(inner)))
            return value.isFinite ? value : nil
        }
        func window(_ offset: Int, _ count: Int) -> OpticalWindow {
            let deltas = (0..<count).map { Int16(bitPattern: u16(offset + 4 + 2 * $0)) }
            return OpticalWindow(innerOffset: offset, firstADC: Int32(bitPattern: u32(offset)), deltas: deltas)
        }
        switch tag {
        case 1, 2, 4:
            return TaggedFields(windows: [window(15, 49)], embeddedUnix: nil,
                                motionDeltaRaw: float(121), channelStateRaw: u16(137),
                                primaryFlagsRaw: byte(143), accelerationAxesG: [])
        case 3:
            return TaggedFields(windows: [window(15, 24), window(67, 24)], embeddedUnix: nil,
                                motionDeltaRaw: float(123), channelStateRaw: u16(139),
                                primaryFlagsRaw: byte(145), accelerationAxesG: [])
        case 5:
            return TaggedFields(windows: [window(23, 24)], embeddedUnix: u32(15),
                                motionDeltaRaw: float(75), channelStateRaw: u16(79),
                                primaryFlagsRaw: byte(81), accelerationAxesG: [])
        case 6:
            let axes = [18, 68, 118].map { start in
                (0..<25).map { Double(Int16(bitPattern: u16(start + 2 * $0))) / 4096.0 }
            }
            return TaggedFields(windows: [], embeddedUnix: nil, motionDeltaRaw: nil,
                                channelStateRaw: nil, primaryFlagsRaw: nil, accelerationAxesG: axes)
        default:
            return nil
        }
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
