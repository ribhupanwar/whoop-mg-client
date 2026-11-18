import XCTest
import CoreGraphics
@testable import Strap

final class ActivitySwipeIntentTests: XCTestCase {
    func testOnlyDeliberateHorizontalSwipeRevealsActionAndNeverCommitsDeletion() {
        XCTAssertEqual(ActivitySwipeIntent.resolve(CGSize(width: -90, height: 5)), .showDelete)
        XCTAssertEqual(ActivitySwipeIntent.resolve(CGSize(width: 70, height: 5)), .hideDelete)
        XCTAssertNil(ActivitySwipeIntent.resolve(CGSize(width: -90, height: 150)), "Vertical scrolling stays scrolling")
        XCTAssertNil(ActivitySwipeIntent.resolve(CGSize(width: -20, height: 0)), "A small movement is not a delete gesture")
        XCTAssertNil(ActivitySwipeIntent.resolve(CGSize(width: CGFloat.nan, height: 0)))
    }
}
