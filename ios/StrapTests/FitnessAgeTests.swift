import XCTest
@testable import Strap

final class FitnessAgeModelTests: XCTestCase {
    func testReferenceInputsMapToChronologicalAge() {
        XCTAssertEqual(FitnessAgeModel.calculate(
            age: 35, sex: .male, restingHR: 65, activityIndex: 5
        )!, 35, accuracy: 1e-8)
        XCTAssertEqual(FitnessAgeModel.calculate(
            age: 40, sex: .female, restingHR: 65, activityIndex: 5
        )!, 40, accuracy: 1e-8)
    }

    func testLowerRHRAndMoreActivityLeadToYoungerFitnessComparison() {
        let baseline = FitnessAgeModel.calculate(
            age: 40, sex: .male, restingHR: 65, activityIndex: 5
        )!
        let improved = FitnessAgeModel.calculate(
            age: 40, sex: .male, restingHR: 53, activityIndex: 8
        )!
        XCTAssertLessThan(improved, baseline)
    }

    func testCannotInferFromUnspecifiedSexOrInvalidInputs() {
        XCTAssertNil(FitnessAgeModel.calculate(age: 40, sex: .unspecified,
                                              restingHR: 55, activityIndex: 5))
        XCTAssertNil(FitnessAgeModel.calculate(age: 40, sex: .male,
                                              restingHR: -5, activityIndex: 5))
        XCTAssertNil(FitnessAgeModel.calculate(age: 40, sex: .female,
                                              restingHR: 55, activityIndex: .nan))
    }

    func testActivityBucketsStayInRange() {
        XCTAssertEqual(FitnessAgeModel.activityIndex(
            activeDays: 0, averageMinutes: 0, highIntensityFraction: 0
        ), 0)
        XCTAssertEqual(FitnessAgeModel.activityIndex(
            activeDays: 7, averageMinutes: 70, highIntensityFraction: 0.7
        ), 15)
        XCTAssertNil(FitnessAgeModel.activityIndex(
            activeDays: 7, averageMinutes: 70, highIntensityFraction: 1.4
        ))
    }

    private func recordedDays() -> [DayMetrics] {
        ["2026-11-08", "2026-11-09", "2026-11-10", "2026-11-11"].map {
            DayMetrics(dateKey: $0, state: "sleep", restingHR: 54,
                       lnRMSSD: 4.0, hrvWindowSeconds: 120,
                       sleepHours: 7.5, sleepStartUnix: nil,
                       sleepEndUnix: nil, strain: 10, steps: 9000)
        }
    }

    private func referenceDate() -> Date {
        Calendar.current.date(from: DateComponents(
            year: 2026, month: 11, day: 11, hour: 12
        ))!
    }

    private func runningSession() -> ActivitySession {
        let start = Int(Calendar.current.date(from: DateComponents(
            year: 2026, month: 11, day: 10, hour: 7
        ))!.timeIntervalSince1970)
        return ActivitySession(startUnix: start,
                               endUnix: start + 1800,
                               kind: "run", steps: 4500,
                               meanHR: 150, walkTicks: 0, runTicks: 1800)
    }

    func testBaselineCoverageUsesSameRollingWindowAsFitnessEstimate() {
        let date = Calendar.current.date(byAdding: .day, value: 4, to: referenceDate())!
        let coverage = FitnessAgeModel.baselineCoverage(days: recordedDays(), asOf: date)
        XCTAssertEqual(coverage.restingNights, 3)
        XCTAssertEqual(coverage.stepDays, 3)
    }

    func testValidMeasuredWeekProducesFiniteFitnessAge() {
        let result = FitnessAgeModel.snapshot(
            age: 35, sex: .male, ageConfirmed: true,
            days: recordedDays(), detected: [runningSession()],
            live: [], asOf: referenceDate()
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.restingNights, 4)
        XCTAssertEqual(result?.capturedDays, 4)
        XCTAssertEqual(result?.exerciseDays, 1)
        XCTAssertTrue(result!.years.isFinite)
    }

    func testDefaultUnconfirmedAgeIsNeverUsed() {
        XCTAssertNil(FitnessAgeModel.snapshot(
            age: 30, sex: .male, ageConfirmed: false,
            days: recordedDays(), detected: [runningSession()],
            live: [], asOf: referenceDate()
        ))
    }

