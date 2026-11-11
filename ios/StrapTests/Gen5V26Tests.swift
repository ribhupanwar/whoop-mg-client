import XCTest
@testable import Strap

final class Gen5V26Tests: XCTestCase {
    func testValidWaveformIsNotHeartRateOrRR() {
        var bytes = [UInt8](repeating: 0, count: 76)
        bytes[0] = 0x2F
        bytes[1] = 26
        bytes[3] = 42
        bytes[7] = 100
        bytes[19] = 0xFF
        bytes[20] = 0xFF
        let waveform = Gen5V26Record.decode(bytes)
        XCTAssertEqual(waveform?.header.recordIndex, 42)
        XCTAssertEqual(waveform?.opticalDeltas.count, 24)
        XCTAssertEqual(waveform?.opticalDeltas.first, -1)
        XCTAssertNil(V18Decoder.decode(bytes))
    }

    func testTruncatedAndWrongVersionRejected() {
        var bytes = [UInt8](repeating: 0, count: 76)
        bytes[0] = 0x2F
        bytes[1] = 26
        XCTAssertNil(Gen5V26Record.decode(Array(bytes.dropLast())))
        bytes[1] = 18
        XCTAssertNil(Gen5V26Record.decode(bytes))
    }
}
