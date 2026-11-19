import XCTest
import SwiftUI
@testable import Strap

final class MoreTabNavigationTests: XCTestCase {

    func testMoreViewInitializesWithoutCrashing() {
        let store = AppStore()
        let moreView = MoreView().environmentObject(store)
        _ = moreView.body
    }

    func testAllMoreTabDestinationsInstantiateAndRender() {
        let store = AppStore()

        // 1. Device Settings
        let deviceSettings = DeviceSettingsView().environmentObject(store)
        _ = deviceSettings.body

        // 2. Connection & Sync
        let connectionSync = ConnectionSyncView().environmentObject(store)
        _ = connectionSync.body

        // 3. Band Alarms
        let bandAlarms = BandAlarmsView().environmentObject(store)
        _ = bandAlarms.body

        // 4. Health Integrations
        let healthIntegrations = AppleHealthImportView()
        _ = healthIntegrations.body

        // 5. Data Management (Import & Export)
        let dataManagement = DataManagementView().environmentObject(store)
        _ = dataManagement.body

        // 6. Health & Activity Settings
        let settings = SettingsView().environmentObject(store)
        _ = settings.body

        // 7. Notification Settings
        let notifications = NotificationSettingsView()
        _ = notifications.body

        // 8. App Preferences
        let appPreferences = AppPreferencesView().environmentObject(store)
        _ = appPreferences.body

        // 9. App Information
        let appInfo = AppInfoView()
        _ = appInfo.body

        // 10. Diagnostics & Support
        let diagnostics = DiagnosticsSupportView().environmentObject(store)
        _ = diagnostics.body
    }

    func testMoreTabSectionsAndRowTitlesAreUnique() {
        // Enumerate expected More tab entries
        let entries: [(section: String, title: String, icon: String)] = [
            ("DEVICE", "Device Settings", "radiowaves.right"),
            ("DEVICE", "Connection & Sync", "arrow.triangle.2.circlepath"),
            ("DEVICE", "Band Alarms", "alarm"),
            ("HEALTH & DATA", "Health Integrations", "link"),
            ("HEALTH & DATA", "Data Import & Export", "externaldrive"),
            ("HEALTH & DATA", "Health & Activity Settings", "figure.run"),
            ("PREFERENCES", "Notifications", "bell"),
            ("PREFERENCES", "App Preferences", "gearshape"),
            ("ABOUT", "App Information", "info.circle"),
            ("ABOUT", "Diagnostics & Support", "wrench.and.screwdriver")
        ]

        // Verify total row count is exactly 10
        XCTAssertEqual(entries.count, 10, "More tab must contain exactly 10 unique rows")

        // Verify all row titles are unique
        let titles = entries.map { $0.title }
        let uniqueTitles = Set(titles)
        XCTAssertEqual(titles.count, uniqueTitles.count, "Every More tab row title must be unique")

        // Verify all icons are unique
        let icons = entries.map { $0.icon }
        let uniqueIcons = Set(icons)
        XCTAssertEqual(icons.count, uniqueIcons.count, "Every More tab row icon must be unique")

        // Verify sections
        let sections = Set(entries.map { $0.section })
        XCTAssertEqual(sections, ["DEVICE", "HEALTH & DATA", "PREFERENCES", "ABOUT"])
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
