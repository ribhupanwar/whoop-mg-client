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

    static func declaredLength(_ bytes: ArraySlice<UInt8>) -> Int? {
        guard bytes.count >= 4 else { return nil }
        let start = bytes.startIndex
        return Int(bytes[start + 2]) | (Int(bytes[start + 3]) << 8)
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
        parse(frame[...])
    }

    static func parse(_ frame: ArraySlice<UInt8>) -> [UInt8]? {
        guard frame.count >= headerLength else { return nil }
        let start = frame.startIndex
        guard frame[start] == startOfFrame else { return nil }
        let storedHeaderCRC = UInt16(frame[start + 6]) | (UInt16(frame[start + 7]) << 8)
        guard BandChecksums.crc16Modbus(frame[start..<(start + 6)]) == storedHeaderCRC else { return nil }
        guard let declared = declaredLength(frame), declared >= 4 else { return nil }
        let total = headerLength + declared
        guard frame.count >= total else { return nil }
        let body = frame[(start + headerLength)..<(start + total)]
        guard body.count >= 4 else { return nil }
        let payload = Array(body[body.startIndex..<(body.endIndex - 4)])
        let tail = body.endIndex - 4
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
    private var cursor: Int = 0
    private(set) var droppedBytes = 0
    private(set) var badFrames = 0

    var pending: Int { buffer.count - cursor }

    func feed(_ chunk: [UInt8]) -> [[UInt8]] {
        buffer.append(contentsOf: chunk)
        var frames: [[UInt8]] = []
        while buffer.count - cursor >= Gen5Frame.headerLength {
            let start = cursor
            if buffer[start] != Gen5Frame.startOfFrame {
                cursor += 1
                droppedBytes += 1
                continue
            }
            let headerCRC = UInt16(buffer[start + 6]) | (UInt16(buffer[start + 7]) << 8)
            guard BandChecksums.crc16Modbus(buffer[start..<(start + 6)]) == headerCRC else {
                cursor += 1
                droppedBytes += 1
                badFrames += 1
                continue
            }
            guard let declared = Gen5Frame.declaredLength(buffer[start..<(start + 4)]) else { break }
            let total = Gen5Frame.headerLength + declared
            if declared < 4 || total > 65_535 {
                cursor += 1
                droppedBytes += 1
                continue
            }
            if buffer.count - cursor < total { break }
            let candidate = buffer[cursor..<(cursor + total)]
            if let inner = Gen5Frame.parse(candidate) {
                cursor += total
                frames.append(inner)
            } else {
                cursor += 1
                droppedBytes += 1
                badFrames += 1
            }
        }
        if cursor == buffer.count {
            buffer.removeAll(keepingCapacity: true)
            cursor = 0
        } else if cursor >= 4096 || (cursor >= 512 && cursor > buffer.count / 2) {
            buffer.removeSubrange(0..<cursor)
            cursor = 0
        }
        return frames
    }
}
