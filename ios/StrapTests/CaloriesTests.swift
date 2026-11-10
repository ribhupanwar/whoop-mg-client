import XCTest
@testable import Strap

/// Pins the calorie arithmetic to hand-computed values so a coefficient or
/// divisor cannot drift silently. Every figure here is an estimate by
/// construction; these tests check the formula, not the physiology.
final class CaloriesTests: XCTestCase {
    private let weight = 70.0
    private let height = 175.0
    private let age = 30.0
    private let resting = 55.0
    private let maximum = 187.0

    func testMifflinBasalPerSex() {
        XCTAssertEqual(
            Calories.bmrKcalPerDay(weightKg: weight, heightCm: height, age: age, sex: .male) ?? 0,
            1648.75, accuracy: 0.001
        )
        XCTAssertEqual(
            Calories.bmrKcalPerDay(weightKg: weight, heightCm: height, age: age, sex: .female) ?? 0,
            1482.75, accuracy: 0.001
        )
        XCTAssertEqual(
            Calories.bmrKcalPerDay(weightKg: weight, heightCm: height, age: age, sex: .unspecified) ?? 0,
            1565.75, accuracy: 0.001
        )
    }

    func testBasalAbstainsWithoutUsableBodyData() {
        XCTAssertNil(Calories.bmrKcalPerDay(weightKg: 0, heightCm: height, age: age, sex: .male))
        XCTAssertNil(Calories.bmrKcalPerDay(weightKg: weight, heightCm: 0, age: age, sex: .male))
        XCTAssertNil(Calories.bmrKcalPerDay(weightKg: weight, heightCm: height, age: 0, sex: .male))
        XCTAssertNil(Calories.activeKcal(
            hrPerMinute: [150], restingHR: resting, maxHR: maximum,
            weightKg: 0, heightCm: height, age: age, sex: .male
        ))
    }

    func testGateIsFortyPercentOfReserve() {
        XCTAssertEqual(Calories.gateHR(restingHR: 55, maxHR: 187) ?? 0, 107.8, accuracy: 0.001)
        XCTAssertNil(Calories.gateHR(restingHR: 90, maxHR: 80))
        XCTAssertNil(Calories.gateHR(restingHR: 0, maxHR: 187))
    }

    func testKeytelRateAtOneFiftyBpm() {
        let perSecond = Calories.keytelKcalPerS(
            hr: 150, maxHR: maximum, weightKg: weight, age: age, sex: .male
        )
        XCTAssertEqual(perSecond, 0.237034, accuracy: 0.00001)
        XCTAssertEqual(perSecond * 60, 14.2221, accuracy: 0.001)
    }

    func testHeartRateAboveMaxIsCapped() {
        let capped = Calories.keytelKcalPerS(
            hr: 260, maxHR: maximum, weightKg: weight, age: age, sex: .male
        )
        let atMax = Calories.keytelKcalPerS(
            hr: maximum, maxHR: maximum, weightKg: weight, age: age, sex: .male
        )
        XCTAssertEqual(capped, atMax, accuracy: 0.000001)
    }

    func testMinutesBelowTheGateBillNoActiveEnergy() {
        let kcal = Calories.activeKcal(
            hrPerMinute: [95, 100, 104], restingHR: resting, maxHR: maximum,
            weightKg: weight, heightCm: height, age: age, sex: .male
        )
        XCTAssertEqual(kcal ?? -1, 0, accuracy: 0.0001)
    }

    func testOneMinuteAtOneFiftyBpmIsKeytelMinusBasal() {
        let kcal = Calories.activeKcal(
            hrPerMinute: [150], restingHR: resting, maxHR: maximum,
            weightKg: weight, heightCm: height, age: age, sex: .male
        )
        XCTAssertEqual(kcal ?? 0, 13.0771, accuracy: 0.001)
    }

    func testSessionAtExerciseHeartRate() {
        let kcal = Calories.sessionActiveKcal(
            meanHR: 150, steps: 0, minutes: 10, restingHR: resting, maxHR: maximum,
            weightKg: weight, heightCm: height, age: age, sex: .male
        )
        XCTAssertEqual(kcal ?? 0, 130.771, accuracy: 0.01)
    }

    /// A walk the HR gate refuses is still priced when its measured cadence
    /// says the wearer was walking — Tudor-Locke 2019, 110 spm = 4 MET.
    func testWalkingCadencePricesAMinuteTheGateRefused() {
        let kcal = Calories.sessionActiveKcal(
            meanHR: 95, steps: 3_300, minutes: 30, restingHR: resting, maxHR: maximum,
            weightKg: weight, heightCm: height, age: age, sex: .male
        )
        XCTAssertEqual(kcal ?? 0, 103.047, accuracy: 0.01)
    }

    func testSlowWalkUnderTheGateCostsNothingAboveRest() {
        let kcal = Calories.sessionActiveKcal(
            meanHR: 95, steps: 900, minutes: 30, restingHR: resting, maxHR: maximum,
            weightKg: weight, heightCm: height, age: age, sex: .male
        )
        XCTAssertEqual(kcal ?? -1, 0, accuracy: 0.0001)
    }

    func testSessionAbstainsWithoutBodyData() {
        XCTAssertNil(Calories.sessionActiveKcal(
            meanHR: 150, steps: 0, minutes: 10, restingHR: resting, maxHR: maximum,
            weightKg: 0, heightCm: height, age: age, sex: .male
        ))
    }
}
