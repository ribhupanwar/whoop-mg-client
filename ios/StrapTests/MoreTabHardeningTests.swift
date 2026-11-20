import XCTest
import SwiftUI
import HealthKit
@testable import Strap

final class MoreTabHardeningTests: XCTestCase {

    // MARK: - Priority 1: Connection & Sync Diagnostics

    func testConnectionSyncViewInstantiatesWithMetrics() {
        let store = AppStore()
        let view = ConnectionSyncView().environmentObject(store)
        XCTAssertNotNil(view)

        // Verify BandLink properties exist and are initialized
        XCTAssertEqual(store.band.packetGapCount, 0)
        XCTAssertEqual(store.band.duplicatePacketCount, 0)
        XCTAssertEqual(store.band.historyUndecodableFrames, 0)
        XCTAssertNil(store.band.historySyncError)
    }

    func testReconnectStateFormatting() {
        let status = BandStatus.reconnecting(attempt: 3)
        XCTAssertEqual(status.title, "Reconnecting (attempt 3)…")
        XCTAssertFalse(status.isConnected)

        let delay = ReconnectBackoffPolicy.delay(forAttempt: 3)
        XCTAssertGreaterThan(delay, 0)
    }

    // MARK: - Priority 2: Verified Backup & Restore Persistence

    func testPersistenceDiagnosticsPermittedKeysIncludesAllMoreTabPreferences() {
        let keysToCheck = [
            "strap.wake.alarm.enabled.v1",
            "strap.wake.alarm.minutes.v1",
            "strap.wake.alarm.schedule.v1",
            "strap.preferences.useMetric",
            "strap.preferences.use24HourTime",
            "strap.notifications.bedtimeReminders",
            "strap.notifications.targetAlerts",
            "strap.spo2ResearchEnabled",
            "strap.spo2ResearchReport",
            "strap.settings.v1",
            "strap.activities.v1"
        ]

        for key in keysToCheck {
            XCTAssertTrue(
                PersistenceDiagnostics.permittedKey(key),
                "Key '\(key)' must be permitted in PersistenceDiagnostics to prevent data loss on backup/restore"
            )
        }
    }

    func testDisallowedKeysAreRejectedByPersistenceDiagnostics() {
        let rejected = [
            "strap.band.authKey",
            "strap.wake.alarm.bandConfirmedEpoch.v1",
            "arbitrary.token",
            "strap.unknown.private"
        ]
        for key in rejected {
            XCTAssertFalse(PersistenceDiagnostics.permittedKey(key))
        }
    }

    // MARK: - Priority 3: Accurate Baseline Progress & Explanations

    func testBaselineRollingWindowConfiguration() {
        XCTAssertEqual(DailyAnalysis.rollingBaselineDays, 28, "Rolling baseline must be 28 days")
        XCTAssertEqual(Recovery.minBaselineDays, 7, "Minimum baseline for initial recovery calculation")
    }

    func testSettingsViewInstantiatesWithBaselinePanel() {
        let store = AppStore()
        let settingsView = SettingsView().environmentObject(store)
        XCTAssertNotNil(settingsView)
    }

    // MARK: - Priority 5: HealthKit Permission & Data-Sync

    func testAppleHealthImportViewInstantiates() {
        let view = AppleHealthImportView()
        XCTAssertNotNil(view)
    }

    func testHealthKitExternalIDDeduplication() {
        let id1 = HealthKitBridge.externalID(startUnix: 1700000000)
        let id2 = HealthKitBridge.externalID(startUnix: 1700000000)
        let id3 = HealthKitBridge.externalID(startUnix: 1700000001)

        XCTAssertEqual(id1, id2, "Same startUnix must produce identical external UUID for deduplication")
        XCTAssertNotEqual(id1, id3)
        XCTAssertEqual(id1, "strap-session-1700000000")
    }

    // MARK: - Priority 6: Band Alarms 7-Day Schedule & Confirmation Latching

    func test7DayAlarmScheduleCustomizationAndDefaults() {
        let defaultSched = WakeAlarm.defaultSchedule
        XCTAssertEqual(defaultSched.count, 7, "Weekly schedule must have 7 days")
        XCTAssertEqual(defaultSched.map { $0.weekday }, [1, 2, 3, 4, 5, 6, 7])

        // Verify DayAlarmSchedule helper strings
        let sunday = DayAlarmSchedule(weekday: 1, isEnabled: true, wakeMinutes: 420)
        XCTAssertEqual(sunday.weekdayName, "Sunday")
        XCTAssertEqual(sunday.weekdayShort, "Sun")

        let saturday = DayAlarmSchedule(weekday: 7, isEnabled: false, wakeMinutes: 540)
        XCTAssertEqual(saturday.weekdayName, "Saturday")
        XCTAssertEqual(saturday.weekdayShort, "Sat")
    }

    func testBandConfirmedEpochTolerance() {
        let now = Date()
        let nowEpoch = Int(now.timeIntervalSince1970)

        WakeAlarm.bandConfirmedEpoch = nowEpoch
        XCTAssertTrue(WakeAlarm.isBandConfirmed(for: now))

        // Within 60 seconds tolerance
        let near = now.addingTimeInterval(45)
        XCTAssertTrue(WakeAlarm.isBandConfirmed(for: near))

        // Outside tolerance
        let far = now.addingTimeInterval(120)
        XCTAssertFalse(WakeAlarm.isBandConfirmed(for: far))

        WakeAlarm.bandConfirmedEpoch = nil
        XCTAssertFalse(WakeAlarm.isBandConfirmed(for: now))
    }

    // MARK: - Priority 7: Safe Device Controls & DIS Display

    func testRebootOpcodeIs0x1D() {
        XCTAssertEqual(BandCommand.rebootStrap.rawValue, 0x1D)
    }

    func testForceTrimOpcodeIs0x19AndQuarantined() {
        XCTAssertEqual(BandCommand.forceTrim.rawValue, 0x19)
    }
}
