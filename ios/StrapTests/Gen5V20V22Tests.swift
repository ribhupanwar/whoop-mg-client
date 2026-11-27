import XCTest
@testable import Strap

final class Gen5V20V22Tests: XCTestCase {
    func testGen5V20RecordDecodesValidBuffer() {
        var bytes = [UInt8](repeating: 0, count: 2128)
        bytes[0] = 0x2F
        bytes[1] = 20
        bytes[2] = 0x80
        // recordIndex = 999
        bytes[3] = 0xE7
        bytes[4] = 0x03
        // unix = 1_800_000_000
        let unix: UInt32 = 1_800_000_000
        bytes[7] = UInt8(unix & 0xFF)
        bytes[8] = UInt8((unix >> 8) & 0xFF)
        bytes[9] = UInt8((unix >> 16) & 0xFF)
        bytes[10] = UInt8((unix >> 24) & 0xFF)

        let record = Gen5V20Record.decode(bytes)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.header.version, 20)
        XCTAssertEqual(record?.header.recordIndex, 999)
        XCTAssertEqual(record?.header.unix, 1_800_000_000)
        XCTAssertEqual(record?.rawBody.count, 2128 - 13)

        // Must not decode as V18 biometric summary
        XCTAssertNil(V18Decoder.decode(bytes))
    }

    func testGen5V20FifthBlockSignedADCAndDrainQuality() throws {
        var bytes = [UInt8](repeating: 0, count: 2128)
        bytes[0] = 47
        bytes[1] = 20
        bytes[15] = 25
        let blockStart = 18 + 4 * 422
        bytes.replaceSubrange(blockStart..<(blockStart + 14),
                              with: [3, 2, 200, 0, 4, 0, 0, 3, 32, 0, 0, 0, 224, 252])
        let a = blockStart + 21
        bytes.replaceSubrange(a..<(a + 12),
                              with: [0, 0, 248, 255, 255, 255, 7, 0, 0, 0, 8, 0])
        let b = blockStart + 221
        bytes.replaceSubrange(b..<(b + 12), with: [7, 0, 0, 0, 7, 0, 0, 0, 7, 0, 0, 0])
        bytes[blockStart + 421] = 0xA5

        let record = try XCTUnwrap(Gen5V20Record.decode(bytes))
        XCTAssertEqual(record.sampleRateHz, 25)
        XCTAssertTrue(record.blocks[0].detectorA.samples.isEmpty)
        let block = record.blocks[4]
        XCTAssertEqual(block.sourceA, 2)
        XCTAssertEqual(block.driveA, 200)
        XCTAssertEqual(block.reserved, 0xA5)
        XCTAssertEqual(block.detectorA.selector, 3)
        XCTAssertEqual(block.detectorA.range, 32)
        XCTAssertEqual(block.detectorA.offset, -800)
        XCTAssertEqual(block.detectorA.samples, [-524_288, 524_287, nil])
        XCTAssertTrue(block.detectorB.isFlatline)
        var deep = NativeDeepTelemetry()
        XCTAssertTrue(deep.ingest(bytes))
        let quality = deep.opticalQuality
        XCTAssertEqual(quality.frames, 1)
        XCTAssertEqual(quality.invalidSamples, 1)
        XCTAssertEqual(quality.saturatedSamples, 2)
        XCTAssertEqual(quality.flatlineSlots, 1)
        bytes[blockStart] = 51
        XCTAssertNil(Gen5V20Record.decode(bytes))
    }

    func testGen5V20RejectsInvalidLengthOrVersion() {
        var bytes = [UInt8](repeating: 0, count: 2128)
        bytes[0] = 0x2F
        bytes[1] = 20
        XCTAssertNil(Gen5V20Record.decode(Array(bytes.dropLast())))
        bytes[1] = 18
        XCTAssertNil(Gen5V20Record.decode(bytes))
        bytes[1] = 20
        bytes[0] = 0x28
        XCTAssertNil(Gen5V20Record.decode(bytes))
    }

    func testGen5V22RecordDecodesValidTelemetry() {
        var bytes = [UInt8](repeating: 0, count: 176)
        bytes[0] = 0x2F
        bytes[1] = 22
        bytes[2] = 0x80
        bytes[3] = 42
        bytes[7] = 100
        bytes[13] = 3 // Tag 3

        let record = Gen5V22Record.decode(bytes)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.header.version, 22)
        XCTAssertEqual(record?.header.recordIndex, 42)
        XCTAssertEqual(record?.tag, 3)
        XCTAssertTrue(record?.hasKnownLayout == true)
        XCTAssertEqual(record?.rawBody.count, 176 - 13)

        // Must not decode as V18 biometric summary
        XCTAssertNil(V18Decoder.decode(bytes))
    }

    func testGen5V22RejectsInvalidLengthOrVersion() {
        var bytes = [UInt8](repeating: 0, count: 176)
        bytes[0] = 0x2F
        bytes[1] = 22
        XCTAssertNil(Gen5V22Record.decode(Array(bytes.dropLast())))
        bytes[1] = 18
        XCTAssertNil(Gen5V22Record.decode(bytes))
        bytes[1] = 22
        bytes[0] = 0x28
        XCTAssertNil(Gen5V22Record.decode(bytes))
    }

    func testGen5V26IncludesAccelDeltaG() {
        var bytes = [UInt8](repeating: 0, count: 76)
        bytes[0] = 0x2F
        bytes[1] = 26
        bytes[3] = 10
        bytes[7] = 20
        // Pack accel float at 67 (0.5g)
        let accelBytes = withUnsafeBytes(of: Float(0.5)) { Array($0) }
        for i in 0..<4 { bytes[67 + i] = accelBytes[i] }

        let record = Gen5V26Record.decode(bytes)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.accelDeltaG, 0.5)
    }
}
