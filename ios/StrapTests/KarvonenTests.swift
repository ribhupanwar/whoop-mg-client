import XCTest
@testable import Strap

final class KarvonenTests: XCTestCase {

    func testZoneMathReferenceExample() {
        // RHR 60, max 190 → reserve 130 → Z2 lower = 60 + 0.6 × 130 = 138.
        let zones = Karvonen.zones(restingHR: 60, maxHR: 190)
        XCTAssertNotNil(zones)
        guard let zones = zones else { return }

        XCTAssertEqual(zones.count, 5)
        XCTAssertEqual(zones[1].name, "Z2")
        XCTAssertEqual(zones[1].lowerBPM, 138.0, accuracy: 0.0001)
        XCTAssertEqual(zones[1].upperBPM, 151.0, accuracy: 0.0001)
        XCTAssertEqual(zones[0].lowerBPM, 125.0, accuracy: 0.0001)
        XCTAssertEqual(zones[0].upperBPM, 138.0, accuracy: 0.0001)
        XCTAssertEqual(zones[4].lowerBPM, 177.0, accuracy: 0.0001)
        XCTAssertEqual(zones[4].upperBPM, 190.0, accuracy: 0.0001)
    }

    func testZonesAreContiguous() {
        guard let zones = Karvonen.zones(restingHR: 72, maxHR: 187) else {
            return XCTFail("Expected valid zones")
        }
        for index in 0..<(zones.count - 1) {
            XCTAssertEqual(zones[index].upperBPM, zones[index + 1].lowerBPM, accuracy: 0.0001)
        }
        XCTAssertEqual(zones.first?.lowerFraction, 0.50)
        XCTAssertEqual(zones.last?.upperFraction, 1.00)
    }

    func testInvalidInputsReturnNil() {
        XCTAssertNil(Karvonen.zones(restingHR: 190, maxHR: 60))
        XCTAssertNil(Karvonen.zones(restingHR: 60, maxHR: 60))
        XCTAssertNil(Karvonen.zones(restingHR: 0, maxHR: 190))
        XCTAssertNil(Karvonen.zones(restingHR: -5, maxHR: 190))
        XCTAssertNil(Karvonen.zones(restingHR: 60, maxHR: .nan))
        XCTAssertNil(Karvonen.zones(restingHR: 60, maxHR: .infinity))
    }

    func testAgePredictedMaxHR() {
        // 208 − 0.7 × 30 = 187 (the Settings default age).
        XCTAssertEqual(Karvonen.agePredictedMaxHR(age: 30), 187.0, accuracy: 0.0001)
        XCTAssertEqual(Karvonen.agePredictedMaxHR(age: 40), 180.0, accuracy: 0.0001)
    }
    func testZoneZeroAndMaximumHaveExplicitBoundaries() throws {
        let zones = try XCTUnwrap(Karvonen.zones(restingHR: 60, maxHR: 190))
        XCTAssertEqual(Karvonen.zoneIndex(heartRate: 80, zones: zones), 0)
        XCTAssertEqual(Karvonen.zoneIndex(heartRate: 125, zones: zones), 1)
        XCTAssertEqual(Karvonen.zoneIndex(heartRate: 138, zones: zones), 2)
        XCTAssertEqual(Karvonen.zoneIndex(heartRate: 190, zones: zones), 5)
        XCTAssertNil(Karvonen.zoneIndex(heartRate: 200, zones: zones))
        XCTAssertNil(Karvonen.zoneIndex(heartRate: .nan, zones: zones))
        XCTAssertNil(Karvonen.zoneIndex(heartRate: 0, zones: zones))
    }

    func testWhoop5802KarvonenReserveMethods() {
        // RHR 60, MaxHR 190 -> reserve span 130
        let rhr = 60.0
        let maxHR = 190.0

        // HR 125 -> (125 - 60)/130 = 65/130 = 0.50
        let reserve50 = Karvonen.getReserveWithHeartRate(heartRate: 125.0, restingHeartRate: rhr, maximumHeartRate: maxHR)
        XCTAssertNotNil(reserve50)
        XCTAssertEqual(reserve50!, 0.50, accuracy: 0.0001)

        // Inverse: reserve 0.50 -> 60 + 0.50 * 130 = 125 BPM
        let hrCalculated = Karvonen.getHeartRateForReserve(reserve: 0.50, restingHeartRate: rhr, maximumHeartRate: maxHR)
        XCTAssertNotNil(hrCalculated)
        XCTAssertEqual(hrCalculated!, 125.0, accuracy: 0.0001)

        // Boundary clipping
        let belowRest = Karvonen.getReserveWithHeartRate(heartRate: 50.0, restingHeartRate: rhr, maximumHeartRate: maxHR)
        XCTAssertEqual(belowRest, 0.0)

        let aboveMax = Karvonen.getReserveWithHeartRate(heartRate: 200.0, restingHeartRate: rhr, maximumHeartRate: maxHR)
        XCTAssertEqual(aboveMax, 1.0)

        // Invalid inputs
        XCTAssertNil(Karvonen.getReserveWithHeartRate(heartRate: 120, restingHeartRate: 190, maximumHeartRate: 60))
        XCTAssertNil(Karvonen.getHeartRateForReserve(reserve: 0.5, restingHeartRate: 190, maximumHeartRate: 60))
    }

    func testWhoop5802EffectiveBaselines() {
        // Fallback with nil baselines
        XCTAssertEqual(Karvonen.effectiveMaxHR(configuredMaxHR: nil, age: nil), 190.0)
        XCTAssertEqual(Karvonen.effectiveMaxHR(configuredMaxHR: nil, age: 30), 187.0)
        XCTAssertEqual(Karvonen.effectiveMaxHR(configuredMaxHR: 195.0, age: 30), 195.0)

        XCTAssertEqual(Karvonen.effectiveRestingHR(measuredRestingHR: nil), 60.0)
        XCTAssertEqual(Karvonen.effectiveRestingHR(measuredRestingHR: 48.0), 48.0)
    }
}
