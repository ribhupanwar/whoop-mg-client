import XCTest
@testable import Strap

/// Diagnostic for skin temperature -5000 raw behavior under the existing decoder.
///
/// Native evidence (SENSOR_NATIVE_RE_REPORT.md §5.3):
///   - V18 inner[65:67] = signed i16 / 100 °C, **-5000 sentinel** = unavailable.
///   - OpenStrap Dart confirms signed decode and -5000 = unavailable.
///
/// STRAP existing behavior: skin temp decoded as signed i16/100 °C with a
/// (20…43) °C range gate in NightTemperature.funnel. -5000 raw decodes to
/// -50.0 °C and is rejected by the range gate as rejectedInvalidTemperature.
/// The sentinel is not explicitly distinguished from other out-of-range values.
///
/// These tests are diagnostic/regression: they pin existing behavior so it
/// cannot silently regress, and document the gap where -5000 is conflated
/// with genuinely out-of-range readings rather than classified as missing.
final class NightTemperatureDiagnosticTests: XCTestCase {

    /// -5000 raw decodes to -50.0 °C (not nil), then rejected by the funnel
    /// range gate as rejectedInvalidTemperature, not rejectedMissingTemperature.
    func testMinus5000RawDecodesToMinus50CAndIsRejectedAsInvalid() {
        let inner = v18InnerWithSkinTempRaw(-5000)
        let sample = try XCTUnwrap(V18Decoder.decode(inner))
        XCTAssertEqual(sample.skinTempC, -50.0, accuracy: 0.01)
    }

    /// Valid skin temperatures decode unchanged.
    func testValidSkinTemperaturesDecodeCorrectly() {
        let sample30 = try XCTUnwrap(V18Decoder.decode(v18InnerWithSkinTempRaw(3060)))
        XCTAssertEqual(sample30.skinTempC, 30.6, accuracy: 0.01)

        let sample22 = try XCTUnwrap(V18Decoder.decode(v18InnerWithSkinTempRaw(2250)))
        XCTAssertEqual(sample22.skinTempC, 22.5, accuracy: 0.01)

        let sample0 = try XCTUnwrap(V18Decoder.decode(v18InnerWithSkinTempRaw(0)))
        XCTAssertEqual(sample0.skinTempC, 0.0, accuracy: 0.01)
    }

    /// NightTemperature.funnel rejects -50.0 °C (from -5000 raw) as
    /// rejectedInvalidTemperature, counting it as invalid rather than missing.
    func testFunnelRejectsMinus5000AsInvalidTemperature() {
        let session = SleepSession(startUnix: 1_700_000_000, endUnix: 1_700_000_000 + 3600)
        let unavailable = try XCTUnwrap(V18Decoder.decode(v18InnerWithSkinTempRaw(-5000)))
        let valid = try XCTUnwrap(V18Decoder.decode(v18InnerWithSkinTempRaw(3060)))

        let result = NightTemperature.funnel([unavailable, valid], session: session)
        XCTAssertEqual(result.rejectedInvalidTemperature, 1)
        XCTAssertEqual(result.eligibleSeconds, 1)
        XCTAssertEqual(result.candidateCelsius, 30.6)
    }

    /// NightTemperature.funnel range gate rejects out-of-range valid temps.
    func testFunnelRangeGateStillRejectsOutOfRange() {
        let session = SleepSession(startUnix: 1_700_000_000, endUnix: 1_700_000_000 + 3600)
        let tooCold = V18Sample(
            header: BandRecordHeader(version: 18, flags: 0, recordIndex: 1, unix: 1_700_000_000, subsecQ15: 0),
            heartRate: 60,
            rrIntervalsMS: [800],
            dynamicAccelG: 0.01,
            skinTempC: 15.0,   // below 20 °C
            sleepStateByte: 0x20,
            sleepState: 2
        )
        let result = NightTemperature.funnel([tooCold], session: session)
        XCTAssertEqual(result.rejectedInvalidTemperature, 1)
        XCTAssertEqual(result.eligibleSeconds, 0)
        XCTAssertNil(result.candidateCelsius)
    }
}

// MARK: - Test fixtures (diagnostic only)

private func v18InnerWithSkinTempRaw(_ raw: Int) -> [UInt8] {
    var inner = [UInt8](repeating: 0, count: 109)
    inner[0] = 0x2F
    inner[1] = 18
    inner[2] = 0x80
    inner[3] = 0xE8
    inner[4] = 0x03
    inner[5] = 0x00
    inner[6] = 0x00
    inner[7] = 0xC1
    inner[8] = 0x53
    inner[9] = 0x65
    inner[10] = 0x00
    inner[11] = 0x00
    inner[12] = 0x00
    inner[14] = 65
    inner[15] = 1
    inner[16] = 0x20
    inner[17] = 0x03
    inner[33] = 0x0D
    inner[34] = 0x45
    inner[35] = 0x1C
    inner[36] = 0x3F
    inner[45] = 0x00
    inner[46] = 0x00
    inner[47] = 0x80
    inner[48] = 0x3F
    // raw as signed i16 LE at offset 65
    inner[65] = UInt8(truncatingIfNeeded: raw & 0xFF)
    inner[66] = UInt8(truncatingIfNeeded: (raw >> 8) & 0xFF)
    inner[73] = 0x20
    return inner
}

private struct SleepSession {
    let startUnix: Int
    let endUnix: Int
}
