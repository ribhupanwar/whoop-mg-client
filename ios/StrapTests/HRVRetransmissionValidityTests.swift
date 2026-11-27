import XCTest
@testable import Strap

final class HRVRetransmissionValidityTests: XCTestCase {
    func testPaddedLongerReplayCannotDisplaceValidPayload() {
        XCTAssertFalse(Hrv.preferRetransmittedRR([0, 0, 800], over: [800]))
        XCTAssertFalse(Hrv.preferRetransmittedRR([0, 800, 0], over: [800]))
    }

    func testMoreValidBeatsWinDespitePadding() {
        XCTAssertTrue(Hrv.preferRetransmittedRR([800, 810, 0], over: [800]))
    }

    func testCleanerEquivalentReplayWins() {
        XCTAssertTrue(Hrv.preferRetransmittedRR([800], over: [800, 0]))
    }

    func testIdenticalAndEmptyReplayAreStable() {
        XCTAssertFalse(Hrv.preferRetransmittedRR([800], over: [800]))
        XCTAssertFalse(Hrv.preferRetransmittedRR([], over: []))
    }

    func testSameValidCountPrefersFewerInvalidWords() {
        XCTAssertTrue(Hrv.preferRetransmittedRR([800, 810], over: [800, 810, 0, 0]))
        XCTAssertFalse(Hrv.preferRetransmittedRR([800, 810, 0], over: [800, 810]))
    }

    func testConflictingEqualQualityRetransmissionKeepsFirstDeterministically() {
        XCTAssertFalse(Hrv.preferRetransmittedRR([820, 830], over: [800, 810]))
    }

}
