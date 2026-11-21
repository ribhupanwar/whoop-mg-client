import XCTest
@testable import Strap

final class LiveHeartRateStateTests: XCTestCase {
    func testSilentPulseDoesNotReconnectAnActiveHistoryOrHandshakeLink() {
        let now = Date(timeIntervalSince1970: 1_000)
        let connected = now.addingTimeInterval(-240)
        XCTAssertEqual(LiveHeartRateState.recovery(
            now: now, connectedAt: connected, receivedAt: nil, lastAttempt: nil,
            attempts: 4, reconnects: 0, protectsHistoryLink: true
        ), .wait)
        XCTAssertEqual(LiveHeartRateState.recovery(
            now: now, connectedAt: connected, receivedAt: nil, lastAttempt: nil,
            attempts: 4, reconnects: 0
        ), .reconnect)
    }

    func testFreshnessNeverPromotesOldDisconnectedInvalidOrFutureReadings() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(LiveHeartRateState.fresh(82, receivedAt: now, connected: true, now: now), 82)
        XCTAssertNil(LiveHeartRateState.fresh(82, receivedAt: now.addingTimeInterval(-806), connected: true, now: now))
        XCTAssertNil(LiveHeartRateState.fresh(82, receivedAt: now, connected: false, now: now))
        XCTAssertNil(LiveHeartRateState.fresh(0, receivedAt: now, connected: true, now: now))
        XCTAssertNil(LiveHeartRateState.fresh(300, receivedAt: now, connected: true, now: now))
        XCTAssertNil(LiveHeartRateState.fresh(82, receivedAt: now.addingTimeInterval(1), connected: true, now: now))
        XCTAssertNil(LiveHeartRateState.fresh(82, receivedAt: nil, connected: true, now: now))
    }
    func testNeverReceivedFirstPacketStillRecoversAndExhaustedRearmsReconnect() {
        let connected = Date(timeIntervalSince1970: 1000)
        let now = connected.addingTimeInterval(806)
        XCTAssertEqual(LiveHeartRateState.recovery(now: now, connectedAt: connected, receivedAt: nil,
            lastAttempt: nil, attempts: 0, reconnects: 0), .rearm)
        XCTAssertEqual(LiveHeartRateState.recovery(now: now, connectedAt: connected, receivedAt: connected,
            lastAttempt: connected.addingTimeInterval(200), attempts: 4, reconnects: 0), .reconnect)
        XCTAssertEqual(LiveHeartRateState.recovery(now: now, connectedAt: connected, receivedAt: nil,
            lastAttempt: nil, attempts: 4, reconnects: 2), .unavailable)
        XCTAssertEqual(LiveHeartRateState.recovery(now: now, connectedAt: connected, receivedAt: now,
            lastAttempt: nil, attempts: 4, reconnects: 0), .wait)
        XCTAssertEqual(LiveHeartRateState.recovery(now: now, connectedAt: connected, receivedAt: connected,
            lastAttempt: now.addingTimeInterval(-20), attempts: 1, reconnects: 0), .wait)
    }
    func testIndicatorMovesUpWithHigherBPMAndClampsAtFixedScaleEdges() {
        XCTAssertLessThan(LiveHeartRateState.indicatorFraction(bpm: 60), LiveHeartRateState.indicatorFraction(bpm: 150))
        XCTAssertEqual(LiveHeartRateState.indicatorFraction(bpm: 25), 0)
        XCTAssertEqual(LiveHeartRateState.indicatorFraction(bpm: 230), 1)
    }
    func testType40OffsetsRRUnitsAndHistoryExclusion() {
        var frame: [UInt8] = [0x28, 0, 0, 0, 0, 0, 0, 0, 82, 2, 0x84, 0x03, 0x8e, 0x03]
        XCTAssertEqual(Type40HeartRate.parse(frame), Type40HeartRate.Reading(bpm: 82, rrMS: [900, 910]))
        frame[0] = 0x2f
        XCTAssertNil(Type40HeartRate.parse(frame), "A historical packet is not a live packet")
        frame[0] = 0x28; frame[8] = 0
        XCTAssertNil(Type40HeartRate.parse(frame))
        frame[8] = 82; frame[9] = 9
        XCTAssertEqual(Type40HeartRate.parse(frame)?.rrMS, [], "Malformed RR must not synthesize beats")
        XCTAssertEqual(Type40HeartRate.parse(Array(frame.prefix(9)))?.bpm, 82)
        XCTAssertNil(Type40HeartRate.parse(Array(frame.prefix(8))))
    }
    func testType40RRBoundariesAndTruncatedPayloadDoNotInventBeats() {
        // Synthetic protocol fixtures: assert parser safety, not device-level validation.
        let prefix: [UInt8] = [0x28, 0, 0, 0, 0, 0, 0, 0, 82]
        let fourBeats = prefix + [4, 0xC8, 0x00, 0x20, 0x03, 0xB8, 0x0B, 0xB9, 0x0B]
        XCTAssertEqual(Type40HeartRate.parse(fourBeats)?.rrMS, [200, 800, 3000])
        XCTAssertEqual(Type40HeartRate.parse(fourBeats)?.bpm, 82)

        // A declared RR count with insufficient bytes must not return partial beats.
        XCTAssertEqual(Type40HeartRate.parse(Array(fourBeats.dropLast()))?.rrMS, [])
        XCTAssertEqual(Type40HeartRate.parse(Array(fourBeats.dropLast()))?.bpm, 82)

        // Out-of-range intervals and an unsupported count must not become HRV inputs.
        XCTAssertEqual(Type40HeartRate.parse(prefix + [1, 0xC7, 0x00])?.rrMS, [])
        XCTAssertEqual(Type40HeartRate.parse(prefix + [5] + [UInt8](repeating: 0, count: 10))?.rrMS, [])
    }

    func testType40ZeroCountAndInvalidIntervalsKeepOnlyMeasuredBPM() {
        let prefix: [UInt8] = [0x28, 0, 0, 0, 0, 0, 0, 0, 82]
        XCTAssertEqual(Type40HeartRate.parse(prefix + [0])?.rrMS, [])
        // Zero, 199 ms, and 3001 ms are not valid measured RR intervals.
        let invalid = prefix + [3, 0x00, 0x00, 0xC7, 0x00, 0xB9, 0x0B]
        XCTAssertEqual(Type40HeartRate.parse(invalid)?.rrMS, [])
        XCTAssertEqual(Type40HeartRate.parse(invalid)?.bpm, 82)
        // A malformed RR count must not discard a separately valid live HR.
        XCTAssertEqual(Type40HeartRate.parse(prefix + [255])?.bpm, 82)
        XCTAssertEqual(Type40HeartRate.parse(prefix + [255])?.rrMS, [])
    }

    func testType40DoesNotTreatHistoryOrInvalidHeartRateAsLive() {
        let frame: [UInt8] = [0x28, 0, 0, 0, 0, 0, 0, 0, 82, 1, 0x20, 0x03]
        XCTAssertEqual(Type40HeartRate.parse(frame)?.rrMS, [800])
        var history = frame
        history[0] = 0x2F
        XCTAssertNil(Type40HeartRate.parse(history))
        var noHeartRate = frame
        noHeartRate[8] = 0
        XCTAssertNil(Type40HeartRate.parse(noHeartRate))
        noHeartRate[8] = 231
        XCTAssertNil(Type40HeartRate.parse(noHeartRate))
    }

    func testStandardWireValueIsPreservedButImplausibleHRIsNeverLive() {
        XCTAssertEqual(StandardHeartRate.parse(Data([0, 82]))?.heartRate, 82)
        let decoded = StandardHeartRate.parse(Data([1, 0xff, 0xff]))?.heartRate
        XCTAssertEqual(decoded, 65535, "The SIG parser preserves the actual 16-bit wire value")
        XCTAssertNil(LiveHeartRateState.fresh(decoded, receivedAt: Date(), connected: true, now: Date()))
        XCTAssertNil(StandardHeartRate.parse(Data([8, 82])), "Missing declared energy bytes")
    }
}