    func testMissingWorkoutAndSparseSyncReturnNoNumber() {
        XCTAssertNil(FitnessAgeModel.snapshot(
            age: 35, sex: .male, ageConfirmed: true,
            days: recordedDays(), detected: [],
            live: [], asOf: referenceDate()
        ))
        XCTAssertNil(FitnessAgeModel.snapshot(
            age: 35, sex: .male, ageConfirmed: true,
            days: Array(recordedDays().prefix(3)),
            detected: [runningSession()], live: [],
            asOf: referenceDate()
        ))
    }

    func testSameSessionFromLiveAndHistoryIsCountedOnce() {
        let run = runningSession()
        let live = LiveActivityRecord(
            dateKey: "2026-11-10",
            startedUnix: run.startUnix, endedUnix: run.endUnix,
            meanHR: 150, maxHR: 165, beats: 1800,
            hrv: .empty, zoneSeconds: [0, 0, 300, 700, 800]
        )
        let result = FitnessAgeModel.snapshot(
            age: 35, sex: .male, ageConfirmed: true,
            days: recordedDays(), detected: [run],
            live: [live], asOf: referenceDate()
        )
        let alone = FitnessAgeModel.snapshot(
            age: 35, sex: .male, ageConfirmed: true,
            days: recordedDays(), detected: [run],
            live: [], asOf: referenceDate()
        )
        XCTAssertEqual(result?.physicalActivityIndex,
                       alone?.physicalActivityIndex)
    }
}

final class HealthspanInputCoverageTests: XCTestCase {
    func testMissingMetricsAreNotInterpretedAsZero() {
        let coverage = HealthspanInputCoverage(observations: [:], asOf: Date())
        XCTAssertEqual(coverage.missingContributors.count, 9)
        XCTAssertTrue(coverage.missing(.steps, minimumDays: 7, windowDays: 30))
    }

    func testNinePublishedContributorsAreDistinct() {
        XCTAssertEqual(Set(HealthspanContributor.allCases).count, 9)
    }

    func testValidObservationIsPresentButDoesNotImplySixMonthCoverage() {
        let now = Date()
        let sample = HealthspanObservation(value: 9000, observedDays: 7,
                                            firstObserved: now.addingTimeInterval(-6 * 86400),
                                            lastObserved: now)
        let coverage = HealthspanInputCoverage(observations: [.steps: sample], asOf: now)
        XCTAssertTrue(coverage.availableContributors.contains(.steps))
        XCTAssertTrue(coverage.missing(.steps, minimumDays: 30, windowDays: 180))
        XCTAssertFalse(coverage.missing(.steps, minimumDays: 7, windowDays: 30))
    }
}


final class RRBeatDurationAuditTests: XCTestCase {
    func testRepeatedSecondDoesNotDoubleCountBeatDuration() {
        let result = HistoryCoverage.beatDurationAudit([
            (second: 100, intervalsMS: [800]),
            (second: 100, intervalsMS: [800, 810]),
            (second: 101, intervalsMS: [790])
        ])
        XCTAssertEqual(result.uniqueSeconds, 2)
        XCTAssertEqual(result.totalRRDurationMS, 2_400)
        XCTAssertFalse(result.exceedsObservedSpan)
    }

    func testImplausibleDurationOverflowIsFlaggedButNotDiscarded() {
        let result = HistoryCoverage.beatDurationAudit([
            (second: 100, intervalsMS: [1_500, 1_500, 1_500, 1_500]),
            (second: 101, intervalsMS: [1_500, 1_500, 1_500, 1_500])
        ])
        XCTAssertTrue(result.exceedsObservedSpan)
        XCTAssertEqual(result.totalRRDurationMS, 12_000)
    }

    func testNonpositiveRRIntervalsAreDiagnosedWithoutDiscardingHistory() {
        let result = HistoryCoverage.beatDurationAudit([
            (second: 100, intervalsMS: [800, 0, -5]),
            (second: 101, intervalsMS: [790])
        ])
        XCTAssertEqual(result.invalidIntervals, 2)
        XCTAssertEqual(result.totalRRDurationMS, 1_590)
    }

    func testEmptyAndNormalRRWindowsAreSafe() {
        XCTAssertFalse(HistoryCoverage.beatDurationAudit([]).exceedsObservedSpan)
        XCTAssertFalse(HistoryCoverage.beatDurationAudit([
            (second: 100, intervalsMS: [900]),
            (second: 101, intervalsMS: [900])
        ]).exceedsObservedSpan)
    }
}
