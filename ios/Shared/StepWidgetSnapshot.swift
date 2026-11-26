import Foundation

/// Captured band-counter minimum. The lastObservedAt timestamp comes from a
/// verified BLE history record, never from the time a widget happens to render.
struct StepWidgetSnapshot: Codable, Hashable {
    static let appGroup = "group.com.ribhupanwar.strap"
    static let storageKey = "strap.steps.widget.snapshot.v1"
    static let widgetKind = "StrapStepsHomeWidget"

    let recordedDayKey: String
    let recordedMinimum: Int?
    let lastObservedAt: Date?
    let lastIncreaseAt: Date?
    let connectedAtWrite: Bool
    let writtenAt: Date

    var isForToday: Bool {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return recordedDayKey == formatter.string(from: Date())
    }

    var isFresh: Bool {
        guard isForToday, connectedAtWrite, let lastObservedAt else { return false }
        let age = Date().timeIntervalSince(lastObservedAt)
        return age >= 0 && age <= 10 * 60
    }

    static func load(defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) -> StepWidgetSnapshot? {
        guard let bytes = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: bytes)
    }

    @discardableResult
    func save(defaults: UserDefaults? = UserDefaults(suiteName: Self.appGroup)) -> Bool {
        guard let defaults, let bytes = try? JSONEncoder().encode(self) else { return false }
        defaults.set(bytes, forKey: Self.storageKey)
        return true
    }
}


/// Opt-in, dated summary; no raw sensor samples or account identifiers.
struct HealthWidgetSnapshot: Codable, Equatable {
    static let storageKey = "strap.health.widget.snapshot.v1"
    static let widgetKind = "StrapHealthHomeWidget"
    let dayKey: String
    let recovery: Double?
    let sleep: Double?
    let strain: Double?
    let battery: Int?
    let savedAt: Date

    func isForDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return dayKey == formatter.string(from: date)
    }

    static func load(defaults: UserDefaults? = UserDefaults(suiteName: StepWidgetSnapshot.appGroup)) -> Self? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    @discardableResult
    static func save(_ value: Self?, defaults: UserDefaults? = UserDefaults(suiteName: StepWidgetSnapshot.appGroup)) -> Bool {
        guard let defaults else { return false }
        guard let value else { defaults.removeObject(forKey: storageKey); return true }
        guard let data = try? JSONEncoder().encode(value) else { return false }
        defaults.set(data, forKey: storageKey)
        return true
    }
}
