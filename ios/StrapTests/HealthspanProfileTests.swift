import XCTest
@testable import Strap

final class HealthspanProfileTests: XCTestCase {
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
