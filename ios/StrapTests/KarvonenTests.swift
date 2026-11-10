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
}