import XCTest

final class SleepFinalizationShadowTests: XCTestCase {
    private let end = 1_700_000_000
    private typealias Shadow = SleepFinalizationShadow

    private func tail(state: Int, count: Int = Shadow.horizon) -> [Shadow.Observation] {
        (0..<count).map { .init(unix: end + $0, state: state, usable: true) }
    }

    func testFullSleepTailRejectsPrematureEnd() {
        let r = Shadow.evaluate(endExclusive: end, archiveLastUnix: end + Shadow.horizon - 1,
                                edited: false, observations: tail(state: 2))
        XCTAssertEqual(r.verdict, .sleepObservedAfterEnd)
        XCTAssertEqual(r.sleepStateSeconds, Shadow.horizon)
    }

    func testIncompleteArchiveCannotFinalizeEvenWithUpState() {
        let r = Shadow.evaluate(endExclusive: end, archiveLastUnix: end + 599,
                                edited: false, observations: tail(state: 3, count: 600))
        XCTAssertEqual(r.verdict, .insufficientHorizon)
    }

    func testSparseHistoryCannotPassOnFrontierAlone() {
        let rows = tail(state: 3, count: 100) + [.init(unix: end + Shadow.horizon - 1, state: 3, usable: true)]
        let r = Shadow.evaluate(endExclusive: end, archiveLastUnix: end + Shadow.horizon - 1,
                                edited: false, observations: rows)
        XCTAssertEqual(r.verdict, .insufficientCoverage)
    }

    func testDenseAwakeTailOnlyPermitsExistingDecision() {
        let r = Shadow.evaluate(endExclusive: end, archiveLastUnix: end + Shadow.horizon - 1,
                                edited: false, observations: tail(state: 3))
        XCTAssertEqual(r.verdict, .eligibleForExistingDecision)
    }

    func testReturnedSleepBlocksDespiteEarlierUpState() {
        var rows = tail(state: 3)
        rows[200] = .init(unix: end + 200, state: 2, usable: true)
        let r = Shadow.evaluate(endExclusive: end, archiveLastUnix: end + Shadow.horizon - 1,
                                edited: false, observations: rows)
        XCTAssertEqual(r.verdict, .sleepObservedAfterEnd)
    }

    func testDuplicatesCannotInflateCoverageAndConflictCannotEraseSleep() {
        let row = Shadow.Observation(unix: end, state: 3, usable: true)
        let repeated = Array(repeating: row, count: Shadow.horizon)
        let r = Shadow.evaluate(endExclusive: end, archiveLastUnix: end + Shadow.horizon - 1,
                                edited: false, observations: repeated)
        XCTAssertEqual(r.observedSeconds, 1)
        XCTAssertEqual(r.verdict, .insufficientCoverage)
        let conflict = Shadow.Observation(unix: end, state: 2, usable: true)
        let c = Shadow.evaluate(endExclusive: end, archiveLastUnix: end + Shadow.horizon - 1,
                                edited: false, observations: repeated + [conflict])
        XCTAssertEqual(c.verdict, .sleepObservedAfterEnd)
        XCTAssertEqual(c.awakeStateSeconds, 0)
    }

    func testStillAndUnusableRowsCannotProveAwakeCoverage() {
        let rows = tail(state: 1) + tail(state: 3).map { Shadow.Observation(unix: $0.unix, state: $0.state, usable: false) }
        let r = Shadow.evaluate(endExclusive: end, archiveLastUnix: end + Shadow.horizon - 1,
                                edited: false, observations: rows)
        XCTAssertEqual(r.verdict, .insufficientCoverage)
        XCTAssertEqual(r.awakeStateSeconds, 0)
    }

    func testManualEditRemainsAuthoritative() {
        let r = Shadow.evaluate(endExclusive: end, archiveLastUnix: end + Shadow.horizon - 1,
                                edited: true, observations: tail(state: 2))
        XCTAssertEqual(r.verdict, .manualOverride)
    }
}
