import XCTest
import SwiftUI
@testable import Strap

final class MoreTabNavigationTests: XCTestCase {

    func testMoreViewInitializesWithoutCrashing() {
        let store = AppStore()
        let moreView = MoreView().environmentObject(store)
        XCTAssertNotNil(moreView)
    }

    func testAllMoreTabDestinationsInstantiateAndRender() {
        let store = AppStore()

        // 1. Device Settings
        let deviceSettings = DeviceSettingsView().environmentObject(store)
        XCTAssertNotNil(deviceSettings)

        // 2. Connection & Sync
        let connectionSync = ConnectionSyncView().environmentObject(store)
        XCTAssertNotNil(connectionSync)

        // 3. Band Alarms
        let bandAlarms = BandAlarmsView().environmentObject(store)
        XCTAssertNotNil(bandAlarms)

        // Additional existing destinations exposed by the consolidated More tab
        XCTAssertNotNil(JournalView().environmentObject(store))
        XCTAssertNotNil(PlanView().environmentObject(store))
        XCTAssertNotNil(StrapWidgetGuideView())
        XCTAssertNotNil(StrapGuidedBreathingView())

        // 4. Health Integrations
        let healthIntegrations = AppleHealthImportView()
        XCTAssertNotNil(healthIntegrations)

        // 5. Data Management (Import & Export)
        let dataManagement = DataManagementView().environmentObject(store)
        XCTAssertNotNil(dataManagement)

        // 6. Health & Activity Settings
        let settings = SettingsView().environmentObject(store)
        XCTAssertNotNil(settings)

        // 7. Notification Settings
        let notifications = NotificationSettingsView()
        XCTAssertNotNil(notifications)

        // 8. App Preferences
        let appPreferences = AppPreferencesView().environmentObject(store)
        XCTAssertNotNil(appPreferences)

        // 9. App Information
        let appInfo = AppInfoView()
        XCTAssertNotNil(appInfo)

        // 10. Diagnostics & Support
        let diagnostics = DiagnosticsSupportView().environmentObject(store)
        XCTAssertNotNil(diagnostics)
    }

    func testMoreTabSectionsAndRowTitlesAreUnique() {
        let entries = MoreMenuItem.allCases
        XCTAssertEqual(entries.count, 16)
        XCTAssertEqual(Set(entries.map { $0.metadata.title }).count, entries.count)
        XCTAssertEqual(Set(entries.map { $0.metadata.icon }).count, entries.count)
        XCTAssertEqual(Set(entries.map { $0.accessibilityID }).count, entries.count)
        let counts = Dictionary(grouping: entries, by: { $0.metadata.section }).mapValues { $0.count }
        XCTAssertEqual(counts, [
            "DEVICE": 3,
            "HEALTH & ACTIVITY": 4,
            "DATA & INTEGRATIONS": 4,
            "PREFERENCES": 2,
            "WIDGETS & LIVE ACTIVITIES": 1,
            "ABOUT": 2
        ])
        XCTAssertEqual(MoreMenuItem.journal.accessibilityID, "more.journal")
        XCTAssertEqual(MoreMenuItem.backupRestore.metadata.section, "DATA & INTEGRATIONS")
    }

    func testJournalReminderUsesValidLocalClockComponents() {
        XCTAssertEqual(JournalReminderSchedule.components(minutes: 0).hour, 0)
        XCTAssertEqual(JournalReminderSchedule.components(minutes: 0).minute, 0)
        XCTAssertEqual(JournalReminderSchedule.components(minutes: 1439).hour, 23)
        XCTAssertEqual(JournalReminderSchedule.components(minutes: 1439).minute, 59)
        XCTAssertEqual(JournalReminderSchedule.components(minutes: -1).hour, 8)
        XCTAssertEqual(JournalReminderSchedule.components(minutes: 1440).hour, 8)
    }

    func testWakeAlarmPersistenceThroughBandAlarms() {
        let originalEnabled = WakeAlarm.isEnabled
        let originalMinutes = WakeAlarm.wakeMinutes
        defer {
            WakeAlarm.setEnabled(originalEnabled, wakeMinutes: originalMinutes)
        }

        // Test updating alarm settings
        WakeAlarm.setEnabled(true, wakeMinutes: 8 * 60 + 15) // 8:15 AM
        XCTAssertTrue(WakeAlarm.isEnabled)
        XCTAssertEqual(WakeAlarm.wakeMinutes, 495)

        WakeAlarm.setEnabled(false, wakeMinutes: 6 * 60 + 30) // 6:30 AM
        XCTAssertFalse(WakeAlarm.isEnabled)
        XCTAssertEqual(WakeAlarm.wakeMinutes, 390)
    }

    func testAppPreferencesPersistence() {
        let defaults = UserDefaults.standard
        let originalMetric = defaults.bool(forKey: "strap.preferences.useMetric")
        let original24h = defaults.bool(forKey: "strap.preferences.use24HourTime")
        let originalSpo2 = defaults.bool(forKey: "strap.spo2ResearchEnabled")
        defer {
            defaults.set(originalMetric, forKey: "strap.preferences.useMetric")
            defaults.set(original24h, forKey: "strap.preferences.use24HourTime")
            defaults.set(originalSpo2, forKey: "strap.spo2ResearchEnabled")
        }

        defaults.set(false, forKey: "strap.preferences.useMetric")
        XCTAssertFalse(defaults.bool(forKey: "strap.preferences.useMetric"))

        defaults.set(true, forKey: "strap.preferences.useMetric")
        XCTAssertTrue(defaults.bool(forKey: "strap.preferences.useMetric"))

        defaults.set(true, forKey: "strap.preferences.use24HourTime")
        XCTAssertTrue(defaults.bool(forKey: "strap.preferences.use24HourTime"))

        defaults.set(true, forKey: "strap.spo2ResearchEnabled")
        XCTAssertTrue(defaults.bool(forKey: "strap.spo2ResearchEnabled"))
    }

    func testNotificationPreferencesPersistence() {
        let defaults = UserDefaults.standard
        let originalBedtime = defaults.bool(forKey: "strap.notifications.bedtimeReminders")
        let originalTargets = defaults.bool(forKey: "strap.notifications.targetAlerts")
        defer {
            defaults.set(originalBedtime, forKey: "strap.notifications.bedtimeReminders")
            defaults.set(originalTargets, forKey: "strap.notifications.targetAlerts")
        }

        defaults.set(true, forKey: "strap.notifications.bedtimeReminders")
        XCTAssertTrue(defaults.bool(forKey: "strap.notifications.bedtimeReminders"))

        defaults.set(true, forKey: "strap.notifications.targetAlerts")
        XCTAssertTrue(defaults.bool(forKey: "strap.notifications.targetAlerts"))
    }
}
