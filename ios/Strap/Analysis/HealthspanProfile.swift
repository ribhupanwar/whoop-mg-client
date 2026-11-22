import Foundation

struct ProfileBirthDate: Codable, Equatable {
    let year: Int
    let month: Int
    let day: Int

    init(_ date: Date, calendar: Calendar = ProfileBirthDate.calendar()) {
        self.init(calendar.dateComponents([.year, .month, .day], from: date))
    }

    init(_ components: DateComponents) {
        year = components.year ?? 0
        month = components.month ?? 0
        day = components.day ?? 0
    }

    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    func date(in calendar: Calendar = ProfileBirthDate.calendar()) -> Date? {
        guard (1900...2200).contains(year),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              Self(date, calendar: calendar) == self else { return nil }
        return date
    }

    func age(on date: Date, calendar: Calendar = ProfileBirthDate.calendar()) -> Double? {
        guard let birth = self.date(in: calendar), birth <= date else { return nil }
        let today = calendar.startOfDay(for: date)
        guard let years = calendar.dateComponents([.year], from: birth, to: today).year,
              let last = calendar.date(byAdding: .year, value: years, to: birth),
              let next = calendar.date(byAdding: .year, value: years + 1, to: birth) else { return nil }
        let elapsed = calendar.dateComponents([.day], from: last, to: today).day ?? 0
        let length = calendar.dateComponents([.day], from: last, to: next).day ?? 365
        return Double(years) + Double(elapsed) / Double(max(1, length))
    }
}

struct ProfileBodyMeasurement: Codable, Equatable {
    let kilograms: Double
    let date: Date
    let source: String
}

struct AppleHealthProfile {
    var birthDate: ProfileBirthDate?
    var sex: Sex?
    var heightCM: Double?
    var weightKG: Double?
    var leanMass: ProfileBodyMeasurement?

    // Reads are user-initiated. Explicit values already saved in Settings win.
    func fillMissing(in settings: inout AppSettings) {
        if settings.birthDate == nil, !settings.ageConfirmed { settings.birthDate = birthDate }
        if settings.sex == .unspecified, let sex { settings.sex = sex }
        if settings.heightCM == nil { settings.heightCM = heightCM }
        if settings.weightKG == nil { settings.weightKG = weightKG }
        if let leanMass, settings.leanMass.map({ $0.date < leanMass.date }) ?? true {
            settings.leanMass = leanMass
        }
    }
}

extension AppSettings {
    func profileAge(on date: Date = Date()) -> Double? {
        if let birthDate {
            return birthDate.age(on: date).flatMap { (5...110).contains($0) ? $0 : nil }
        }
        return ageConfirmed && (5...110).contains(age) ? Double(age) : nil
    }

    func profileMaxHeartRate(on date: Date = Date()) -> Double? {
        if let maxHROverride, maxHROverride.isFinite, maxHROverride > 60 { return maxHROverride }
        return profileAge(on: date).map { 208 - 0.7 * $0 }
    }
}
