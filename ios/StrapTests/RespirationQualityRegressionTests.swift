import Foundation
import XCTest
@testable import Strap

final class RespirationQualityRegressionTests: XCTestCase {
    private func row(_ unix: Int, rr: [Int], hr: Int = 60, motion: Double? = 0.01) -> V18Sample {
        V18Sample(header: BandRecordHeader(version: 18, flags: 0x80,
            recordIndex: UInt32(unix), unix: UInt32(unix), subsecQ15: 0),
            heartRate: hr, rrIntervalsMS: rr, dynamicAccelG: motion)
    }

    func testReplayPaddingCannotDisplaceValidBeats() {
        let valid = row(0, rr: [900, 920])
        let invalid = row(0, rr: [900, 0, 65535])
        for rows in [[invalid, valid], [valid, invalid]] {
            let segments = Respiration.beatSegments(rows)
            XCTAssertEqual(segments.count, 1)
            XCTAssertEqual(segments.first?.map { $0.rr }, [900, 920])
        }
    }

    func testMissingRRAndInvalidMotionSplitSegments() {
        let left = row(0, rr: [900])
        let right = row(2, rr: [920])
        let rejected = [
            row(1, rr: []),
            row(1, rr: [910], hr: 0),
            row(1, rr: [910], motion: nil),
            row(1, rr: [910], motion: -0.01),
            row(1, rr: [910], motion: .nan),
            row(1, rr: [910], motion: 0.5)
        ]
        for middle in rejected {
            let segments = Respiration.beatSegments([left, middle, right])
            XCTAssertEqual(segments.map { $0.map { $0.rr } }, [[900], [920]])
        }
    }
}
