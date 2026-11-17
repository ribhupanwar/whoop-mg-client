import XCTest
@testable import Strap

final class Gen5ResearchBufferTests: XCTestCase {
    func testV20CountsSignedTwentyBitSamplesAndMetadataWithoutInventedBeats() throws {
        var bytes = [UInt8](repeating: 0, count: 2128)
        bytes[0] = 0x2F; bytes[1] = 20; bytes[15] = 25
        bytes[18] = 2; bytes[19] = 7
        bytes[39] = 0xFF; bytes[40] = 0xFF; bytes[41] = 0x07 // maximum positive 20-bit
        bytes[43] = 0x00; bytes[44] = 0x00; bytes[45] = 0x08 // minimum negative
        bytes[239] = 0xFF; bytes[240] = 0xFF; bytes[241] = 0x0F // -1
        let record = try XCTUnwrap(Gen5OpticalBuffer.decode(bytes))
        XCTAssertEqual(record.declaredSampleRateHz, 25); XCTAssertEqual(record.blocks.count, 5)
        XCTAssertEqual(record.blocks[0].detectorA, [524287, -524288])
        XCTAssertEqual(record.blocks[0].detectorB, [-1, 0]); XCTAssertEqual(record.blocks[0].metadata.first, 7)
        XCTAssertTrue(record.blocks[1].detectorA.isEmpty)
        XCTAssertNil(V18Decoder.decode(bytes)); XCTAssertNil(Gen5OpticalBuffer.decode(Array(bytes.dropLast())))
        bytes[18] = 51; XCTAssertNil(Gen5OpticalBuffer.decode(bytes))
    }
    func testV22UnknownTagsAndBodyRemainRawWithoutTypedClinicalFields() throws {
        var bytes = [UInt8](repeating: 0, count: 176); bytes[0] = 0x2F; bytes[1] = 22
        bytes[13] = 255; bytes[175] = 99
        let unknown = try XCTUnwrap(Gen5ResearchBuffer.decode(bytes))
        XCTAssertEqual(unknown.tag, 255); XCTAssertFalse(unknown.hasDocumentedLayout)
        XCTAssertEqual(unknown.originalBody, Array(bytes[13...]))
        bytes[13] = 6; XCTAssertTrue(try XCTUnwrap(Gen5ResearchBuffer.decode(bytes)).hasDocumentedLayout)
        XCTAssertNil(Gen5ResearchBuffer.decode(bytes + [0])); XCTAssertNil(Gen5ResearchBuffer.decode(Array(bytes.dropLast())))
        XCTAssertNil(V18Decoder.decode(bytes))
        bytes[0] = 0x34; XCTAssertNil(Gen5ResearchBuffer.decode(bytes))
    }
}
