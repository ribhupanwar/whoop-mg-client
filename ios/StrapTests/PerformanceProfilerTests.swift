#if DEBUG
import XCTest
@testable import Strap

final class PerformanceProfilerTests: XCTestCase {
    private enum CommitError: Error, Equatable {
        case failed
    }

    func testHistoryCommitProfilingPreservesResultAndRunsOnce() {
        var invocationCount = 0
        let value = PerformanceProfiler.measureHistoryCommit {
            invocationCount += 1
            return 42
        }

        XCTAssertEqual(value, 42)
        XCTAssertEqual(invocationCount, 1)
    }

    func testHistoryCommitProfilingPropagatesFailureWithoutRetry() {
        var invocationCount = 0
        XCTAssertThrowsError(try PerformanceProfiler.measureHistoryCommit {
            invocationCount += 1
            throw CommitError.failed
        }) { error in
            XCTAssertEqual(error as? CommitError, .failed)
        }
        XCTAssertEqual(invocationCount, 1)
    }
}
#endif
