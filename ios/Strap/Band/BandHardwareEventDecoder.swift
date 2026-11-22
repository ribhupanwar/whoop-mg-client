import Foundation

/// Four-state wearing/contact status of the strap.
enum WristContactState: String, Equatable, Codable, CaseIterable {
    case unknown
    case onWrist
    case offWrist
    case uncertain
}

/// Decoded hardware event from Gen5 / MG events characteristic (fd4b0004).
struct BandHardwareEventPacket: Equatable {
    let rawOpcode: UInt8
    let event: BandHardwareEvent?
    let timestamp: UInt32?
    let payload: [UInt8]

    var isKnown: Bool { event != nil }

    init(rawOpcode: UInt8, event: BandHardwareEvent?, timestamp: UInt32?, payload: [UInt8]) {
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
    static func decode(_ inner: [UInt8]) -> BandHardwareEventPacket? {
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

/// Decoded telemetry status envelope packet from Gen5 / MG hardware.
///
/// Encodes battery state-of-charge in tenths of percent (Ghidra 0x10bc3d110 / 0x10a3c4c30),
/// charging status, and 16-bit capacitive/optical wrist contact state (0x10a3cd4f0).
struct WhoopStatusPacket: Equatable {
    let rawBatteryTenths: Int?
    let batteryPercent: Double?
    let isCharging: Bool?
    let wristStateRaw: UInt16?
    let contactState: WristContactState

    init(
        rawBatteryTenths: Int?,
        batteryPercent: Double?,
        isCharging: Bool?,
        wristStateRaw: UInt16?,
        contactState: WristContactState
    ) {
        self.rawBatteryTenths = rawBatteryTenths
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.wristStateRaw = wristStateRaw
        self.contactState = contactState
    }

    /// Decode status envelope from inner bytes.
    ///
    /// Gen5 Type 48 (0x30) Battery/Status Event:
    /// - inner[0] == 0x30 (EVENT)
    /// - inner[2] == 0x03 (Battery & Status Event)
    /// - inner[13..14] == SoC in tenths of percent (UInt16 LE)
    /// - inner[15] == charging bit / status (bit 0 = charging)
    /// - inner[16..17] == wristState bitfield (UInt16 LE):
    ///     - bit 0 (0x0001): capacitive touch contact
    ///     - bit 1 (0x0002): optical PPG reflectance contact
    ///     - bit 2 (0x0004): on-body placement validity
    static func decode(_ inner: [UInt8]) -> WhoopStatusPacket? {
        guard !inner.isEmpty else { return nil }

        if inner[0] == 0x30, inner.count >= 3, inner[2] == 0x03 {
            var tenths: Int? = nil
            var batteryPct: Double? = nil
            var charging: Bool? = nil
            var wristRaw: UInt16? = nil
            var contact: WristContactState = .unknown

            if inner.count >= 15 {
                let soc = Int(inner[13]) | (Int(inner[14]) << 8)
                tenths = soc
                let pct = Double(soc) / 10.0
                if (0.0...100.0).contains(pct) {
                    batteryPct = pct
                }
            }
            if inner.count >= 16 {
                charging = (inner[15] & 0x01) != 0
            }
            if inner.count >= 18 {
                let raw = UInt16(inner[16]) | (UInt16(inner[17]) << 8)
                wristRaw = raw
                if (raw & 0x0001) != 0 || (raw & 0x0002) != 0 {
                    contact = .onWrist
                } else if raw == 0 {
                    contact = .offWrist
                } else {
                    contact = .uncertain
                }
            } else if inner.count >= 15 {
                // If wristState is truncated but battery is valid
                contact = .unknown
            }
            return WhoopStatusPacket(
                rawBatteryTenths: tenths,
                batteryPercent: batteryPct,
                isCharging: charging,
                wristStateRaw: wristRaw,
                contactState: contact
            )
        }
        return nil
    }
}
