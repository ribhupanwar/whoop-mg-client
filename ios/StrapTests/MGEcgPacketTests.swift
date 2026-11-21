import XCTest
@testable import Strap

final class MGEcgPacketTests: XCTestCase {
    func testCapabilityRequiresTheConnectedDevicesDISModel() {
        XCTAssertTrue(MGEcgPacket.isMG(model: " MG\n"))
        XCTAssertFalse(MGEcgPacket.isMG(model: nil))
        XCTAssertFalse(MGEcgPacket.isMG(model: "WHOOP MG"))
        XCTAssertFalse(MGEcgPacket.isMG(model: "5.0"))
    }

    private func inner(type: UInt8 = 43) -> [UInt8] {
        var inner = [UInt8](repeating: 0, count: 228)
        inner[0] = type
        inner[1] = 17
        inner[24] = 3
        inner.replaceSubrange(26..<32, with: [0, 0, 0xFF, 0xFF, 52, 18])
        return inner
    }

    func testFragmentedR17FrameYieldsOnlyDeclaredSignedSamples() throws {
        let frame = Gen5Frame.build(inner())
        let framer = FrameReassembler()
        XCTAssertTrue(framer.feed(Array(frame.prefix(33))).isEmpty)
        let verified = try XCTUnwrap(framer.feed(Array(frame.dropFirst(33))).first)
        XCTAssertEqual(MGEcgPacket.decodeVerifiedInner(verified)?.samples, [0, -1, 0x1234])
        XCTAssertNotNil(MGEcgPacket.decodeVerifiedInner(inner(type: 47)))
    }

    func testZeroCountAndAlignmentBytesAreNeverWaveformSamples() {
        var bytes = inner()
        bytes[24] = 0
        XCTAssertEqual(MGEcgPacket.decodeVerifiedInner(bytes)?.samples, [])
        bytes[227] = 1
        XCTAssertNil(MGEcgPacket.decodeVerifiedInner(bytes))
    }

    func testRejectsWrongRevisionCountAndCRC() {
        var bytes = inner()
        bytes[1] = 16
        XCTAssertNil(MGEcgPacket.decodeVerifiedInner(bytes))
        bytes = inner()
        bytes[24] = 101
        XCTAssertNil(MGEcgPacket.decodeVerifiedInner(bytes))
        var frame = Gen5Frame.build(inner())
        frame[frame.count - 1] ^= 1
        XCTAssertTrue(FrameReassembler().feed(frame).isEmpty)
    }
}
