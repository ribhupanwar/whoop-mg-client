import XCTest
@testable import Strap

final class HealthspanProfileTests: XCTestCase {

    func testHealthspanCoverageUsesRequestedCalendarForObservedDays() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var la = Calendar(identifier: .gregorian)
        la.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        // 00:30 UTC and 23:30 UTC are distinct UTC dates but the same LA date.
        let first = Date(timeIntervalSince1970: 1_795_681_000)
        let last = first.addingTimeInterval(23 * 3600)
        let observation = HealthspanObservation(value: 50, observedDays: 2,
                                                firstObserved: first, lastObserved: last)
        XCTAssertTrue(observation.isValid(calendar: utc))
        XCTAssertFalse(observation.isValid(calendar: la))
        let coverage = HealthspanInputCoverage(observations: [.steps: observation],
                                                asOf: last.addingTimeInterval(60))
        XCTAssertFalse(coverage.missing(.steps, minimumDays: 2, windowDays: 3, calendar: utc))
        XCTAssertTrue(coverage.missing(.steps, minimumDays: 2, windowDays: 3, calendar: la))
    }

    func testBirthdayUsesCalendarDaysAndPersistsWithoutTimeZoneShift() throws {
        let india = ProfileBirthDate.calendar(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata")))
        let west = ProfileBirthDate.calendar(timeZone: try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles")))
        let birth = ProfileBirthDate(DateComponents(year: 1988, month: 11, day: 22))
        let data = try JSONEncoder().encode(birth)
        let decoded = try JSONDecoder().decode(ProfileBirthDate.self, from: data)
        for calendar in [india, west] {
            let birthday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 22)))
            let eve = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: birthday))
            XCTAssertEqual(decoded.age(on: birthday, calendar: calendar), 38)
            XCTAssertLessThan(try XCTUnwrap(decoded.age(on: eve, calendar: calendar)), 38)
            XCTAssertEqual(ProfileBirthDate(try XCTUnwrap(decoded.date(in: calendar)), calendar: calendar), birth)
        }
    }

    func testBirthDateProvidesTrainingAgeWithoutConfirmingLegacyPlaceholder() throws {
        var settings = AppSettings()
        XCTAssertNil(settings.profileAge())
        XCTAssertNil(settings.profileMaxHeartRate())
        AppleHealthProfile(birthDate: ProfileBirthDate(DateComponents(year: 1966, month: 11, day: 22)))
            .fillMissing(in: &settings)
        let date = try XCTUnwrap(ProfileBirthDate.calendar().date(from: DateComponents(year: 2026, month: 11, day: 22)))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.profileAge(on: date), 60)
        XCTAssertEqual(decoded.profileMaxHeartRate(on: date), 166)
        XCTAssertFalse(decoded.ageConfirmed)
    }

    func testHealthProfileImportPreservesExplicitEntriesAndOlderMassCannotReplaceNewer() {
        var settings = AppSettings()
        settings.ageConfirmed = true
        settings.age = 38
        settings.sex = .female
        settings.weightKG = 62
        let later = ProfileBodyMeasurement(kilograms: 46, date: Date(timeIntervalSince1970: 20), source: "Scale")
        let earlier = ProfileBodyMeasurement(kilograms: 44, date: Date(timeIntervalSince1970: 10), source: "Scale")
        AppleHealthProfile(birthDate: ProfileBirthDate(DateComponents(year: 1988, month: 11, day: 22)),
                           sex: .male, heightCM: 165, weightKG: 65, leanMass: later)
            .fillMissing(in: &settings)
        AppleHealthProfile(leanMass: earlier).fillMissing(in: &settings)
        XCTAssertNil(settings.birthDate)
        XCTAssertEqual(settings.age, 38)
        XCTAssertEqual(settings.sex, .female)
        XCTAssertEqual(settings.heightCM, 165)
        XCTAssertEqual(settings.weightKG, 62)
        XCTAssertEqual(settings.leanMass, later)
    }
}
