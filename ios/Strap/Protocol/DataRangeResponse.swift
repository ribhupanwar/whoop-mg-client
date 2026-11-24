import Foundation

/// Parsed response body for WHOOP 5.0 / MG GET_DATA_RANGE (opcode 0x22 / 34).
/// Wire geometry: 65 bytes in the command response body starting at inner[5].
public struct DataRangeResponse: Equatable {
    public static let bodyLength = 65
    public static let minPlausibleUnix = 1_600_000_000
    public static let maxPlausibleUnix = 2_500_000_000

    public let revision: UInt8
    public let rawOldPage: UInt32
    public let readPage: UInt32
    public let writePage: UInt32
    public let trimPage: UInt32
    public let wrapCount: UInt32
    public let totalPages: UInt32
    public let usedRecords: UInt32
    public let freeRecords: UInt32
    public let oldestUnix: Int?
    public let trimUnix: Int?
    public let currentReadUnix: Int?
    public let newestUnix: Int?

    /// Number of pages between trim pointer and write pointer, accounting for ring buffer wrap.
    public var pagesBehind: Int {
        guard totalPages > 0 else { return 0 }
        let w = Int(writePage)
        let t = Int(trimPage)
        if w >= t {
            return w - t
        } else {
            return (w + Int(totalPages)) - t
        }
    }

    public var isEmpty: Bool {
        newestUnix == nil || pagesBehind == 0
    }

    private static func parseUnix(_ val: UInt32) -> Int? {
        let v = Int(val)
        guard v >= minPlausibleUnix, v <= maxPlausibleUnix else { return nil }
        return v
    }

    public static func decode(_ body: [UInt8]) -> DataRangeResponse? {
        guard body.count >= bodyLength else { return nil }

        let rev = body[0]
        func u32le(_ offset: Int) -> UInt32 {
            UInt32(body[offset]) |
            (UInt32(body[offset + 1]) << 8) |
            (UInt32(body[offset + 2]) << 16) |
            (UInt32(body[offset + 3]) << 24)
        }

        let rawOld = u32le(1)
        let readP = u32le(5)
        let writeP = u32le(9)
        let trimP = u32le(13)
        let wrapC = u32le(17)
        let totalP = u32le(21)
        let usedRec = u32le(25)
        let freeRec = u32le(29)

        let oldest = parseUnix(u32le(33))
        let trim = parseUnix(u32le(41))
        let curRead = parseUnix(u32le(49))
        let newest = parseUnix(u32le(57))

        return DataRangeResponse(
            revision: rev,
            rawOldPage: rawOld,
            readPage: readP,
            writePage: writeP,
            trimPage: trimP,
            wrapCount: wrapC,
            totalPages: totalP,
            usedRecords: usedRec,
            freeRecords: freeRec,
            oldestUnix: oldest,
            trimUnix: trim,
            currentReadUnix: curRead,
            newestUnix: newest
        )
    }
}
