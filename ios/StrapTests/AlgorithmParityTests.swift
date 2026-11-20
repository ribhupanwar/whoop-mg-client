import XCTest
@testable import Strap

final class AlgorithmParityTests: XCTestCase {

    func testMaxSleepWindowMatchesTwelveHours() {
        // Verified from WHOOP 5.80.2 WhoopSleepCoach/SleepWindows/SleepWindow.swift (TWELVE_HOUR)
        XCTAssertEqual(SleepDetect.maxSleepS, 12 * 3600)
        XCTAssertEqual(SleepDetect.maxSleepS, 43200)
    }

    func testActivityDuplicateSuppression() {
        // Auto-detected sessions overlapping by >= 50% must be suppressed (WHOOP ActivityEntity parity)
        let s1 = ActivitySession(
            startUnix: 1000,
            endUnix: 2000,
            kind: "run",
            steps: 1000,
            meanHR: 145.0,
            walkTicks: 0,
            runTicks: 500
        )
        // s2 overlaps with s1 from 1200 to 2000 (800s out of 1000s duration = 80%)
        let s2 = ActivitySession(
            startUnix: 1200,
            endUnix: 2200,
            kind: "run",
            steps: 900,
            meanHR: 140.0,
            walkTicks: 0,
            runTicks: 450
        )
        // s3 does not overlap (starts at 3000)
        let s3 = ActivitySession(
            startUnix: 3000,
            endUnix: 4000,
            kind: "walk",
            steps: 800,
            meanHR: 110.0,
            walkTicks: 400,
            runTicks: 0
        )

        let result = ActivityDetect.suppressDuplicates([s1, s2, s3])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].startUnix, 1000)
        XCTAssertEqual(result[1].startUnix, 3000)
    }

    func testSwsRestingHRVFallback() {
        // When deep epochs have no samples, falls back to quiet window cleanly
        let fallback = Hrv.swsRestingHRV([], deepEpochs: [100...200], minWindowS: 300)
        XCTAssertFalse(fallback.isSWS)
        XCTAssertEqual(fallback.windowSeconds, 0)
    }
}
