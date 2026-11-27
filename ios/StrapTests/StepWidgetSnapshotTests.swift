import Foundation
import XCTest
@testable import Strap

final class StepWidgetSnapshotTests: XCTestCase {
    func testAppGroupSnapshotRoundTripWithIsolatedDefaults() throws {
        let suite = "strap.steps.widget.test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let observed = Date(timeIntervalSince1970: 1_700_006_400)
        let snapshot = StepWidgetSnapshot(
            recordedDayKey: "2023-11-15", recordedMinimum: 312,
            lastObservedAt: observed, lastIncreaseAt: observed,
            connectedAtWrite: true, writtenAt: observed
        )
        XCTAssertTrue(snapshot.save(defaults: defaults))
        XCTAssertEqual(StepWidgetSnapshot.load(defaults: defaults), snapshot)
    }

    func testDailyHealthSnapshotRoundTripAndRemoval() throws {
        let suite = "strap.health.widget.test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 27)))
        let snapshot = HealthWidgetSnapshot(dayKey: "2026-11-27", recovery: 62, sleep: nil,
            strain: 2.7, battery: 85, savedAt: date)
        XCTAssertTrue(HealthWidgetSnapshot.save(snapshot, defaults: defaults))
        XCTAssertEqual(HealthWidgetSnapshot.load(defaults: defaults), snapshot)
        XCTAssertTrue(snapshot.isForDay(date, calendar: calendar))
        XCTAssertFalse(snapshot.isForDay(date.addingTimeInterval(86400), calendar: calendar))
        XCTAssertTrue(HealthWidgetSnapshot.save(nil, defaults: defaults))
        XCTAssertNil(HealthWidgetSnapshot.load(defaults: defaults))
    }

    func testHealthTimelineExpiresLiveMetricsWithoutRemovingDailyMetrics() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 10)))
        let snapshot = HealthWidgetSnapshot(dayKey: "2026-11-27", recovery: 62, sleep: 80,
            strain: 2.7, battery: 85, savedAt: now, stress: 1.4,
            stressObservedAt: now.addingTimeInterval(-540))
        let stressExpiry = now.addingTimeInterval(60)
        let batteryExpiry = now.addingTimeInterval(600)
        XCTAssertEqual(snapshot.refreshBoundaries(after: now, calendar: calendar), [stressExpiry, batteryExpiry])
        XCTAssertEqual(HealthWidgetMetric.stress.value(in: snapshot, at: stressExpiry.addingTimeInterval(-1), calendar: calendar), 1.4)
        XCTAssertNil(HealthWidgetMetric.stress.value(in: snapshot, at: stressExpiry, calendar: calendar))
        XCTAssertEqual(HealthWidgetMetric.battery.value(in: snapshot, at: stressExpiry, calendar: calendar), 85)
        XCTAssertNil(HealthWidgetMetric.battery.value(in: snapshot, at: batteryExpiry, calendar: calendar))
        XCTAssertEqual(HealthWidgetMetric.recovery.value(in: snapshot, at: batteryExpiry, calendar: calendar), 62)
        XCTAssertTrue(snapshot.refreshBoundaries(after: batteryExpiry, calendar: calendar).isEmpty)
        XCTAssertTrue(snapshot.refreshBoundaries(after: now.addingTimeInterval(86400), calendar: calendar).isEmpty)
    }

    func testOldWorkoutLiveActivityDecodesWithoutNewStepFields() throws {
        let legacy = """
        {"heartRate":143,"zone":3,"distanceMeters":1234.0,
         "paceSecondsPerKilometer":305,"paused":false,"lastSampleAt":0.0}
        """
        let decoded = try JSONDecoder().decode(
            WorkoutActivityAttributes.ContentState.self, from: Data(legacy.utf8)
        )
        XCTAssertEqual(decoded.heartRate, 143)
        XCTAssertNil(decoded.steps)
        XCTAssertNil(decoded.stepsObservedAt)
    }

    func testWalkingLiveActivityContentStateCodable() throws {
        let when = Date(timeIntervalSince1970: 1_700_006_400)
        let state = CapturedStepsActivityAttributes.ContentState(
            recordedMinimum: 650, lastObservedAt: when, isConnected: true,
            heartRate: 110, estimatedStrain: 3.2
        )
        let decoded = try JSONDecoder().decode(
            CapturedStepsActivityAttributes.ContentState.self,
            from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(decoded, state)
    }
}
