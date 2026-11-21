import XCTest
@testable import Strap

final class ActivityReplayBoundaryTests: XCTestCase {
    private func session(start: Int, duration: Int) -> ActivitySession {
        ActivitySession(
            startUnix: start, endUnix: start + duration - 1, kind: "workout",
            steps: 0, meanHR: 120, walkTicks: 0, runTicks: 0
        )
    }

    func testLongStoredDetectionDoesNotAbsorbDistinctReplaySessions() throws {
        let suite = "ActivityReplayBoundaryTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ActivityStore(defaults: defaults)
        let long = session(start: 1_800_000_000, duration: 189 * 60)
        let first = session(start: long.startUnix + 30 * 60, duration: 15 * 60)
        let second = session(start: long.startUnix + 150 * 60, duration: 15 * 60)

        store.mergeDetected([long])
        store.mergeDetected([first, second])

        XCTAssertEqual(store.detectedActivities().map(\.startUnix), [
            long.startUnix, first.startUnix, second.startUnix
        ])
    }

    func testDeletingLongDetectionDoesNotSuppressNestedReplaySessions() throws {
        let suite = "ActivityReplayBoundaryTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ActivityStore(defaults: defaults)
        let long = session(start: 1_800_000_000, duration: 189 * 60)
        let first = session(start: long.startUnix + 30 * 60, duration: 15 * 60)
        let second = session(start: long.startUnix + 150 * 60, duration: 15 * 60)

        store.mergeDetected([long])
        store.deleteDetected(long)
        store.mergeDetected([first, second])

        XCTAssertEqual(store.detectedActivities().map(\.startUnix), [first.startUnix, second.startUnix])
        XCTAssertTrue(store.isDetectedDeleted(long))
    }
}
