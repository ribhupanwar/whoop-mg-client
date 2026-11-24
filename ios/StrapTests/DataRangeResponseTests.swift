import XCTest
@testable import Strap

final class DataRangeResponseTests: XCTestCase {
    private func makePayload(
        rev: UInt8 = 1,
        rawOld: UInt32 = 10,
        readP: UInt32 = 20,
        writeP: UInt32 = 130,
        trimP: UInt32 = 100,
        wrapC: UInt32 = 0,
        totalP: UInt32 = 131072,
        usedRec: UInt32 = 5000,
        freeRec: UInt32 = 80000,
        oldestS: UInt32 = 1780000000,
        trimS: UInt32 = 1781000000,
        readS: UInt32 = 1782000000,
        newestS: UInt32 = 1786000000
    ) -> [UInt8] {
        var body = [UInt8]()
        body.append(rev)
        func appendU32(_ v: UInt32) {
            body.append(UInt8(v & 0xFF))
            body.append(UInt8((v >> 8) & 0xFF))
            body.append(UInt8((v >> 16) & 0xFF))
            body.append(UInt8((v >> 24) & 0xFF))
        }
        appendU32(rawOld)
        appendU32(readP)
        appendU32(writeP)
        appendU32(trimP)
        appendU32(wrapC)
        appendU32(totalP)
        appendU32(usedRec)
        appendU32(freeRec)
        appendU32(oldestS); appendU32(0)
        appendU32(trimS); appendU32(0)
        appendU32(readS); appendU32(0)
        appendU32(newestS); appendU32(0)
        return body
    }

    func testDecodeValidPayload() {
        let payload = makePayload()
        guard let res = DataRangeResponse.decode(payload) else {
            XCTFail("Failed to decode valid payload")
            return
        }
        XCTAssertEqual(res.revision, 1)
        XCTAssertEqual(res.writePage, 130)
        XCTAssertEqual(res.trimPage, 100)
        XCTAssertEqual(res.pagesBehind, 30)
        XCTAssertEqual(res.oldestUnix, 1780000000)
        XCTAssertEqual(res.newestUnix, 1786000000)
        XCTAssertFalse(res.isEmpty)
    }

    func testPagesBehindRingWrap() {
        let payload = makePayload(writeP: 5, trimP: 131070, totalP: 131072)
        guard let res = DataRangeResponse.decode(payload) else {
            XCTFail("Failed to decode wrapped payload")
            return
        }
        XCTAssertEqual(res.pagesBehind, 7)
    }

    func testShortPayloadReturnsNil() {
        XCTAssertNil(DataRangeResponse.decode([1, 2, 3]))
    }

    func testSentinelNewestReturnsNil() {
        let payload = makePayload(newestS: 0xFFFFFFFF)
        guard let res = DataRangeResponse.decode(payload) else {
            XCTFail("Failed to decode sentinel payload")
            return
        }
        XCTAssertNil(res.newestUnix)
        XCTAssertTrue(res.isEmpty)
    }
}
