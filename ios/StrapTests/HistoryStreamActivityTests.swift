import XCTest
@testable import Strap

final class HistoryStreamActivityTests: XCTestCase {
    func testRawType52KeepsHistoryAliveWithoutBecomingBiometricData() {
        var activity = HistoryStreamActivity()
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(activity.receive(type: BandPacket.historicalData, at: start))
        XCTAssertTrue(activity.receive(type: 0x34, at: start.addingTimeInterval(10)))
        XCTAssertEqual(start.addingTimeInterval(11).timeIntervalSince(activity.lastReceivedAt!), 1,
                       "A continuing raw IMU stream must not look like eleven seconds of idle history")
        XCTAssertEqual(activity.unmappedType52Frames, 1)
        XCTAssertFalse(activity.receive(type: BandPacket.realtimeData, at: start.addingTimeInterval(20)))
        XCTAssertEqual(activity.lastReceivedAt, start.addingTimeInterval(10))
        XCTAssertEqual(activity.unmappedType52Frames, 1)
        XCTAssertTrue(activity.receive(type: BandPacket.metadata, at: start.addingTimeInterval(21)))
        XCTAssertEqual(activity.lastReceivedAt, start.addingTimeInterval(21))
        activity = HistoryStreamActivity()
        XCTAssertNil(activity.lastReceivedAt); XCTAssertEqual(activity.unmappedType52Frames, 0)
    }
}
