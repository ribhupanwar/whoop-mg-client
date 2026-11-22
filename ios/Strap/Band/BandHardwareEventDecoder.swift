import Foundation

/// Tri-state wearing/contact status of the strap.
public enum WristContactState: String, Equatable, Codable {
    case unknown
    case onWrist
    case offWrist
}

/// Decoded hardware event from Gen5 / MG events characteristic (fd4b0004).
public struct BandHardwareEventPacket: Equatable {
    public let rawOpcode: UInt8
    public let event: BandHardwareEvent?
    public let timestamp: UInt32?
    public let payload: [UInt8]

    public init(rawOpcode: UInt8, event: BandHardwareEvent?, timestamp: UInt32?, payload: [UInt8]) {
        self.rawOpcode = rawOpcode
        self.event = event
        self.timestamp = timestamp
        self.payload = payload
    }

    /// Decode inner payload after CRC-validated Format-1 frame extraction.
    ///
    /// Gen5 Format-1 EVENT packet (inner[0] == 0x30 / 48):
    /// - inner[0] == 0x30 (EVENT packet type)
    /// - inner[1] == flags / sub-type (e.g. 0x34 or 0x03)
    /// - inner[2] == event opcode (0x09 wristOn, 0x0A wristOff, 0x0E doubleTap, 0x15 batteryPackConnected, 0x16 batteryPackRemoved, 0x17 bleBonded)
    /// - inner[3] == status / secondary byte
    /// - inner[4..7] == 4-byte real Unix timestamp (little-endian)
    /// - inner[8...] == optional payload (e.g. battery percent, mV)
    public static func decode(_ inner: [UInt8]) -> BandHardwareEventPacket? {
        guard !inner.isEmpty else { return nil }
        if inner[0] == 0x30 {
            guard inner.count >= 3 else { return nil }
            let opcode = inner[2]
            var ts: UInt32? = nil
            if inner.count >= 8 {
                ts = UInt32(inner[4])
                    | (UInt32(inner[5]) << 8)
                    | (UInt32(inner[6]) << 16)
                    | (UInt32(inner[7]) << 24)
            }
            let payload = inner.count > 8 ? Array(inner.dropFirst(8)) : []
            return BandHardwareEventPacket(
                rawOpcode: opcode,
                event: BandHardwareEvent(rawValue: opcode),
                timestamp: ts,
                payload: payload
            )
        } else {
            // Direct/legacy single-byte event notification fallback
            let opcode = inner[0]
            let payload = inner.count > 1 ? Array(inner.dropFirst(1)) : []
            return BandHardwareEventPacket(
                rawOpcode: opcode,
                event: BandHardwareEvent(rawValue: opcode),
                timestamp: nil,
                payload: payload
            )
        }
    }
}
