import Foundation
import XCTest
@testable import Strap

private let base = 1_720_000_000

private func makeNight(
    minutes: Int = 60,
    hr: Double = 53,
    bursts: [(Int, Int)] = [],
    breathing: Bool = true,
    heartRateOverride: Int? = nil
) -> ([V18Sample], SleepPeriod) {
    var samples: [V18Sample] = []
    let seconds = minutes * 60
    for second in 0..<seconds {
        var rate = hr + 1.5 * sin(2 * Double.pi * Double(second) / 2400.0)
        var gravity = (0.0, 0.0, 1.0)
        for (startMinute, endMinute) in bursts
        where startMinute * 60 <= second && second < endMinute * 60 {
            gravity = (
                0.6 * sin(Double(second) * 7.1),
                0.6 * cos(Double(second) * 5.3),
                1.0 + 0.4 * sin(Double(second) * 3.7)
            )
            rate = 88
        }
        let rr = breathing ? [Int(1000 + 45 * sin(2 * Double.pi * Double(second) / 4.0))] : []
        samples.append(
            V18Sample(
                header: BandRecordHeader(
                    version: 18, flags: 0x80, recordIndex: UInt32(second),
                    unix: UInt32(base + second), subsecQ15: 0
                ),
                heartRate: heartRateOverride ?? Int(rate.rounded()),
                rrIntervalsMS: rr,
                dynamicAccelG: 0.02,
                gravityXG: gravity.0,
                gravityYG: gravity.1,
                gravityZG: gravity.2,
                stepCounter: nil,
                stepCadence: nil,
                activityClass: nil,
                skinTempC: nil,
                tempAux1C: nil,
                tempAux2C: nil,
                sleepStateByte: nil,
                sleepState: nil,
                cardiacFlags: nil,
                hrQualityFlags: nil,
                spo2CandidateRaw: nil,
                spo2CandidatePct: nil,
                spo2CandidateKind: .absent,
                signalQualityLogVariance: nil,
            psnrB: nil,
            psnrA: nil
            )
        )
    }
    let period = SleepPeriod(
        startUnix: base,
        endUnix: base + seconds - 1,
        quietFraction: 0.95,
        meanHR: hr,
        wakeEvents: 0
    )
    return (samples, period)
}

final class SleepStageTests: XCTestCase {

    func testQuietNightTilesTheWindow() throws {
        let (samples, period) = makeNight()
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertNil(staging.reason)
        XCTAssertTrue(staging.stageable)

        let segments = try XCTUnwrap(staging.segments.first)
        XCTAssertEqual(segments.startUnix, period.startUnix)
        XCTAssertEqual(staging.segments.last?.endUnix, period.endUnix + 1)
        for (left, right) in zip(staging.segments, staging.segments.dropFirst()) {
            XCTAssertEqual(left.endUnix, right.startUnix)
        }
        XCTAssertEqual(staging.totalMinutes, 60, accuracy: 0.001)
    }

    func testQuietNightIsMostlyLightWithoutWake() {
        let (samples, period) = makeNight()
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertEqual(staging.wakeMinutes, 0)
        XCTAssertGreaterThan(staging.lightMinutes, staging.deepMinutes)
        XCTAssertGreaterThan(staging.restorativeMinutes, 0)
        XCTAssertEqual(staging.asleepMinutes + staging.wakeMinutes, staging.totalMinutes, accuracy: 0.001)
    }

    func testTotalsMatchSegments() {
        let (samples, period) = makeNight(bursts: [(20, 23)])
        let staging = SleepStager.stage(samples: samples, period: period)
        for stage in SleepStage.allCases {
            let expected = staging.segments
                .filter { $0.stage == stage }
                .reduce(0.0) { $0 + $1.minutes }
            XCTAssertEqual(staging.minutes(for: stage), expected, accuracy: 0.001)
        }
    }

    func testMotionBurstsAreStagedAsWake() {
        let (samples, period) = makeNight(bursts: [(20, 24)])
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertNil(staging.reason)
        XCTAssertGreaterThan(staging.wakeMinutes, 0)
        XCTAssertTrue(staging.segments.contains { $0.stage == .wake })
    }

    func testMissingHeartRateRefusesToInventStages() {
        let (samples, period) = makeNight(heartRateOverride: 0)
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertFalse(staging.stageable)
        XCTAssertTrue(staging.segments.isEmpty)
        XCTAssertEqual(staging.totalMinutes, 0)
        XCTAssertTrue(staging.reason?.contains("heart rate covers 0%") == true)
    }

    func testShortWindowRefuses() {
        let period = SleepPeriod(
            startUnix: 100, endUnix: 110, quietFraction: 1, meanHR: 50, wakeEvents: 0
        )
        let staging = SleepStager.stage(samples: [], period: period)
        XCTAssertTrue(staging.reason?.contains("shorter than one") == true)
        XCTAssertTrue(staging.segments.isEmpty)
    }
}
