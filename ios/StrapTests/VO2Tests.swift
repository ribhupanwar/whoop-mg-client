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

    func testSteadyLevelRunningEstimate() {
        // 3 m/s = 180 m/min; ACSM running net cost = 36 ml/kg/min.
        // HR reserve fraction = (150-50)/(190-50) = 5/7.
        let value = Hrv.runningVO2Estimate(
            speedMetersPerSecond: 3, meanHR: 150,
            restingHR: 50, maxHR: 190, durationSeconds: 600
        )
        XCTAssertEqual(value ?? 0, 53.9, accuracy: 0.001)
    }

    func testRunningEstimateRejectsUnreliableSegments() {
        XCTAssertNil(Hrv.runningVO2Estimate(
            speedMetersPerSecond: 3, meanHR: 150,
            restingHR: 50, maxHR: 190, durationSeconds: 120))
        XCTAssertNil(Hrv.runningVO2Estimate(
            speedMetersPerSecond: 3, meanHR: 150,
            restingHR: 50, maxHR: 190, durationSeconds: 600, grade: 0.08))
        XCTAssertNil(Hrv.runningVO2Estimate(
            speedMetersPerSecond: 3, meanHR: 85,
            restingHR: 50, maxHR: 190, durationSeconds: 600))
        XCTAssertNil(Hrv.runningVO2Estimate(
            speedMetersPerSecond: .nan, meanHR: 150,
            restingHR: 50, maxHR: 190, durationSeconds: 600))
    }

    func testRunningTrendNeedsThreeDistinctDaysAndRejectsOutliers() {
        let day = 86_400
        let now = 100 * day
        XCTAssertNil(Hrv.runningVO2Trend([
            (unix: now - day, value: 50),
            (unix: now - day + 60, value: 51),
            (unix: now - 2 * day, value: 52)
        ], nowUnix: now))
        let observations: [(unix: Int, value: Double)] = [
            (unix: now - day, value: 50),
            (unix: now - 2 * day, value: 51),
            (unix: now - 3 * day, value: 52),
            (unix: now - 4 * day, value: 84),
            (unix: now - 40 * day, value: 20),
            (unix: now - 5 * day, value: .nan)
        ]
        XCTAssertEqual(Hrv.runningVO2Trend(observations, nowUnix: now) ?? 0,
                       51.5, accuracy: 0.001)
    }

    func testImpossibleInputsGiveNil() {
        XCTAssertNil(Hrv.vo2Max(maxHR: 50, restingHR: 60))
        XCTAssertNil(Hrv.vo2Max(maxHR: 190, restingHR: 0))
        XCTAssertNil(Hrv.vo2Max(maxHR: 190, restingHR: -5))
        XCTAssertNil(Hrv.vo2Max(maxHR: 60, restingHR: 60))
    }
}
