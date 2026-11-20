import XCTest
@testable import Strap

final class ReconnectBackoffPolicyTests: XCTestCase {

    func testDelaysFollowBoundedExponentialSchedule() {
        XCTAssertEqual(ReconnectBackoffPolicy.delays, [1, 2, 4, 8, 16, 30])
        XCTAssertEqual(ReconnectBackoffPolicy.maximumAttempts, 6)
    }

    func testDelayForAttemptReturnsExpectedValues() {
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 0), 1.0)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 1), 1.0)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 2), 2.0)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 3), 4.0)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 4), 8.0)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 5), 16.0)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 6), 30.0)
        // Values beyond maximum attempts clamp to 30.0s cap
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 7), 30.0)
        XCTAssertEqual(ReconnectBackoffPolicy.delay(forAttempt: 100), 30.0)
    }

    func testJitteredDelayRemainsWithinBoundedWindow() {
        for attempt in 1...6 {
            let base = ReconnectBackoffPolicy.delay(forAttempt: attempt)
            let lowerBound = base * 0.90 - 0.001
            let upperBound = base * 1.10 + 0.001
            for _ in 0..<50 {
                let jittered = ReconnectBackoffPolicy.jitteredDelay(forAttempt: attempt, jitterFraction: 0.10)
                XCTAssertGreaterThanOrEqual(jittered, lowerBound, "Attempt \(attempt) jittered delay below lower bound")
                XCTAssertLessThanOrEqual(jittered, upperBound, "Attempt \(attempt) jittered delay above upper bound")
            }
        }
    }
}
