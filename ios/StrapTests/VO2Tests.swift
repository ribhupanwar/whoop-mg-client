import XCTest
@testable import Strap

final class VO2Tests: XCTestCase {
    func testUthFormula() {
        // 15.3 × 190 / 50 = 58.14
        XCTAssertEqual(Hrv.vo2Max(maxHR: 190, restingHR: 50) ?? 0, 58.14, accuracy: 0.001)
    }

    func testAgePredictedMaxHRFeedsTheSameFormula() {
        let maxHR = Karvonen.agePredictedMaxHR(age: 30)  // 187
        XCTAssertEqual(maxHR, 187, accuracy: 0.001)
        XCTAssertEqual(Hrv.vo2Max(maxHR: maxHR, restingHR: 55) ?? 0, 52.02, accuracy: 0.001)
    }

    func testImpossibleInputsGiveNil() {
        XCTAssertNil(Hrv.vo2Max(maxHR: 50, restingHR: 60))
        XCTAssertNil(Hrv.vo2Max(maxHR: 190, restingHR: 0))
        XCTAssertNil(Hrv.vo2Max(maxHR: 190, restingHR: -5))
        XCTAssertNil(Hrv.vo2Max(maxHR: 60, restingHR: 60))
    }
}
