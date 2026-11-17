import XCTest
@testable import Strap

final class WeeklyWakeScheduleTests: XCTestCase {
    private func utc(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func slots(_ enabled: [Int: Int]) -> [WeekdayWakeSlot] {
        (1...7).map { WeekdayWakeSlot(weekday: $0, minutes: enabled[$0] ?? 420, enabled: enabled[$0] != nil) }
    }
    func testNextEnabledWeekdayUsesItsOwnTimeAndSkipsDisabledDays() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let schedule = slots([2: 420, 7: 540])
        XCTAssertEqual(try WeeklyWakeSchedule.next(after: utc("2026-11-20T08:00:00Z"), slots: schedule, calendar: calendar), utc("2026-11-21T09:00:00Z"))
        XCTAssertEqual(try WeeklyWakeSchedule.next(after: utc("2026-11-21T09:00:00Z"), slots: schedule, calendar: calendar), utc("2026-11-23T07:00:00Z"))
        XCTAssertNil(try WeeklyWakeSchedule.next(after: Date(), slots: slots([:]), calendar: calendar))
    }
    func testSpringGapAdvancesToFirstValidLocalClockTime() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let next = try XCTUnwrap(WeeklyWakeSchedule.next(after: utc("2026-03-07T20:00:00Z"), slots: slots([1: 150]), calendar: calendar))
        XCTAssertEqual(calendar.component(.day, from: next), 8)
        XCTAssertEqual(calendar.component(.hour, from: next), 3)
        XCTAssertEqual(calendar.component(.minute, from: next), 0)
    }
    func testFallFoldIsScheduledOnceAndNeverRearmsSecondCopyOfSameHour() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let schedule = slots([1: 90])
        XCTAssertEqual(try WeeklyWakeSchedule.next(after: utc("2026-10-31T20:00:00Z"), slots: schedule, calendar: calendar), utc("2026-11-01T05:30:00Z"))
        XCTAssertEqual(try WeeklyWakeSchedule.next(after: utc("2026-11-01T05:31:00Z"), slots: schedule, calendar: calendar), utc("2026-11-08T06:30:00Z"))
    }
    func testStorePreservesDailyPreferenceAndRejectsMalformedEditsBeforeWriting() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WeeklyWake-" + UUID().uuidString))
        defer {
            defaults.removeObject(forKey: WeeklyWakeSchedule.entriesKey)
            defaults.removeObject(forKey: WeeklyWakeSchedule.activeKey)
            defaults.removeObject(forKey: "strap.wake.alarm.minutes.v1")
        }
        defaults.set(420, forKey: "strap.wake.alarm.minutes.v1")
        let schedule = slots([2: 480, 3: 540])
        try WeeklyWakeSchedule.save(schedule, active: true, defaults: defaults)
        XCTAssertEqual(try WeeklyWakeSchedule.load(defaults: defaults), schedule)
        XCTAssertEqual(defaults.integer(forKey: "strap.wake.alarm.minutes.v1"), 420)
        let original = defaults.data(forKey: WeeklyWakeSchedule.entriesKey)
        XCTAssertThrowsError(try WeeklyWakeSchedule.save(schedule + [schedule[0]], active: true, defaults: defaults))
        XCTAssertEqual(defaults.data(forKey: WeeklyWakeSchedule.entriesKey), original)
        try WeeklyWakeSchedule.save(schedule, active: false, defaults: defaults)
        XCTAssertEqual(try WeeklyWakeSchedule.load(defaults: defaults), schedule, "Leaving weekly mode must retain configured days")
        XCTAssertTrue(PersistenceDiagnostics.permittedKey(WeeklyWakeSchedule.entriesKey))
        XCTAssertTrue(PersistenceDiagnostics.permittedKey(WeeklyWakeSchedule.activeKey))
    }
    func testChangedDateAtSameClockTimeIsCoalescedAfterPendingDelivery() {
        var delivery = AlarmDeliveryState()
        let monday = AlarmTarget(enabled: true, date: utc("2026-11-23T07:00:00Z"))
        let tuesday = AlarmTarget(enabled: true, date: utc("2026-11-24T07:00:00Z"))
        XCTAssertFalse(delivery.deferIfPending(monday))
        delivery.start(monday)
        XCTAssertTrue(delivery.deferIfPending(tuesday))
        XCTAssertTrue(delivery.finish(), "A new weekday must not be lost behind a minute-only alarm cache")
        delivery.start(tuesday)
        XCTAssertTrue(delivery.deferIfPending(tuesday))
        XCTAssertFalse(delivery.finish(), "An unchanged pending target must not cause repeated writes")
    }
    func testDisableDuringPendingWriteIsNotLostAndDisconnectClearsTransientState() {
        var delivery = AlarmDeliveryState()
        delivery.start(AlarmTarget(enabled: true, date: Date()))
        XCTAssertTrue(delivery.deferIfPending(AlarmTarget(enabled: false, date: nil)))
        XCTAssertTrue(delivery.finish())
        delivery.start(AlarmTarget(enabled: false, date: nil))
        delivery.reset()
        XCTAssertNil(delivery.pendingTarget)
        XCTAssertFalse(delivery.finish())
    }
}

extension WeeklyWakeScheduleTests {
    func testTurningOffIsNotBlockedByAnInvalidDailyTime() {
        let defaults = UserDefaults.standard
        let keys = ["strap.wake.alarm.enabled.v1", "strap.wake.alarm.minutes.v1", WeeklyWakeSchedule.activeKey]
        let previous = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in previous {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(false, forKey: WeeklyWakeSchedule.activeKey)
        defaults.set(true, forKey: "strap.wake.alarm.enabled.v1")
        defaults.set(9999, forKey: "strap.wake.alarm.minutes.v1")
        WakeAlarm.setEnabled(false, wakeMinutes: -1)
        XCTAssertFalse(WakeAlarm.isEnabled)
        XCTAssertEqual(defaults.integer(forKey: "strap.wake.alarm.minutes.v1"), 9999,
            "Disabling must not rewrite unreadable original settings")
    }
}
