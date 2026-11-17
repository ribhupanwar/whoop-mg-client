import Foundation

/// Envelope-level history liveness only. Type 52 is known to be a historical
/// IMU stream; its body is not decoded or passed into biometric analysis.
struct HistoryStreamActivity {
    private(set) var lastReceivedAt: Date?
    private(set) var unmappedType52Frames = 0
    mutating func receive(type: UInt8, at date: Date) -> Bool {
        guard type == BandPacket.historicalData || type == BandPacket.metadata || type == 0x34 else { return false }
        lastReceivedAt = date
        if type == 0x34 { unmappedType52Frames += 1 }
        return true
    }
}
