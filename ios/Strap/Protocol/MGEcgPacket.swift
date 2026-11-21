import Foundation

/// Passive filtered R17 observations. Layout documented in NOOP PROTOCOL_ECG.md
/// at 2a1de7609843b095505274ad6fc811757210be80. Values retain native units.
struct MGEcgPacket: Equatable {
    let samples: [Int16]

    static func isMG(model: String?) -> Bool {
        model?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "MG"
    }

    /// Input must come from the Gen5 reassembler after both CRC checks.
    static func decodeVerifiedInner(_ bytes: [UInt8]) -> Self? {
        guard bytes.count == 228, bytes[1] == 17,
              bytes[0] == 43 || bytes[0] == 47,
              bytes[226] == 0, bytes[227] == 0 else { return nil }
        let count = Int(bytes[24]) | Int(bytes[25]) << 8
        guard count <= 100 else { return nil }

        let samples = (0..<count).map { index -> Int16 in
            let offset = 26 + index * 2
            return Int16(bitPattern: UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8)
        }
        return Self(samples: samples)
    }
}
