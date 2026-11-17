import XCTest
@testable import Strap

final class WhoopRecoveredCaloriesTests: XCTestCase {
    private func profile(_ baseline: WhoopRecoveredCalories.Baseline = .raw0) -> WhoopRecoveredCalories.Profile {
        .init(weightKg: 70, heightMeters: 1.75, ageYears: 30, baseline: baseline)
    }
    private func integrate(_ hr: [Double?], _ times: [Double?], tail: WhoopRecoveredCalories.TailPolicy = .observedIntervalsOnly) throws -> WhoopRecoveredCalories.Result {
        try WhoopRecoveredCalories.integrate(heartRates: hr, timestamps: times, profile: profile(),
            restingHR: 55, maxHR: 187, referenceRate: 0.2, tailPolicy: tail)
    }
    func testRestingRateIndependentDecimalAnchorsAndHeightMeters() throws {
        // Independent decimal calculation recorded in validation notes.
        XCTAssertEqual(try WhoopRecoveredCalories.restingKcalPerSecond(profile(.raw0)), 0.019625775462962963, accuracy: 1e-14)
        XCTAssertEqual(try WhoopRecoveredCalories.restingKcalPerSecond(profile(.raw1)), 0.01744366898148148, accuracy: 1e-14)
        XCTAssertEqual(try WhoopRecoveredCalories.restingKcalPerSecond(profile(.raw2Mean)), 0.01853472222222222, accuracy: 1e-14)
        XCTAssertNil(WhoopRecoveredCalories.Baseline(rawValue: 99), "Unknown resting enum metadata must not become an invented profile")
    }
    func testRecoveredRestingClampAndMeanOfSeparatelyClampedRates() throws {
        let zero = WhoopRecoveredCalories.Profile(weightKg: 1, heightMeters: 0.1, ageYears: 100, baseline: .raw0)
        XCTAssertEqual(try WhoopRecoveredCalories.restingKcalPerSecond(zero), 0)
        let mean = WhoopRecoveredCalories.Profile(weightKg: 1, heightMeters: 0.1, ageYears: 100, baseline: .raw2Mean)
        // First formula clamps to zero; second daily value is 54.82, then mean.
        XCTAssertEqual(try WhoopRecoveredCalories.restingKcalPerSecond(mean), 27.41 / 86400, accuracy: 1e-14)
    }
    func testWorkoutRatesAndCappedMaximumIndependentAnchors() throws {
        XCTAssertEqual(try WhoopRecoveredCalories.workoutKcalPerSecond(hr: 150, maxHR: 187, profile: profile(.raw0)), 0.23621733588272785, accuracy: 1e-14)
        XCTAssertEqual(try WhoopRecoveredCalories.workoutKcalPerSecond(hr: 150, maxHR: 187, profile: profile(.raw1)), 0.15137029955385596, accuracy: 1e-14)
        XCTAssertEqual(try WhoopRecoveredCalories.workoutKcalPerSecond(hr: 150, maxHR: 187, profile: profile(.raw2Mean)), 0.1937938177182919, accuracy: 1e-14)
        XCTAssertEqual(try WhoopRecoveredCalories.workoutKcalPerSecond(hr: 260, maxHR: 187, profile: profile()), 0.32464945825366475, accuracy: 1e-14)
        XCTAssertEqual(try WhoopRecoveredCalories.workoutKcalPerSecond(hr: 1, maxHR: 187, profile: profile()), 0)
    }
    func testWorkoutOtherRawBaselinesUseRecoveredMeanWithoutAssumingRestingEnumMapping() throws {
        for raw in [-1, 2, 99] {
            XCTAssertEqual(try WhoopRecoveredCalories.workoutKcalPerSecond(hr: 150, maxHR: 187,
                weightKg: 70, ageYears: 30, rawBaseline: raw), 0.1937938177182919, accuracy: 1e-14)
        }
    }
    func testThresholdAndTwoRegisterSlopeInterceptIncludeEquality() throws {
        XCTAssertEqual(try WhoopRecoveredCalories.threshold(restingHR: 55, maxHR: 187), 94.6, accuracy: 1e-12)
        let line = try WhoopRecoveredCalories.interpolation(restingRate: 0.02, referenceRate: 0.2, restingHR: 60, maxHR: 160)
        XCTAssertEqual(line.threshold, 90)
        XCTAssertEqual(line.slope, 0.18 / 70, accuracy: 1e-14)
        XCTAssertEqual(line.intercept, -0.21142857142857144, accuracy: 1e-14)
        XCTAssertEqual(try line.rate(hr: 89), 0.02, accuracy: 1e-14)
        XCTAssertEqual(try line.rate(hr: 90), 0.02, accuracy: 1e-14)
        XCTAssertEqual(try line.rate(hr: 160), 0.2, accuracy: 1e-14)
        XCTAssertEqual(try line.rate(hr: 125), 0.11, accuracy: 1e-14)
        XCTAssertGreaterThan(try line.rate(hr: 180), 0.2, "Integration input clamp is not established by the excerpts")
    }
    func testIntervalsCapAtThreeWithoutFillingLongGapsOrImplicitTail() throws {
        XCTAssertEqual(try WhoopRecoveredCalories.durations(timestamps: [0, 1, 11, 11.5], tailPolicy: .observedIntervalsOnly), [1, 3, 0.5, 0])
        XCTAssertEqual(try WhoopRecoveredCalories.durations(timestamps: [0, 1, 11, 11.5], tailPolicy: .repeatFinalInterval), [1, 3, 0.5, 0.5])
    }
    func testEmptySingletonDuplicateAndMissingEndpointsDoNotManufactureSeconds() throws {
        for tail in [WhoopRecoveredCalories.TailPolicy.observedIntervalsOnly, .repeatFinalInterval] {
            XCTAssertEqual(try WhoopRecoveredCalories.durations(timestamps: [], tailPolicy: tail), [])
            XCTAssertEqual(try WhoopRecoveredCalories.durations(timestamps: [10], tailPolicy: tail), [0])
            XCTAssertEqual(try WhoopRecoveredCalories.durations(timestamps: [10, 10], tailPolicy: tail), [0, 0])
            XCTAssertEqual(try WhoopRecoveredCalories.durations(timestamps: [0, 1, nil], tailPolicy: tail), [1, 0, 0])
        }
        XCTAssertThrowsError(try integrate([], [])) { XCTAssertEqual($0 as? WhoopRecoveredCalories.Failure, .noCoveredIntervals) }
        XCTAssertThrowsError(try integrate([150], [0], tail: .repeatFinalInterval))
        XCTAssertThrowsError(try integrate([150, 150], [0, 0], tail: .repeatFinalInterval))
    }
    func testInvalidSampleBreaksAdjacentCoverageRatherThanBridgingIt() throws {
        let invalidValues: [Double?] = [nil, .nan, .infinity, 0, -1]
        for invalid in invalidValues {
            let result = try integrate([150, invalid, 150, 150], [0, 1, 2, 3])
            XCTAssertEqual(result.coveredSeconds, 1)
            XCTAssertEqual(result.excludedIntervals, 3)
        }
        let result = try integrate([150, 150, 150, 150], [0, .infinity, 2, 3])
        XCTAssertEqual(result.coveredSeconds, 1)
    }
    func testOutOfOrderDataAndCountMismatchFailWithoutSortingOrDroppingRecords() {
        XCTAssertThrowsError(try integrate([150, 150, 150, 150], [0, 2, 1, 3])) {
            XCTAssertEqual($0 as? WhoopRecoveredCalories.Failure, .outOfOrderTimestamps)
        }
        XCTAssertThrowsError(try integrate([150], [0, 1])) {
            XCTAssertEqual($0 as? WhoopRecoveredCalories.Failure, .countMismatch)
        }
        XCTAssertThrowsError(try WhoopRecoveredCalories.durations(timestamps: [2, nil, 1], tailPolicy: .observedIntervalsOnly))
    }
    func testRestingSamplesProveIntegratedOutputIsNotActiveOnlyOrWholeDayTotal() throws {
        let result = try integrate([60, 60, 60], [0, 1, 2])
        XCTAssertEqual(result.coveredSeconds, 2)
        XCTAssertEqual(result.integratedKcal, 0.039251550925925926, accuracy: 1e-14)
        XCTAssertEqual(result.integratedKcal, result.restingKcalForCoveredSeconds, accuracy: 1e-14)
        XCTAssertEqual(result.netAboveRestingKcal, 0, accuracy: 1e-14)
        XCTAssertEqual(result.repeatedTailSeconds, 0)
    }
    func testExplicitTailBranchReportsAddedCoverageAndOriginalSum() throws {
        let observed = try integrate([60, 150, 187], [0, 1, 3])
        let repeated = try integrate([60, 150, 187], [0, 1, 3], tail: .repeatFinalInterval)
        XCTAssertEqual(observed.coveredSeconds, 3)
        XCTAssertEqual(repeated.coveredSeconds, 5)
        XCTAssertEqual(repeated.repeatedTailSeconds, 2)
        XCTAssertEqual(repeated.integratedKcal - observed.integratedKcal, 0.4, accuracy: 1e-13)
        XCTAssertEqual(observed.integratedKcal, 0.275170227673561, accuracy: 1e-13)
        XCTAssertEqual(repeated.integratedKcal, 0.675170227673561, accuracy: 1e-13)
        let missingTail = try integrate([60, 150, 187], [0, 1, nil], tail: .repeatFinalInterval)
        XCTAssertEqual(missingTail.coveredSeconds, 1); XCTAssertEqual(missingTail.repeatedTailSeconds, 0)
    }
    func testInvalidInputsAndArithmeticOverflowFailClosed() throws {
        for invalid in [Double.nan, .infinity, 0, -1] {
            let p = WhoopRecoveredCalories.Profile(weightKg: invalid, heightMeters: 1.75, ageYears: 30, baseline: .raw0)
            XCTAssertThrowsError(try WhoopRecoveredCalories.restingKcalPerSecond(p))
            XCTAssertThrowsError(try WhoopRecoveredCalories.workoutKcalPerSecond(hr: invalid, maxHR: 187, profile: profile()))
            XCTAssertThrowsError(try WhoopRecoveredCalories.threshold(restingHR: 55, maxHR: invalid))
        }
        for p in [
            WhoopRecoveredCalories.Profile(weightKg: 70, heightMeters: .nan, ageYears: 30, baseline: .raw0),
            WhoopRecoveredCalories.Profile(weightKg: 70, heightMeters: 0, ageYears: 30, baseline: .raw0),
            WhoopRecoveredCalories.Profile(weightKg: 70, heightMeters: 1.75, ageYears: -.infinity, baseline: .raw0),
            WhoopRecoveredCalories.Profile(weightKg: 70, heightMeters: 1.75, ageYears: -1, baseline: .raw0)
        ] { XCTAssertThrowsError(try WhoopRecoveredCalories.restingKcalPerSecond(p)) }
        XCTAssertThrowsError(try WhoopRecoveredCalories.threshold(restingHR: 90, maxHR: 90))
        XCTAssertThrowsError(try WhoopRecoveredCalories.interpolation(restingRate: 0.02, referenceRate: .nan, restingHR: 55, maxHR: 187))
        let enormous = WhoopRecoveredCalories.Profile(weightKg: .greatestFiniteMagnitude, heightMeters: 1.75, ageYears: .greatestFiniteMagnitude, baseline: .raw0)
        XCTAssertThrowsError(try WhoopRecoveredCalories.restingKcalPerSecond(enormous))
        XCTAssertThrowsError(try WhoopRecoveredCalories.durations(timestamps: [-Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude], tailPolicy: .observedIntervalsOnly))
    }
    func testProductionModelAndNoImplicitBaselineConversionStaySeparate() throws {
        XCTAssertEqual(Calories.moderateHRRFraction, 0.4)
        XCTAssertEqual(Calories.bmrKcalPerDay(weightKg: 70, heightCm: 175, age: 30, sex: .male), 1648.75)
        XCTAssertEqual(try WhoopRecoveredCalories.restingKcalPerSecond(profile()) * 86400, 1695.667, accuracy: 1e-10)
    }
}
