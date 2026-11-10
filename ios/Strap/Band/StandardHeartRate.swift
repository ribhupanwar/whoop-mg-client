import Foundation

/// Standard Bluetooth SIG heart-rate measurement (0x2A37). The proprietary
/// gen5 stream carries history; this is the live path, available after the
/// band's generic HR profile is enabled.
enum StandardHeartRate {
    /// Flags: bit0 uint16 HR, bit3 energy expended, bit4 R-R present.
    static func parse(_ data: Data) -> (heartRate: Int, rrMS: [Int])? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }
        let flags = bytes[0]
        var index = 1
        let heartRate: Int
        if flags & 0x01 == 0 {
            heartRate = Int(bytes[index])
            index += 1
        } else {
            guard bytes.count >= 3 else { return nil }
            heartRate = Int(bytes[1]) | (Int(bytes[2]) << 8)
            index = 3
        }
        if flags & 0x08 != 0 { index += 2 }
        var rrMS: [Int] = []
        if flags & 0x10 != 0 {
            while index + 1 < bytes.count {
                let raw = Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
                index += 2
                // The SIG unit is 1/1024 s. Values outside a plausible R-R
                // window are artefacts, not beats.
                let ms = Int((Double(raw) * 1000.0 / 1024.0).rounded())
                if ms >= V18Decoder.minRRMS && ms <= V18Decoder.maxRRMS {
                    rrMS.append(ms)
                }
            }
        }
        return (heartRate, rrMS)
    }
}
