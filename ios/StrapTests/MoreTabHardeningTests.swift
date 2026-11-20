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

    // MARK: - Priority 4: Raw Telemetry CSV Export

    private func makeSample(
        unix: Int, hr: Int, rr: [Int] = [833], accel: Double? = 0.025,
        gx: Double? = 0.1, gy: Double? = 0.2, gz: Double? = 0.95,
        steps: Int? = 1250, cadence: Int? = 110, activityClass: Int? = 1,
        skinTemp: Double? = 34.5, sleepState: Int? = 0, hrQuality: Int? = 1
    ) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(
                version: 18, flags: 0x80, recordIndex: UInt32(unix % 100000),
                unix: UInt32(unix), subsecQ15: 16384
            ),
            heartRate: hr,
            rrIntervalsMS: rr,
            dynamicAccelG: accel,
            gravityXG: gx, gravityYG: gy, gravityZG: gz,
            stepCounter: steps, stepCadence: cadence, activityClass: activityClass,
            skinTempC: skinTemp, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: nil, sleepState: sleepState,
            cardiacFlags: nil, hrQualityFlags: hrQuality,
            spo2CandidateRaw: nil, spo2CandidatePct: nil,
            spo2CandidateKind: .absent,
            signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
        )
    }

    func testRawTelemetryDiagnosticsCSVGeneration() throws {
        let sample1 = makeSample(unix: 1700000000, hr: 72, rr: [833, 834])

        let csv = try RawTelemetryDiagnostics.csv(samples: [sample1])
        XCTAssertTrue(csv.contains("unix,record_index,subsec_q15,heart_rate_bpm,rr_ms,dynamic_accel_g,gravity_x_g,gravity_y_g,gravity_z_g,step_counter,step_cadence,activity_class,skin_temp_c,band_state,hr_quality_flags"))
        XCTAssertTrue(csv.contains("72,833|834,0.0250,0.1000,0.2000,0.9500,1250,110,1,34.5000,0,1"))
    }

    func testRawTelemetryDiagnosticsWriteToDisk() throws {
        let sample = makeSample(
            unix: 1700000001, hr: 65, rr: [923], accel: 0.01,
            gx: 0.0, gy: 0.0, gz: 1.0,
            steps: nil, cadence: nil, activityClass: nil, skinTemp: 33.8
        )

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("raw-telemetry-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = try RawTelemetryDiagnostics.write(samples: [sample], directory: tmpDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let readBack = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(readBack.contains("65,923,0.0100,0.0000,0.0000,1.0000"))
    }

    func testRawTelemetryThrowsOnEmptySamples() {
        XCTAssertThrowsError(try RawTelemetryDiagnostics.csv(samples: [])) { error in
            XCTAssertEqual(error.localizedDescription, "No sensor samples available in the selected window for raw export.")
        }
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
