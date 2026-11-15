import XCTest
@testable import Strap

final class BandHapticsTests: XCTestCase {
    func testAlarmTimestampAndWaveformAreInsideChecksummedGen5Frame() throws {
        let date = Date(timeIntervalSince1970: 0x12345678)
        let body = try XCTUnwrap(BandHaptics.alarmBody(at: date))
        XCTAssertEqual(body.count, 20)
        XCTAssertEqual(Array(body.prefix(8)), [4, 1, 0x78, 0x56, 0x34, 0x12, 0, 0])
        XCTAssertEqual(Array(body.suffix(12)), [0x2F, 0x98, 0, 0, 0, 0, 0, 0, 0, 0, 7, 30])
        let payload = [UInt8(0x23), 9, BandHaptics.alarmOpcode] + body
        let decoded = try XCTUnwrap(Gen5Frame.parse(Gen5Frame.build(payload)))
        XCTAssertEqual(Array(decoded.prefix(payload.count)), payload)
        XCTAssertEqual(decoded.count % 4, 0)
    }
    func testBuzzIsOneBoundedPulseAndCancelUsesCapturedGen5Form() {
        XCTAssertEqual(BandHaptics.buzzBody, [1, 0x2F, 0x98, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(BandHaptics.disableBody, [2, 0xFF])
        XCTAssertNil(BandHaptics.alarmBody(at: Date(timeIntervalSince1970: -1)))
    }
    func testNextWakeMovesPastAlreadyElapsedAlarmAndSurvivesDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 8)))
        let next = try XCTUnwrap(BandHaptics.nextWake(minutes: 7 * 60, after: now, calendar: calendar))
        let parts = calendar.dateComponents([.day, .hour, .minute], from: next)
        XCTAssertEqual(parts.day, 8)
        XCTAssertEqual(parts.hour, 7)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertEqual(next.timeIntervalSince(now), 22 * 3600)
        XCTAssertNil(BandHaptics.nextWake(minutes: 1440, after: now, calendar: calendar))
    }
}
