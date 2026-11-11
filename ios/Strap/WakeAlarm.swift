import Foundation
import UserNotifications

/// A local phone notification fired daily at the sleep coach's wake time.
///
/// Deliberately a PHONE alarm, not a band haptic: no alarm command has been
/// verified on the strap, so nothing is sent to the band. The notification
/// repeats at the chosen wake time until turned off.
enum WakeAlarm {
    static let identifier = "strap.wake.alarm"
    private static let enabledKey = "strap.wake.alarm.enabled.v1"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Persist the choice and (re)schedule or cancel the daily notification.
    static func setEnabled(_ on: Bool, wakeMinutes: Int) {
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