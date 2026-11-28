import XCTest
@testable import Strap

/// Diagnostic for skin temperature -5000 and zero raw values under the existing decoder.
///
/// Production behavior (V18Decoder.temp, V18Record.swift:349-358; records.py:290-295):
///   - raw 0 → nil (explicit sentinel rejection)
///   - raw -5000 → decodes to -50.0 °C, then rejected by (-20…80) °C plausibility → nil
///   - NightTemperature.funnel then counts nil as rejectedMissingTemperature
///
/// Native evidence (SENSOR_NATIVE_RE_REPORT.md §5.3):
///   - V18 inner[65:67] = signed i16 / 100 °C, -5000 sentinel = unavailable.
///
/// These tests pin existing production behavior so it cannot silently regress.
final class NightTemperatureDiagnosticTests: XCTestCase {

    /// -5000 raw decodes to nil skinTempC (not -50.0 °C), matching production.
    func testMinus5000RawDecodesToNil() {
        let inner = v18InnerWithSkinTempRaw(-5000)
        let sample = try XCTUnwrap(V18Decoder.decode(inner))
        XCTAssertNil(sample.skinTempC, "-5000 (-50.00 C) sentinel must decode to nil")
    }

    /// Zero raw decodes to nil skinTempC (not 0.0 °C), matching production.
    func testZeroRawDecodesToNil() {
        let inner = v18InnerWithSkinTempRaw(0)
        let sample = try XCTUnwrap(V18Decoder.decode(inner))
        XCTAssertNil(sample.skinTempC, "zero raw must decode to nil, not 0.0 °C")
    }

    /// Valid skin temperatures decode unchanged.
    func testValidSkinTemperaturesDecodeCorrectly() {
        let sample30 = try XCTUnwrap(V18Decoder.decode(v18InnerWithSkinTempRaw(3060)))
        XCTAssertEqual(sample30.skinTempC, 30.6, accuracy: 0.01)

        let sample22 = try XCTUnwrap(V18Decoder.decode(v18InnerWithSkinTempRaw(2250)))
        XCTAssertEqual(sample22.skinTempC, 22.5, accuracy: 0.01)
    }

    /// NightTemperature.funnel with nil session returns empty (early return).
    func testFunnelWithNilSessionReturnsEmpty() {
        let unavailable = try XCTUnwrap(V18Decoder.decode(v18InnerWithSkinTempRaw(-5000)))
        let valid = try XCTUnwrap(V18Decoder.decode(v18InnerWithSkinTempRaw(3060)))

        let result = NightTemperature.funnel([unavailable, valid], session: nil)
        XCTAssertFalse(result.hasSession)
        XCTAssertEqual(result.inputRecords, 2)
        XCTAssertEqual(result.eligibleSeconds, 0)
        XCTAssertNil(result.candidateCelsius)
    }

    /// NightTemperature.funnel counts -5000 and zero as rejectedMissingTemperature.
    func testFunnelCountsSentinelAsMissingTemperature() throws {
        let session = SleepSession(
            version: 11,
            sourceStartUnix: 1_700_000_000,
            startUnix: 1_700_000_000,
            endUnix: 1_700_000_000 + 3600,
            staging: .unavailable,
            heartRate: [],
            movementBouts: 0,
            isEdited: false
        )
        let sentinel = try XCTUnwrap(V18Decoder.decode(v18InnerWithSkinTempRaw(-5000)))
        let zero = try XCTUnwrap(V18Decoder.decode(v18InnerWithSkinTempRaw(0)))
        let valid = try XCTUnwrap(V18Decoder.decode(v18InnerWithSkinTempRaw(3060)))

        let result = NightTemperature.funnel([sentinel, zero, valid], session: session)
        XCTAssertEqual(result.rejectedMissingTemperature, 2)
        XCTAssertEqual(result.eligibleSeconds, 1)
        XCTAssertEqual(result.candidateCelsius, 30.6)
    }

    /// NightTemperature.funnel range gate rejects out-of-range valid temps.
    func testFunnelRangeGateStillRejectsOutOfRange() throws {
        let session = SleepSession(
            version: 11,
            sourceStartUnix: 1_700_000_000,
            startUnix: 1_700_000_000,
            endUnix: 1_700_000_000 + 3600,
            staging: .unavailable,
            heartRate: [],
            movementBouts: 0,
            isEdited: false
        )
        let tooCold = V18Sample(
            header: BandRecordHeader(version: 18, flags: 0, recordIndex: 1, unix: 1_700_000_000, subsecQ15: 0),
            heartRate: 60,
            rrIntervalsMS: [800],
            dynamicAccelG: 0.01,
            gravityXG: nil,
            gravityYG: nil,
            gravityZG: nil,
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
    var inner = [UInt8](repeating: 0, count: 112)
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
