import XCTest
@testable import Strap

final class LiveHeartRateStateTests: XCTestCase {
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
    func testStandardWireValueIsPreservedButImplausibleHRIsNeverLive() {
        XCTAssertEqual(StandardHeartRate.parse(Data([0, 82]))?.heartRate, 82)
        let decoded = StandardHeartRate.parse(Data([1, 0xff, 0xff]))?.heartRate
        XCTAssertEqual(decoded, 65535, "The SIG parser preserves the actual 16-bit wire value")
        XCTAssertNil(LiveHeartRateState.fresh(decoded, receivedAt: Date(), connected: true, now: Date()))
        XCTAssertNil(StandardHeartRate.parse(Data([8, 82])), "Missing declared energy bytes")
    }
}
