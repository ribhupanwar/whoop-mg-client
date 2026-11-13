import Foundation
import XCTest
@testable import Strap

private let base = 1_720_000_000

private func makeNight(
    minutes: Int = 60,
    hr: Double = 53,
    bursts: [(Int, Int)] = [],
    breathing: Bool = true,
    heartRateOverride: Int? = nil,
    hrAvailableMinutes: Int? = nil,
    motion: Bool = true,
    bandWakeMinutes: (Int, Int)? = nil
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
        let state = bandWakeMinutes.map { range in
            range.0 * 60 <= second && second < range.1 * 60 ? 0 : 2
        }
        let measuredHR = heartRateOverride ?? ((hrAvailableMinutes.map { second < $0 * 60 } ?? true) ? Int(rate.rounded()) : 0)
        samples.append(
            V18Sample(
                header: BandRecordHeader(
                    version: 18, flags: 0x80, recordIndex: UInt32(second),
                    unix: UInt32(base + second), subsecQ15: 0
                ),
                heartRate: measuredHR,
                rrIntervalsMS: rr,
                dynamicAccelG: motion ? 0.02 : nil,
                gravityXG: motion ? gravity.0 : nil,
                gravityYG: motion ? gravity.1 : nil,
                gravityZG: motion ? gravity.2 : nil,
                stepCounter: nil,
                stepCadence: nil,
                activityClass: nil,
                skinTempC: nil,
                tempAux1C: nil,
                tempAux2C: nil,
                sleepStateByte: state,
                sleepState: state,
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

    func testBandWakeStatePreservesAwakePhoneUseInsideSleepWindow() {
        let (samples, period) = makeNight(bandWakeMinutes: (20, 26))
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertTrue(staging.stageable)
        XCTAssertGreaterThan(staging.wakeMinutes, 4.5)
        XCTAssertTrue(staging.segments.contains { $0.stage == .wake })
    }

    func testMissingHeartRateRefusesToInventStages() {
        let (samples, period) = makeNight(heartRateOverride: 0)
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertFalse(staging.stageable)
        XCTAssertTrue(staging.segments.isEmpty)
        XCTAssertEqual(staging.totalMinutes, 60, accuracy: 0.001)
        XCTAssertEqual(staging.unclassifiedMinutes ?? 0, 60, accuracy: 0.001)
        XCTAssertTrue(staging.reason?.contains("heart rate covers 0%") == true)
    }

    func testBriefMovementDoesNotRemoveWholeSleepTime() {
        var quiet = Array(repeating: true, count: 600)
        for second in 120..<180 { quiet[second] = false }
        XCTAssertEqual(SleepDetect.estimatedAsleepFraction(quiet: quiet, unix: Array(0..<600)), 1, accuracy: 0.001)
    }

    func testSustainedPhoneMotionCountsAsAwakeWhenHeartRateRises() {
        var quiet = Array(repeating: true, count: 600)
        for second in 120..<300 { quiet[second] = false }
        let heartRates = (0..<600).map { Optional((120..<300).contains($0) ? 88 : 55) }
        XCTAssertEqual(
            SleepDetect.estimatedAsleepFraction(
                quiet: quiet, unix: Array(0..<600), heartRates: heartRates
            ),
            0.7,
            accuracy: 0.01
        )
    }

    func testSustainedMotionWithoutHeartRateRiseIsNotCountedAsAwake() {
        var quiet = Array(repeating: true, count: 600)
        for second in 120..<300 { quiet[second] = false }
        let heartRates = Array(repeating: Optional(55), count: 600)
        XCTAssertEqual(
            SleepDetect.estimatedAsleepFraction(
                quiet: quiet, unix: Array(0..<600), heartRates: heartRates
            ),
            1.0,
            accuracy: 0.01
        )
    }

    func testReliableBandWakeStateCountsStillPhoneUseAsAwake() {
        let unix = Array(0..<3600)
        let states = unix.map { second in Optional((1200..<1500).contains(second) ? 0 : 2) }
        XCTAssertEqual(SleepDetect.estimatedAsleepFraction(quiet: Array(repeating: true, count: 3600), unix: unix, sleepStates: states), 55.0 / 60.0, accuracy: 0.001)
    }

    func testMovementSamplesAreCoalescedIntoOneBout() {
        let quiet = Array(repeating: true, count: 20) + Array(repeating: false, count: 120) + Array(repeating: true, count: 20)
        let unix = Array(0..<quiet.count)
        XCTAssertEqual(SleepDetect.movementBoutCount(quiet: quiet, unix: unix), 1)
    }

    func testShortMotionNoiseDoesNotBecomeAwakening() {
        var quiet = Array(repeating: true, count: 120)
        for start in stride(from: 10, to: 100, by: 10) { quiet[start] = false }
        XCTAssertEqual(SleepDetect.movementBoutCount(quiet: quiet, unix: Array(0..<quiet.count)), 0)
    }

    func testManualWindowSurvivesDetectorOnsetChangeByWakeDay() {
        let calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let start = Int(formatter.date(from: "2026-11-05 22:18")!.timeIntervalSince1970)
        let end = Int(formatter.date(from: "2026-11-06 06:30")!.timeIntervalSince1970)
        let original = SleepPeriod(startUnix: start - 600, endUnix: end, quietFraction: 0.8, meanHR: 55, wakeEvents: 0)
        let restaged = SleepPeriod(startUnix: start, endUnix: end, quietFraction: 0.8, meanHR: 55, wakeEvents: 0)
        let manualTimes = [start, end]
        let saved = [SleepCorrectionStore.key(for: original, timeZone: zone): manualTimes]
        XCTAssertEqual(end - start, 8 * 3600 + 12 * 60)
        XCTAssertEqual(SleepCorrectionStore.times(for: restaged, overrides: saved, timeZone: zone), manualTimes)
        XCTAssertEqual(SleepCorrectionStore.estimatedAsleepHours(period: restaged, editedTimes: manualTimes), restaged.hours * restaged.quietFraction, accuracy: 0.001)
        XCTAssertLessThan(SleepCorrectionStore.estimatedAsleepHours(period: restaged, editedTimes: manualTimes), Double(end - start) / 3600.0)
        _ = calendar
    }

    func testFortyThreePercentCoverageLeavesWholeWindowUnclassified() {
        let (samples, period) = makeNight(hrAvailableMinutes: 26)
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertFalse(staging.stageable)
        XCTAssertTrue(staging.reason?.contains("43%") == true)
        XCTAssertEqual(staging.unclassifiedMinutes ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(staging.totalMinutes, 60, accuracy: 0.001)
        XCTAssertEqual(staging.hrObservedSeconds, 26 * 60)
        XCTAssertEqual(staging.hrWindowSeconds, 60 * 60)
        XCTAssertEqual(staging.longestHRGapSeconds, 34 * 60)
    }

    func testMissingMotionIsUnknownRatherThanInventedStillness() {
        let (samples, period) = makeNight(motion: false)
        let staging = SleepStager.stage(samples: samples, period: period)
        XCTAssertTrue(staging.stageable)
        XCTAssertEqual(staging.totalMinutes, 60, accuracy: 0.001)
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
