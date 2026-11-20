import XCTest
@testable import Strap

final class AppOpenStreakTests: XCTestCase {
    func testGapResetsCurrentButPreservesBestAndFutureDatesDoNotCount() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20))!
        let streak = AppOpenStreak(keys: [
            "2026-11-13", "2026-11-14", "2026-11-15", "2026-11-19",
            "2026-11-19", "2026-11-20", "2026-11-21",
        ], today: today, calendar: calendar)
        XCTAssertEqual(streak.current, 2)
        XCTAssertEqual(streak.best, 3)
        XCTAssertEqual(streak.start, calendar.date(byAdding: .day, value: -1, to: today))
        XCTAssertEqual(streak.week.count, 7)
        XCTAssertEqual(streak.week.filter { $0.date > today && $0.opened }.count, 0)
    }

    func testYesterdayRemainsCurrentUntilTodayHasPassed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20))!
        XCTAssertEqual(AppOpenStreak(keys: ["2026-11-19"], today: today, calendar: calendar).current, 1)
        XCTAssertEqual(AppOpenStreak(keys: ["2026-11-18"], today: today, calendar: calendar).current, 0)
    }
}
