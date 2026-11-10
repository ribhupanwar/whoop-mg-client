import Foundation

/// Gen5 frame envelope: 8-byte header, word-padded inner, trailing crc32.
///
/// Header: [0xAA][0x01][declared u16 LE][dir marker x2][crc16-modbus LE].
/// declared = padded inner length + 4, and the frame ends with a crc32 over
/// the padded inner. Reassembly is driven by the declared length, never by
/// scanning for 0xAA: sensor payloads are full of 0xAA bytes.
enum Gen5Frame {
    static let headerLength = 8
    static let startOfFrame: UInt8 = 0xAA

    static func padded(_ inner: [UInt8]) -> [UInt8] {
        let remainder = inner.count % 4
        guard remainder != 0 else { return inner }
        return inner + [UInt8](repeating: 0, count: 4 - remainder)
    }

    static func declaredLength(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        return Int(bytes[2]) | (Int(bytes[3]) << 8)
    }

    static func build(_ inner: [UInt8]) -> [UInt8] {
        let payload = padded(inner)
        let declared = payload.count + 4
        var frame = [UInt8](repeating: 0, count: headerLength)
        frame[0] = startOfFrame
        frame[1] = 0x01
        frame[2] = UInt8(declared & 0xFF)
        frame[3] = UInt8((declared >> 8) & 0xFF)
        frame[4] = 0x00
        frame[5] = 0x01
        let headerCRC = BandChecksums.crc16Modbus(frame[0..<6])
        frame[6] = UInt8(headerCRC & 0xFF)
        frame[7] = UInt8(headerCRC >> 8)
        frame.append(contentsOf: payload)
        let payloadCRC = BandChecksums.crc32(payload)
        frame.append(UInt8(payloadCRC & 0xFF))
        frame.append(UInt8((payloadCRC >> 8) & 0xFF))
        frame.append(UInt8((payloadCRC >> 16) & 0xFF))
        frame.append(UInt8((payloadCRC >> 24) & 0xFF))
        return frame
    }

    /// Returns the padded inner, or nil when either checksum fails.
    static func parse(_ frame: [UInt8]) -> [UInt8]? {
        guard frame.count >= headerLength, frame[0] == startOfFrame else { return nil }
        let storedHeaderCRC = UInt16(frame[6]) | (UInt16(frame[7]) << 8)
        guard BandChecksums.crc16Modbus(frame[0..<6]) == storedHeaderCRC else { return nil }
        guard let declared = declaredLength(frame), declared >= 4 else { return nil }
        let total = headerLength + declared
        guard frame.count >= total else { return nil }
        let body = Array(frame[headerLength..<total])
        guard body.count >= 4 else { return nil }
        let payload = Array(body[0..<(body.count - 4)])
        let tail = body.count - 4
        let stored = UInt32(body[tail])
            | (UInt32(body[tail + 1]) << 8)
            | (UInt32(body[tail + 2]) << 16)
            | (UInt32(body[tail + 3]) << 24)
        guard BandChecksums.crc32(payload) == stored else { return nil }
        return payload
    }
}

final class FrameReassembler {
    private var buffer: [UInt8] = []
    private(set) var droppedBytes = 0
    private(set) var badFrames = 0

    var pending: Int { buffer.count }

    func feed(_ chunk: [UInt8]) -> [[UInt8]] {
        buffer.append(contentsOf: chunk)
        var frames: [[UInt8]] = []
        while true {
            guard buffer.count >= Gen5Frame.headerLength else { break }
            if buffer[0] != Gen5Frame.startOfFrame {
                buffer.removeFirst()
                droppedBytes += 1
                continue
            }
            guard let declared = Gen5Frame.declaredLength(buffer) else { break }
            let total = Gen5Frame.headerLength + declared
            if declared < 4 || total > 65_535 {
                buffer.removeFirst()
                droppedBytes += 1
                continue
            }
            if buffer.count < total { break }
            let candidate = Array(buffer[0..<total])
            buffer.removeFirst(total)
            if let inner = Gen5Frame.parse(candidate) {
                frames.append(inner)
            } else {
                badFrames += 1
            }
        }
        return frames
    }
}
