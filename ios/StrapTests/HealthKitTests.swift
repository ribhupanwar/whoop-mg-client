import HealthKit
import XCTest
@testable import Strap

final class HealthKitMappingTests: XCTestCase {
    func testGaitKindsMapToWorkoutTypes() {
        XCTAssertEqual(HealthKitBridge.activityType(for: "run"), .running)
        XCTAssertEqual(HealthKitBridge.activityType(for: "walk"), .walking)
        XCTAssertEqual(HealthKitBridge.activityType(for: "lift"), .traditionalStrengthTraining)
        // An HR-only session must not claim to be running or lifting.
        XCTAssertEqual(HealthKitBridge.activityType(for: "workout"), .other)
        XCTAssertEqual(HealthKitBridge.activityType(for: "cardio"), .other)
    }

    func testExternalIDIsStableAndDistinct() {
        XCTAssertEqual(
            HealthKitBridge.externalID(startUnix: 1_700_000_000),
            "strap-session-1700000000"
        )
        XCTAssertNotEqual(
            HealthKitBridge.externalID(startUnix: 1_700_000_000),
            HealthKitBridge.externalID(startUnix: 1_700_000_001)
        )
    }

    func testDetectedDeletionRequiresAppSourceAndBandWorkoutIdentifiers() throws {
        // The unsigned test host cannot create a default HealthKit source.
        let source = NSPredicate(value: false)
        let predicate = HealthKitBridge.detectedWorkoutDeletionPredicate(
            startTimes: [1_700_000_000], sourcePredicate: source
        )
        let compound = try XCTUnwrap(predicate as? NSCompoundPredicate)
        XCTAssertEqual(compound.compoundPredicateType, .and)
        let parts = try XCTUnwrap(compound.subpredicates as? [NSPredicate])
        XCTAssertEqual(parts, [
            source,
            HKQuery.predicateForObjects(withMetadataKey: HealthKitBridge.sourceKey, operatorType: .equalTo,
                                        value: "strap-band"),
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID,
                                        allowedValues: ["strap-session-1700000000"])
        ])
    }

    func testHealthKitDefaultsOff() throws {
        XCTAssertFalse(AppSettings().healthKitEnabled)
        let roundTrip = try JSONDecoder().decode(
            AppSettings.self, from: JSONEncoder().encode(AppSettings())
        )
        XCTAssertFalse(roundTrip.healthKitEnabled)
    }

    func testLegacySettingsWithoutTheKeyStillLoad() throws {
        let legacy = Data(#"{"age":41,"designPreview":true}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertEqual(decoded.age, 41)
        XCTAssertTrue(decoded.designPreview)
        XCTAssertFalse(decoded.healthKitEnabled)
    }
}

final class RecordedRunRelayTests: XCTestCase {
    @MainActor
    func testExplicitRecordedSportMapping() {
        XCTAssertEqual(RecordedRunHealthRelay.activityType("run"), .running)
        XCTAssertEqual(RecordedRunHealthRelay.activityType("treadmill"), .running)
        XCTAssertEqual(RecordedRunHealthRelay.activityType("trailRun"), .running)
        XCTAssertEqual(RecordedRunHealthRelay.activityType("walk"), .walking)
        XCTAssertEqual(RecordedRunHealthRelay.activityType("cycling"), .cycling)
        XCTAssertNil(RecordedRunHealthRelay.activityType("unknown"))
        XCTAssertNil(RecordedRunHealthRelay.activityType("lift"))
    }

    func testExportPauseAndHRTimestampsRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var run = WorkoutSession(id: UUID(), activityKind: "run", activityLabel: "Run",
            startedAt: start, endedAt: start.addingTimeInterval(90), phase: .saved)
        run.exportHeartRate = [.init(unix: 1_700_000_010, bpm: 140)]
        run.exportPauses = [.init(start: start.addingTimeInterval(30), end: start.addingTimeInterval(40))]
        let decoded = try JSONDecoder().decode(WorkoutSession.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(decoded.exportHeartRate, run.exportHeartRate)
        XCTAssertEqual(decoded.exportPauses, run.exportPauses)
        run.exportPauses = nil
        run.exportHeartRate = nil
        let legacy = try JSONDecoder().decode(WorkoutSession.self, from: JSONEncoder().encode(run))
        XCTAssertNil(legacy.exportPauses)
        XCTAssertNil(legacy.exportHeartRate)
    }
}
