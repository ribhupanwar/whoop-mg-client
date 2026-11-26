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
            recordedMinimum: 650, lastObservedAt: when, isConnected: true
        )
        let decoded = try JSONDecoder().decode(
            CapturedStepsActivityAttributes.ContentState.self,
            from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(decoded, state)
    }
}
