import Foundation

/// Checksums for the gen5 wire format. Polynomials are protocol facts, not
/// implementation choices: crc16/modbus guards the 8-byte header and crc32
/// guards the payload.
enum BandChecksums {
    private static let crc32Table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    /// CRC-32 (zlib polynomial, reflected, init/xorout 0xFFFFFFFF).
    static func crc32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = crc32Table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        crc32(bytes[...])
    }

    /// CRC-16/MODBUS: reflected poly 0xA001, init 0xFFFF, no xorout.
    static func crc16Modbus(_ bytes: ArraySlice<UInt8>) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc
    }

    static func crc16Modbus(_ bytes: [UInt8]) -> UInt16 {
        crc16Modbus(bytes[...])
    }
}
