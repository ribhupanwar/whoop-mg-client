import Foundation
import CoreBluetooth

/// Gen5 GATT identifiers plus the standard SIG services the strap exposes.
/// The proprietary service requires the CLIENT_HELLO write; the standard
/// heart-rate and battery services do not.
enum BandUUID {
    static let service = CBUUID(string: "fd4b0001-cce1-4033-93ce-002d5875f58a")
    static let commandTo = CBUUID(string: "fd4b0002-cce1-4033-93ce-002d5875f58a")
    static let commandFrom = CBUUID(string: "fd4b0003-cce1-4033-93ce-002d5875f58a")
    static let events = CBUUID(string: "fd4b0004-cce1-4033-93ce-002d5875f58a")
    static let data = CBUUID(string: "fd4b0005-cce1-4033-93ce-002d5875f58a")
    static let memfault = CBUUID(string: "fd4b0007-cce1-4033-93ce-002d5875f58a")

    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")
    static let deviceInfoService = CBUUID(string: "180A")

    static let notifiable: [CBUUID] = [commandFrom, events, data, memfault]
}

/// Command opcodes observed on gen5 hardware. 0x0F (FORGET_BONDS) is
/// destructive and is deliberately absent: nothing here can send it.
enum BandCommand: UInt8 {
    case realtimeHROn = 0x03
    case setGenericHRProfile = 0x0E
    case abortHistoricalTransmits = 0x14
    case sendHistoricalData = 0x16
    case historicalDataResult = 0x17
    case getDataRange = 0x22
    case clientHello = 0x91
}

enum BandPacket {
    static let command: UInt8 = 0x23
    static let realtimeData: UInt8 = 0x28
    static let historicalData: UInt8 = 0x2F
    static let metadata: UInt8 = 0x31
    /// HISTORY_END sub-opcode inside a METADATA frame.
    static let historyEnd: UInt8 = 0x02
}
