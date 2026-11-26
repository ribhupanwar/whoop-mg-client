import Foundation

/// Captured band-counter minimum. The lastObservedAt timestamp comes from a
/// verified BLE history record, never from the time a widget happens to render.
struct StepWidgetSnapshot: Codable, Hashable {
    static let appGroup = "group.com.ribhupanwar.strap"
    static let storageKey = "strap.steps.widget.snapshot.v1"
    static let widgetKind = "StrapStepsHomeWidget"

    let recordedMinimum: Int?
    let lastObservedAt: Date?
    let lastIncreaseAt: Date?
    let connectedAtWrite: Bool
    let writtenAt: Date

    var isFresh: Bool {
        guard connectedAtWrite, let lastObservedAt else { return false }
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
