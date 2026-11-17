import Foundation

/// Shape identified from OpenStrap protocol facts (fbadb5b, gen5_records.dart).
/// Motion diagnostics only: no HR, RR, wear, sleep-stage or oxygen interpretation.
struct Gen5IMUBuffer: Equatable {
    let version: UInt8
    let recordIndex: UInt32
    let unix: UInt32
    let rawSubsecond: UInt16
    let accelerationG: [[Double]]
    let angularVelocityDPS: [[Double]]

    static func decode(_ bytes: [UInt8]) -> Gen5IMUBuffer? {
        // Only packet routes verified by the reference. Type 0x34 has no
        // established framing here and must remain a retained raw frame.
        guard bytes.count == 1232, bytes[0] == 0x2F || bytes[0] == 0x2B else { return nil }
        func word(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8 }
        func dword(_ offset: Int) -> UInt32 { UInt32(word(offset)) | UInt32(word(offset + 2)) << 16 }
        let accelCount = Int(word(16)), gyroCount = Int(word(622))
        guard (1...100).contains(accelCount), (1...100).contains(gyroCount) else { return nil }
        func axes(_ offsets: [Int], count: Int, scale: Double) -> [[Double]] {
            offsets.map { offset in
                (0..<count).map { index in Double(Int16(bitPattern: word(offset + index * 2))) * scale }
            }
        }
        return Gen5IMUBuffer(version: bytes[1], recordIndex: dword(3), unix: dword(7),
            rawSubsecond: word(11), accelerationG: axes([20, 220, 420], count: accelCount, scale: 1.0 / 4096),
            angularVelocityDPS: axes([632, 832, 1032], count: gyroCount, scale: 2000.0 / 32768))
    }
}
