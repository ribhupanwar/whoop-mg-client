import Foundation

/// Decoded WHOOP 5.0 / MG command response (`0x24` / `0x26`) from `FD4B0003`.
struct BandCommandResult: Equatable, Codable {
    let responseType: UInt8
    let responseSequence: UInt8
    let commandOpcode: UInt8
    let originSequence: UInt8
    let resultCode: UInt8
    let receivedAt: Date

    var isSuccess: Bool { resultCode == 0x01 }

    var commandName: String {
        switch commandOpcode {
        case 0x03: return "REALTIME_HR"
        case 0x0E: return "BROADCAST_HR"
        case 0x13: return "BUZZ"
        case 0x16: return "SEND_HISTORICAL_DATA"
        case 0x17: return "HISTORICAL_DATA_ACK"
        case 0x1D: return "REBOOT_STRAP"
        case 0x22: return "GET_DATA_RANGE"
        case 0x42: return "SET_ALARM"
        case 0x45: return "DISABLE_ALARM"
        case 0x91: return "CLIENT_HELLO"
        default: return String(format: "CMD_0x%02X", commandOpcode)
        }
    }

    static func decode(_ inner: [UInt8], now: Date = Date()) -> BandCommandResult? {
        guard inner.count >= 5, inner[0] == 0x24 || inner[0] == 0x26 else { return nil }
        return BandCommandResult(
            responseType: inner[0],
            responseSequence: inner[1],
            commandOpcode: inner[2],
            originSequence: inner[3],
            resultCode: inner[4],
            receivedAt: now
        )
    }
}
