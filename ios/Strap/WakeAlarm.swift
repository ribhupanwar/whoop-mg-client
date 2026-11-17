import Foundation
import UserNotifications
import Combine

final class WakeAlarmDelivery: ObservableObject {
    static let shared = WakeAlarmDelivery()
    @Published var status = "Phone notification delivery has not been checked this launch."
}

/// Daily phone notification plus persisted desired next band wake time.
/// BandLink independently programs the next occurrence on the strap.
enum WakeAlarm {
    static let identifier = "strap.wake.alarm"
    private static let enabledKey = "strap.wake.alarm.enabled.v1"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var hasPreference: Bool { UserDefaults.standard.object(forKey: enabledKey) != nil }

    /// Preserve the pre-haptics wake time when upgrading an existing install.
    static func restoreWakeTimeIfNeeded(_ minutes: Int, defaults: UserDefaults = .standard) {
        let key = "strap.wake.alarm.minutes.v1"
        guard defaults.object(forKey: key) == nil, (0..<1440).contains(minutes) else { return }
        defaults.set(minutes, forKey: key)
    }

    static var wakeMinutes: Int {
        UserDefaults.standard.object(forKey: "strap.wake.alarm.minutes.v1") as? Int ?? 7 * 60
    }

    static var usesWeeklySchedule: Bool { UserDefaults.standard.bool(forKey: WeeklyWakeSchedule.activeKey) }
    private static var notificationGeneration = 0
    static func nextWakeDate(after now: Date = Date(), calendar: Calendar = .current,
                             defaults: UserDefaults = .standard) -> Date? {
        guard defaults.bool(forKey: enabledKey) else { return nil }
        return plannedWakeDate(after: now, calendar: calendar, defaults: defaults)
    }
    static func plannedWakeDate(after now: Date = Date(), calendar: Calendar = .current,
                                defaults: UserDefaults = .standard) -> Date? {
        if defaults.bool(forKey: WeeklyWakeSchedule.activeKey) {
            guard let slots = try? WeeklyWakeSchedule.load(defaults: defaults) else { return nil }
            return try? WeeklyWakeSchedule.next(after: now, slots: slots, calendar: calendar)
        }
        let minutes = defaults.object(forKey: "strap.wake.alarm.minutes.v1") as? Int ?? 420
        return BandHaptics.nextWake(minutes: minutes, after: now, calendar: calendar)
    }

    /// Persist the choice and (re)schedule or cancel the daily notification.
    static func setEnabled(_ on: Bool, wakeMinutes: Int) {
        // Turning alarms off must remain possible even if an old saved daily
        // time is corrupt. Weekly mode validates its own per-day slots below.
        guard !on || usesWeeklySchedule || (0..<1440).contains(wakeMinutes) else {
            WakeAlarmDelivery.shared.status = "Invalid daily wake time; existing settings preserved."
            return
        }
        if !usesWeeklySchedule, (0..<1440).contains(wakeMinutes) {
            UserDefaults.standard.set(wakeMinutes, forKey: "strap.wake.alarm.minutes.v1")
        }
        isEnabled = on
        notificationGeneration += 1
        let generation = notificationGeneration
        let center = UNUserNotificationCenter.current()
        let ids = [identifier] + (1...7).map { identifier + ".weekday.\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard on else { WakeAlarmDelivery.shared.status = "Phone notifications off."; return }
        let requests: [(String, DateComponents)]
        if usesWeeklySchedule {
            guard let slots = try? WeeklyWakeSchedule.load() else {
                WakeAlarmDelivery.shared.status = "Saved weekly schedule is unreadable; no phone alarm was scheduled."
                return
            }
            requests = slots.filter(\.enabled).map { slot in
                var when = DateComponents(); when.weekday = slot.weekday
                when.hour = slot.minutes / 60; when.minute = slot.minutes % 60
                return (identifier + ".weekday.\(slot.weekday)", when)
            }
        } else {
            var when = DateComponents(); when.hour = wakeMinutes / 60; when.minute = wakeMinutes % 60
            requests = [(identifier, when)]
        }
        guard !requests.isEmpty else { WakeAlarmDelivery.shared.status = "No enabled weekdays; no phone alarm scheduled."; return }
        WakeAlarmDelivery.shared.status = "Requesting phone notification permission…"
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                guard generation == notificationGeneration else { return }
                guard granted else {
                    WakeAlarmDelivery.shared.status = "Phone notification permission unavailable. Enable notifications in iPhone Settings."
                    return
                }
                if let error { WakeAlarmDelivery.shared.status = "Phone permission failed: " + error.localizedDescription; return }
                var remaining = requests.count
                var failures = 0
                for (id, when) in requests {
                    let content = UNMutableNotificationContent()
                    content.title = "Time to wake"; content.body = "Your saved STRAP wake time."; content.sound = .default
                    let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
                    center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
                        DispatchQueue.main.async {
                            guard generation == notificationGeneration else { return }
                            if error != nil { failures += 1 }
                            remaining -= 1
                            if remaining == 0 {
                                WakeAlarmDelivery.shared.status = failures == 0
                                    ? "Phone schedule saved: \(requests.count) repeating notification(s). Wrist verification is separate."
                                    : "Phone schedule partially failed: \(failures) notification(s) were not saved."
                            }
                        }
                    }
                }
            }
        }
    }
}
