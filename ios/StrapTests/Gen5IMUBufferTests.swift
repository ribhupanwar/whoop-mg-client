import XCTest
@testable import Strap

final class Gen5IMUBufferTests: XCTestCase {
    private func fixture(type: UInt8 = 0x2F, version: UInt8 = 21) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 1232)
        bytes[0] = type; bytes[1] = version; bytes[3] = 42; bytes[7] = 99
        bytes[16] = 2; bytes[622] = 1
        bytes[21] = 0x10 // +4096 = 1 g
        bytes[22] = 0; bytes[23] = 0xF0 // -4096 = -1 g
        bytes[633] = 0x40 // +16384 = 1000 dps
        bytes[635] = 0x7F // unused stale sample must not appear
        return bytes
    }
    func testDeclaredCountsSignedAxesAndIndependentVersionShape() throws {
        for type in [UInt8(0x2F), 0x2B] {
            let decoded = try XCTUnwrap(Gen5IMUBuffer.decode(fixture(type: type, version: 18)))
            XCTAssertEqual(decoded.version, 18)
            XCTAssertEqual(decoded.recordIndex, 42); XCTAssertEqual(decoded.unix, 99)
            XCTAssertEqual(decoded.accelerationG[0], [1, -1])
            XCTAssertEqual(decoded.accelerationG[1], [0, 0])
            XCTAssertEqual(decoded.angularVelocityDPS[0], [1000])
        }
    }
    func testMalformedCountsLengthsAndUnverifiedPacketRoutesRejected() {
        for count in [UInt8(0), 101, 255] {
            var bytes = fixture(); bytes[16] = count
            XCTAssertNil(Gen5IMUBuffer.decode(bytes))
            bytes = fixture(); bytes[622] = count
            XCTAssertNil(Gen5IMUBuffer.decode(bytes))
        }
        XCTAssertNil(Gen5IMUBuffer.decode(Array(fixture().dropLast())))
        XCTAssertNil(Gen5IMUBuffer.decode(fixture() + [0]))
        XCTAssertNil(Gen5IMUBuffer.decode(fixture(type: 0x34)))
        XCTAssertNil(V18Decoder.decode(fixture()))
    }

    func testIMURhythmWindowRejectsWrongVersionAndHandlesWrapAndReplay() {
        func fullBlock(version: UInt8 = 21, unix: UInt32, index: UInt32) -> Gen5IMUBuffer {
            let x = (0..<100).map { i in 1.0 + 0.3 * sin(2 * Double.pi * Double(i) / 50.0) }
            let zero = [Double](repeating: 0, count: 100)
            return Gen5IMUBuffer(
                version: version, recordIndex: index, unix: unix,
                rawSubsecond: 0, accelerationG: [x, zero, zero], angularVelocityDPS: [zero, zero, zero]
            )
        }

        var window = IMURhythmWindow()
        for offset in 0..<5 {
            window.ingest(fullBlock(version: 21, unix: UInt32(100 + offset), index: UInt32.max - 3 &+ UInt32(offset)))
        }
        // Wrong version must reset window instead of producing candidate.
        window.ingest(fullBlock(version: 18, unix: 105, index: 2))
        XCTAssertNil(window.candidate)

        // Continuous 6-second run across UInt32.max wrap must produce candidate;
        // replayed older unix must not reset or overwrite.
        for offset in 0..<6 {
            window.ingest(fullBlock(version: 21, unix: UInt32(200 + offset), index: UInt32.max - 2 &+ UInt32(offset)))
        }
        let firstCandidate = window.candidate
        XCTAssertNotNil(firstCandidate)
        window.ingest(fullBlock(version: 21, unix: 199, index: 999))
        XCTAssertEqual(window.candidate, firstCandidate)
    }
}
