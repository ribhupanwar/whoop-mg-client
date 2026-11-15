import Foundation
import UserNotifications

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

    /// Persist the choice and (re)schedule or cancel the daily notification.
    static func setEnabled(_ on: Bool, wakeMinutes: Int) {
        guard (0..<1440).contains(wakeMinutes) else { return }
        UserDefaults.standard.set(wakeMinutes, forKey: "strap.wake.alarm.minutes.v1")
        isEnabled = on
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard on else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            var when = DateComponents()
            when.hour = (wakeMinutes / 60) % 24
            when.minute = wakeMinutes % 60
            let content = UNMutableNotificationContent()
            content.title = "Time to wake"
            content.body = "Your sleep coach wake time — get up and start the day."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }
}