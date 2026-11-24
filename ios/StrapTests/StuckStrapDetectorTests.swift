import XCTest
@testable import Strap

final class StuckStrapDetectorTests: XCTestCase {
    func testAdvancingFrontierIsNeverStuck() {
        var detector = StuckStrapDetector(stuckAfterSeconds: 60.0, behindGapSeconds: 300)
        // Seed
        XCTAssertFalse(detector.observe(strapNewestTs: 1786001000, ourFrontierTs: 1786000000, now: 100.0))
        // Progress at t=130s
        XCTAssertFalse(detector.observe(strapNewestTs: 1786001000, ourFrontierTs: 1786000500, now: 130.0))
        // Progress at t=170s
        XCTAssertFalse(detector.observe(strapNewestTs: 1786001000, ourFrontierTs: 1786000900, now: 170.0))
    }

    func testCaughtUpIsNeverStuck() {
        var detector = StuckStrapDetector(stuckAfterSeconds: 60.0, behindGapSeconds: 300)
        // Gap only 50s (<= 300s)
        XCTAssertFalse(detector.observe(strapNewestTs: 1786000050, ourFrontierTs: 1786000000, now: 100.0))
        // 100s later, gap still 50s
        XCTAssertFalse(detector.observe(strapNewestTs: 1786000050, ourFrontierTs: 1786000000, now: 200.0))
    }

    func testStuckDetectedWhenBehindAndFrozen() {
        var detector = StuckStrapDetector(stuckAfterSeconds: 60.0, behindGapSeconds: 300)
        // Strap 2000s ahead (> 300s)
        XCTAssertFalse(detector.observe(strapNewestTs: 1786002000, ourFrontierTs: 1786000000, now: 100.0))
        // At t=130s (30s elapsed < 60s)
        XCTAssertFalse(detector.observe(strapNewestTs: 1786002000, ourFrontierTs: 1786000000, now: 130.0))
        // At t=161s (61s elapsed >= 60s) -> STUCK!
        XCTAssertTrue(detector.observe(strapNewestTs: 1786002000, ourFrontierTs: 1786000000, now: 161.0))
    }

    func testRecoveringFromStuck() {
        var detector = StuckStrapDetector(stuckAfterSeconds: 60.0, behindGapSeconds: 300)
        _ = detector.observe(strapNewestTs: 1786002000, ourFrontierTs: 1786000000, now: 100.0)
        XCTAssertTrue(detector.observe(strapNewestTs: 1786002000, ourFrontierTs: 1786000000, now: 165.0))
        // Unblocked at t=170s
        XCTAssertFalse(detector.observe(strapNewestTs: 1786002000, ourFrontierTs: 1786000500, now: 170.0))
    }

    func testMissingTimestampsDoNotTriggerStuck() {
        var detector = StuckStrapDetector(stuckAfterSeconds: 60.0, behindGapSeconds: 300)
        XCTAssertFalse(detector.observe(strapNewestTs: nil, ourFrontierTs: 1786000000, now: 100.0))
        XCTAssertFalse(detector.observe(strapNewestTs: 1786002000, ourFrontierTs: nil, now: 100.0))
    }
}
