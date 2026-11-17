import Foundation

struct WeekdayWakeSlot: Codable, Equatable, Identifiable {
    let weekday: Int // Foundation Calendar: 1=Sunday ... 7=Saturday.
    var minutes: Int
    var enabled: Bool
    var id: Int { weekday }
}

enum WeeklyWakeSchedule {
    static let entriesKey = "strap.wake.weekly.entries.v1"
    static let activeKey = "strap.wake.weekly.active.v1"
    static func validate(_ slots: [WeekdayWakeSlot]) throws {
        guard slots.count == 7, Set(slots.map(\.weekday)) == Set(1...7),
              slots.allSatisfy({ (0..<1440).contains($0.minutes) }) else {
            throw PersistenceDiagnostics.Failure(message: "Each weekday needs one valid wake time.")
        }
    }
    static func defaults(minutes: Int, enabled: Bool) -> [WeekdayWakeSlot] {
        (1...7).map { WeekdayWakeSlot(weekday: $0, minutes: minutes, enabled: enabled) }
    }
    static func load(defaults: UserDefaults = .standard) throws -> [WeekdayWakeSlot]? {
        guard let data = defaults.data(forKey: entriesKey) else { return nil }
        let slots = try JSONDecoder().decode([WeekdayWakeSlot].self, from: data)
        try validate(slots)
        return slots
    }
    static func save(_ slots: [WeekdayWakeSlot], active: Bool, defaults: UserDefaults = .standard) throws {
        try validate(slots)
        let bytes = try JSONEncoder().encode(slots.sorted { $0.weekday < $1.weekday })
        defaults.set(bytes, forKey: entriesKey)
        defaults.set(active, forKey: activeKey)
    }
    static func next(after now: Date, slots: [WeekdayWakeSlot], calendar: Calendar = .current) throws -> Date? {
        try validate(slots)
        let byDay = Dictionary(uniqueKeysWithValues: slots.map { ($0.weekday, $0) })
        let midnight = calendar.startOfDay(for: now)
        // Build each day's FIRST wall-clock occurrence from its own midnight.
        // This avoids rearming the second copy of a fall-back hour after the
        // first alarm has already passed.
        return (0...7).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: midnight),
                  let slot = byDay[calendar.component(.weekday, from: day)], slot.enabled,
                  let candidate = calendar.date(bySettingHour: slot.minutes / 60, minute: slot.minutes % 60,
                    second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward),
                  calendar.isDate(candidate, inSameDayAs: day), candidate > now else { return nil }
            return candidate
        }.min()
    }
}

/// Coalesces a changed desired schedule while an older verified command is in
/// flight. A transport acknowledgement is not proof of physical wrist actuation.
struct AlarmTarget: Equatable {
    let enabled: Bool
    let date: Date?
}
struct AlarmDeliveryState {
    private(set) var pendingTarget: AlarmTarget?
    private var refreshRequested = false
    mutating func deferIfPending(_ target: AlarmTarget) -> Bool {
        guard let pendingTarget else { return false }
        if pendingTarget != target { refreshRequested = true }
        return true
    }
    mutating func start(_ target: AlarmTarget) { pendingTarget = target }
    mutating func finish() -> Bool {
        pendingTarget = nil
        let again = refreshRequested; refreshRequested = false
        return again
    }
    mutating func reset() { pendingTarget = nil; refreshRequested = false }
}
