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

    func testDetectedDeletionRequiresAppSourceAndBandWorkoutIdentifiers() {
        let source = HKSource.default()
        let predicate = HealthKitBridge.detectedWorkoutDeletionPredicate(startTimes: [1_700_000_000], source: source)
        let parts = (predicate as? NSCompoundPredicate)?.subpredicates
        XCTAssertEqual(parts?.count, 3)
        XCTAssertEqual(parts?.first, HKQuery.predicateForObjects(from: source))
        XCTAssertEqual(parts?[1], HKQuery.predicateForObjects(
            withMetadataKey: HealthKitBridge.sourceKey, operatorType: .equalTo, value: "strap-band"
        ))
        XCTAssertEqual(parts?.last, HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: ["strap-session-1700000000"]
        ))
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
