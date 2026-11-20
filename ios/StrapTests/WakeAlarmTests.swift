import XCTest
@testable import Strap

final class WakeAlarmTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        WakeAlarm.isEnabled = false
        WakeAlarm.bandConfirmedEpoch = nil
    }

    func testUpgradePreservesExistingWakeTimeAndNeverOverwritesNewPreference() throws {
        let name = "WakeAlarmTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        WakeAlarm.restoreWakeTimeIfNeeded(6 * 60 + 40, defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: "strap.wake.alarm.minutes.v1"), 400)
        WakeAlarm.restoreWakeTimeIfNeeded(7 * 60, defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: "strap.wake.alarm.minutes.v1"), 400)
        XCTAssertNil(defaults.object(forKey: "strap.wake.alarm.enabled.v1"))
    }

    func testDefaultScheduleHasSevenDaysWithWakeMinutes() {
        WakeAlarm.wakeMinutes = 7 * 60 + 30 // 7:30 AM
        let defaultSched = WakeAlarm.defaultSchedule
        XCTAssertEqual(defaultSched.count, 7)
        for (idx, entry) in defaultSched.enumerated() {
            XCTAssertEqual(entry.weekday, idx + 1)
            XCTAssertTrue(entry.isEnabled)
            XCTAssertEqual(entry.wakeMinutes, 450)
            XCTAssertFalse(entry.weekdayName.isEmpty)
            XCTAssertFalse(entry.weekdayShort.isEmpty)
        }
    }

    func testUpdateScheduleUpdatesSpecificDay() {
        let sched = WakeAlarm.defaultSchedule
        WakeAlarm.schedule = sched

        // Update Wednesday (weekday 4) to 06:15 (375 mins)
        WakeAlarm.updateSchedule(weekday: 4, isEnabled: true, wakeMinutes: 375)
        let updated = WakeAlarm.schedule
        let wednesday = updated.first(where: { $0.weekday == 4 })
        XCTAssertNotNil(wednesday)
        XCTAssertEqual(wednesday?.wakeMinutes, 375)
        XCTAssertEqual(wednesday?.isEnabled, true)

        // Disable Sunday (weekday 1)
        WakeAlarm.updateSchedule(weekday: 1, isEnabled: false, wakeMinutes: 450)
        let reloaded = WakeAlarm.schedule
        let sunday = reloaded.first(where: { $0.weekday == 1 })
        XCTAssertEqual(sunday?.isEnabled, false)
    }

    func testNextWakeDateComputesCorrectUpcomingDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // Create a fixed reference date: Wednesday 2026-11-18 10:00:00 UTC
        let components = DateComponents(year: 2026, month: 11, day: 18, hour: 10, minute: 0, second: 0)
        let now = try XCTUnwrap(calendar.date(from: components))

        // Set up schedule where Wednesday is 7:00 AM (already past), Thursday is 6:45 AM (upcoming tomorrow)
        WakeAlarm.isEnabled = true
        var schedule: [DayAlarmSchedule] = []
        for d in 1...7 {
            // Thursday is day 5 in gregorian (Sun=1, Mon=2, Tue=3, Wed=4, Thu=5, Fri=6, Sat=7)
            schedule.append(DayAlarmSchedule(weekday: d, isEnabled: true, wakeMinutes: d == 5 ? (6 * 60 + 45) : (7 * 60)))
        }
        WakeAlarm.schedule = schedule

        let next = try XCTUnwrap(WakeAlarm.nextWakeDate(after: now, calendar: calendar))
        let nextComp = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: next)
        XCTAssertEqual(nextComp.year, 2026)
        XCTAssertEqual(nextComp.month, 11)
        XCTAssertEqual(nextComp.day, 19) // Thursday
        XCTAssertEqual(nextComp.weekday, 5)
        XCTAssertEqual(nextComp.hour, 6)
        XCTAssertEqual(nextComp.minute, 45)
    }

    func testNextWakeDateReturnsNilWhenAlarmIsDisabled() {
        WakeAlarm.isEnabled = false
        XCTAssertNil(WakeAlarm.nextWakeDate())
    }

    func testBandLatchingConfirmationAndClearOnDisable() {
        let now = Date()
        WakeAlarm.isEnabled = true
        WakeAlarm.bandConfirmedEpoch = Int(now.timeIntervalSince1970)

        // Exact match is confirmed
        XCTAssertTrue(WakeAlarm.isBandConfirmed(for: now))

        // Within 60 seconds tolerance is confirmed
        let driftedDate = now.addingTimeInterval(35)
        XCTAssertTrue(WakeAlarm.isBandConfirmed(for: driftedDate))

        // Beyond 60 seconds is NOT confirmed
        let distantDate = now.addingTimeInterval(120)
        XCTAssertFalse(WakeAlarm.isBandConfirmed(for: distantDate))

        // Disabling alarm clears the band confirmation epoch
        WakeAlarm.isEnabled = false
        XCTAssertNil(WakeAlarm.bandConfirmedEpoch)
        XCTAssertFalse(WakeAlarm.isBandConfirmed(for: now))
    }
}
