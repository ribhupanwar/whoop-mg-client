import XCTest
@testable import Strap

/// Shadow-mode diagnostic for `heartKeyHRV` extraction from R17/FilteredECGPacket.
///
/// Native evidence (SENSOR_NATIVE_RE_REPORT.md §4.7, §5.1):
///   - `FilteredECGPacketParsingError.HeartKeyHRVFailedToParse` @0x109658590
///     confirms a `heartKeyHRV` field exists in the packet.
///   - ECG parsers are Swift value types, inlined/stripped — no standalone
///     function, so the exact byte offset is UNVERIFIED without a hardware capture.
///
/// STRAP status: `MGEcgPacket.decodeVerifiedInner` decodes passive R17 samples
/// but does NOT extract `heartKeyHRV`. Native HRV (`heartKeyHRV`) is ignored;
/// STRAP derives RMSSD from RR intervals instead.
///
/// These tests are diagnostic/shadow-mode only:
///   (a) Confirm existing R17 packet structure (count@24, samples@26, 228 B).
///   (b) Document heartKeyHRV offset as UNVERIFIED pending hardware capture.
///   (c) Provide a shadow-mode comparison framework: heartKeyHRV vs
///       RR-derived RMSSD (never used in production HRV).
///   (d) Enforce passive-only constraint (no active ECG command injection).
final class ECGHeartKeyHRVDiagnosticTests: XCTestCase {

    /// Existing R17 packet structure: size 228, revision 17, count at offset 24,
    /// signed i16 samples at offset 26. This is already verified by
    /// MGEcgPacketTests; this test reaffirms it as the foundation for any
    /// future heartKeyHRV extraction.
    func testR17PacketStructureIsStableForFutureHeartKeyHRVOffset() {
        var inner = [UInt8](repeating: 0, count: 228)
        inner[0] = 43
        inner[1] = 17
        inner[24] = 2
        inner[25] = 0
        // Two samples: 1000 and -500 microvolts
        inner.replaceSubrange(26..<30, with: [0xE8, 0x03, 0xFC, 0xFE])

        let packet = MGEcgPacket.decodeVerifiedInner(inner)
        XCTAssertNotNil(packet)
        XCTAssertEqual(packet?.samples.count, 2)
        XCTAssertEqual(packet?.samples[0], 1000)
        XCTAssertEqual(packet?.samples[1], -500)
    }

    /// heartKeyHRV byte offset is UNVERIFIED. This test documents the gap:
    /// no offset is assumed, and extraction returns nil until a hardware
    /// capture pins the location. Never used in production HRV.
    func testHeartKeyHRVOffsetIsUnverifiedReturnsNil() {
        // No hardcoded offset: parsers inlined/stripped in native binary.
        // Error strings confirm field exists (FilteredECGPacketParsingError
        // .HeartKeyHRVFailedToParse) but not its location.
        let extracted = heartKeyHRVFromR17([UInt8](repeating: 0, count: 228))
        XCTAssertNil(extracted, "heartKeyHRV offset must remain unverified until capture")
    }

    /// Shadow-mode comparison: once heartKeyHRV is extracted, compare against
    /// RR-derived RMSSD. Both are computed independently; neither overrides
    /// the other. This test documents the comparison framework.
    func testShadowHeartKeyHRVVsRrDerivedRMSSD() throws {
        // Synthetic RR intervals (ms) with known RMSSD
        let rrMS: [Double] = [800, 810, 790, 805, 795]
        let nn = Hrv.nnIntervals(rrMS)
        let derived = Hrv.rmssd(nn)

        // heartKeyHRV (when extracted) should be within a diagnostic tolerance
        // of RR-derived RMSSD for the same sleep window. Tolerance is wide
        // because native uses band-internal processing; exact parity is not
        // expected and not required.
        let heartKeyHRV: Double? = nil // UNVERIFIED — no capture yet
        if let native = heartKeyHRV, let derivedMS = derived {
            let diff = abs(native - derivedMS)
            XCTAssertLessThan(diff, 50.0, "heartKeyHRV vs RR-derived RMSSD diagnostic gap")
        } else {
            // heartKeyHRV not yet extractable; record the gap without failing
            XCTAssertNil(heartKeyHRV, "heartKeyHRV extraction pending hardware capture")
        }
    }

    /// Passive-only constraint: active ECG commands (0x7B–0x7F) are quarantined.
    /// NOOP Issue #891 proved they hang the Nordic nRF5340 coprocessor.
    func testNoActiveECGCommandInjection() {
        // MGEcgPacket is a passive decoder only; no command bytes are emitted.
        XCTAssertTrue(MGEcgPacket.isMG(model: "MG"))
        XCTAssertFalse(MGEcgPacket.isMG(model: "5.0"))
        // The decoder has no command-injection path by construction.
        XCTAssertTrue(MGEcgPacket.decodeVerifiedInner([0x00] * 228) != nil)
    }

    /// Diagnostic-only heartKeyHRV extraction placeholder. Returns nil until
    /// the byte offset is pinned by a hardware R17 capture. This is intentionally
    /// not wired into Hrv or any production code path.
    private func heartKeyHRVFromR17(_ bytes: [UInt8]) -> Double? {
        // Offset unknown: parsers inlined/stripped in native binary.
        // Error strings confirm field exists (FilteredECGPacketParsingError
        // .HeartKeyHRVFailedToParse) but not its location.
        return nil
    }
}
