import Foundation
import UserNotifications

/// Individual day wake alarm schedule entry (Sunday = 1 ... Saturday = 7).
public struct DayAlarmSchedule: Codable, Equatable, Identifiable {
    public var id: Int { weekday }
    public let weekday: Int // 1 = Sunday, 2 = Monday, ... 7 = Saturday
    public var isEnabled: Bool
    public var wakeMinutes: Int // Minutes from midnight (0..<1440)

    public init(weekday: Int, isEnabled: Bool, wakeMinutes: Int) {
        self.weekday = weekday
        self.isEnabled = isEnabled
        self.wakeMinutes = min(max(wakeMinutes, 0), 1439)
    }

    public var weekdayName: String {
        switch weekday {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return "Day \(weekday)"
        }
    }

    public var weekdayShort: String {
        switch weekday {
        case 1: return "Sun"
        case 2: return "Mon"
        case 3: return "Tue"
        case 4: return "Wed"
        case 5: return "Thu"
        case 6: return "Fri"
        case 7: return "Sat"
        default: return "\(weekday)"
        }
    }
}

/// Daily phone notification plus persisted desired next band wake time.
/// BandLink independently programs the next occurrence on the strap.
///
/// Enhanced with WHOOP 5.80.2 and OpenStrap-verified 7-day weekly scheduling
/// and band-latching confirmation tracking.
public enum WakeAlarm {
    public static let identifier = "strap.wake.alarm"
    private static let enabledKey = "strap.wake.alarm.enabled.v1"
    private static let minutesKey = "strap.wake.alarm.minutes.v1"
    private static let scheduleKey = "strap.wake.alarm.schedule.v1"
    private static let bandConfirmedEpochKey = "strap.wake.alarm.bandConfirmedEpoch.v1"

    /// Master alarm toggle.
    public static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if !newValue {
                bandConfirmedEpoch = nil
            }
            rescheduleNotifications()
        }
    }

    public static var hasPreference: Bool { UserDefaults.standard.object(forKey: enabledKey) != nil }

    /// Preserve the pre-haptics wake time when upgrading an existing install.
    public static func restoreWakeTimeIfNeeded(_ minutes: Int, defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: minutesKey) == nil, (0..<1440).contains(minutes) else { return }
        defaults.set(minutes, forKey: minutesKey)
    }

    /// Primary / default target wake minutes from midnight (0..<1440).
    public static var wakeMinutes: Int {
        get { UserDefaults.standard.object(forKey: minutesKey) as? Int ?? 7 * 60 }
        set {
            guard (0..<1440).contains(newValue) else { return }
            UserDefaults.standard.set(newValue, forKey: minutesKey)
            rescheduleNotifications()
        }
    }

    /// The exact Unix timestamp acknowledged by the physical WHOOP band.
    public static var bandConfirmedEpoch: Int? {
        get {
            let val = UserDefaults.standard.integer(forKey: bandConfirmedEpochKey)
            return val > 0 ? val : nil
        }
        set {
            if let val = newValue {
                UserDefaults.standard.set(val, forKey: bandConfirmedEpochKey)
            } else {
                UserDefaults.standard.removeObject(forKey: bandConfirmedEpochKey)
            }
        }
    }

    /// Whether the currently scheduled next wake alarm has been physically acknowledged by the band.
    public static func isBandConfirmed(for nextWake: Date?) -> Bool {
        guard let nextWake, let confirmed = bandConfirmedEpoch else { return false }
        let nextEpoch = Int(nextWake.timeIntervalSince1970)
        // Allow up to 60 seconds tolerance for subsecond/RTC drift
        return abs(confirmed - nextEpoch) <= 60
    }

    /// Whether the immediate upcoming alarm is confirmed on the band.
    public static var isNextWakeConfirmed: Bool {
        guard let next = nextWakeDate() else { return false }
        return isBandConfirmed(for: next)
    }

    /// Default 7-day schedule using current wakeMinutes.
    public static var defaultSchedule: [DayAlarmSchedule] {
        let mins = wakeMinutes
        return (1...7).map { DayAlarmSchedule(weekday: $0, isEnabled: true, wakeMinutes: mins) }
    }

    /// Persisted 7-day schedule (Sunday=1 through Saturday=7).
    public static var schedule: [DayAlarmSchedule] {
        get {
            guard let data = UserDefaults.standard.data(forKey: scheduleKey),
                  let decoded = try? JSONDecoder().decode([DayAlarmSchedule].self, from: data),
                  decoded.count == 7 else {
                return defaultSchedule
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: scheduleKey)
            }
            rescheduleNotifications()
        }
    }

    /// Update a specific weekday's schedule.
    public static func updateSchedule(weekday: Int, isEnabled: Bool, wakeMinutes: Int) {
        var current = schedule
        if let idx = current.firstIndex(where: { $0.weekday == weekday }) {
            current[idx].isEnabled = isEnabled
            current[idx].wakeMinutes = min(max(wakeMinutes, 0), 1439)
            schedule = current
        }
    }

    /// Calculates the next upcoming scheduled wake Date after `now`.
    public static func nextWakeDate(after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        let currentSchedule = schedule

        var earliest: Date? = nil
        for dayOffset in 0...7 {
            guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: checkDate)
            guard let entry = currentSchedule.first(where: { $0.weekday == weekday }), entry.isEnabled else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: checkDate)
            components.hour = (entry.wakeMinutes / 60) % 24
            components.minute = entry.wakeMinutes % 60
            components.second = 0

            guard let candidate = calendar.date(from: components), candidate > now else { continue }

            if earliest == nil || candidate < earliest! {
                earliest = candidate
            }
        }
        return earliest
    }

    /// Persist choice and (re)schedule or cancel the daily notification.
    public static func setEnabled(_ on: Bool, wakeMinutes: Int) {
        guard (0..<1440).contains(wakeMinutes) else { return }
        UserDefaults.standard.set(wakeMinutes, forKey: minutesKey)
        isEnabled = on
    }

    /// Re-evaluates and schedules local notifications across all enabled weekdays.
    public static func rescheduleNotifications() {
        let startTime = CFAbsoluteTimeGetCurrent()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        for i in 1...7 {
            center.removePendingNotificationRequests(withIdentifiers: ["\(identifier).day\(i)"])
        }

        guard isEnabled else { return }

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let currentSchedule = schedule
            for entry in currentSchedule where entry.isEnabled {
                var when = DateComponents()
                when.weekday = entry.weekday
                when.hour = (entry.wakeMinutes / 60) % 24
                when.minute = entry.wakeMinutes % 60

                let content = UNMutableNotificationContent()
                content.title = "Time to wake"
                content.body = "Your sleep coach target wake time — get up and start the day."
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
                let reqId = "\(identifier).day\(entry.weekday)"
                center.add(UNNotificationRequest(identifier: reqId, content: content, trigger: trigger))
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            PerformanceProfiler.shared.recordNotificationProcessingTime(elapsed)
        }
    }
}
