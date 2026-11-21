import Foundation
import XCTest
@testable import Strap

final class SleepBathroomBreakMergingTests: XCTestCase {
    private func makeV18Sample(
        unix: Int, hr: Int, accel: Double, wearing: Bool = true, state: Int? = 2
    ) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(
                version: 18, flags: 0x80, recordIndex: UInt32(unix % 100000),
                unix: UInt32(unix), subsecQ15: 0
            ),
            heartRate: hr,
            rrIntervalsMS: [Int(60000 / max(1, hr))],
            dynamicAccelG: accel,
            gravityXG: 0, gravityYG: 0, gravityZG: 1,
            stepCounter: nil, stepCadence: nil, activityClass: nil,
            skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: nil, sleepState: state,
            cardiacFlags: nil, hrQualityFlags: nil,
            spo2CandidateRaw: nil, spo2CandidatePct: nil,
            spo2CandidateKind: .absent,
            signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
        )
    }

    func testNocturnalBathroomBreakMergesIntoSingleSleepSession() {
        var samples: [V18Sample] = []
        let baseUnix = 1795039200 // Overnight timestamp

        // 1. Daytime / active reference (1 hour at HR 85, accel 0.15) to establish active median
        for i in 0..<3600 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 85, accel: 0.15, state: 0))
        }

        // 2. Sleep segment 1: 3 hours (10,800s) from base+3600 to base+14400, HR 55, accel 0.01, state 2
        for i in 3600..<14400 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 55, accel: 0.01, state: 2))
        }

        // 3. Bathroom break: 12 minutes (720s) from base+14400 to base+15120, HR 88, accel 0.20, state 3 (up)
        for i in 14400..<15120 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 88, accel: 0.20, state: 3))
        }

        // 4. Sleep segment 2: 3 hours (10,800s) from base+15120 to base+25920, HR 54, accel 0.01, state 2
        for i in 15120..<25920 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 54, accel: 0.01, state: 2))
        }

        // 5. Wake-up reference (30 minutes at HR 85, accel 0.15)
        for i in 25920..<27720 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 85, accel: 0.15, state: 0))
        }

        let detected = SleepDetect.detect(samples)
        XCTAssertEqual(detected.count, 1, "Nocturnal bathroom break must be merged into a single overnight sleep session")

        guard let night = detected.first else {
            XCTFail("Expected 1 detected night")
            return
        }
        XCTAssertEqual(night.startUnix, baseUnix + 3600)
        XCTAssertEqual(night.endUnix, baseUnix + 25920 - 1)
        XCTAssertGreaterThanOrEqual(night.wakeEvents, 1, "Wake events must capture the nocturnal bathroom interruption")

        // Run staging on the merged period: verify bathroom break is scored as wake minutes
        let staging = SleepStager.stage(samples: samples, period: night)
        XCTAssertGreaterThanOrEqual(staging.wakeMinutes, 10, "Bathroom break must be staged as awake time in bed")
        XCTAssertGreaterThan(staging.asleepMinutes, 300, "Asleep minutes must combine both sleep segments")
    }

    func testLongAwakeningDoesNotMergeIntoSingleSession() {
        var samples: [V18Sample] = []
        let baseUnix = 1795039200

        // Active baseline
        for i in 0..<3600 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 85, accel: 0.15, state: 0))
        }

        // Segment 1 (3 hours sleep)
        for i in 3600..<14400 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 55, accel: 0.01, state: 2))
        }

        // 2 hours awake (7200s > 1800s threshold)
        for i in 14400..<21600 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 85, accel: 0.15, state: 0))
        }

        // Segment 2 (2 hours sleep)
        for i in 21600..<28800 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 55, accel: 0.01, state: 2))
        }

        let detected = SleepDetect.detect(samples)
        XCTAssertEqual(detected.count, 2, "Sleep segments separated by >30 minutes of wakefulness must remain separate sessions")
    }

    func testOffWristGapDoesNotMergeAsBathroomBreak() {
        var samples: [V18Sample] = []
        let baseUnix = 1795039200

        // Active baseline
        for i in 0..<3600 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 85, accel: 0.15, state: 0))
        }

        // Segment 1 (3 hours sleep)
        for i in 3600..<14400 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 55, accel: 0.01, state: 2))
        }

        // 15 minutes off-wrist gap (wearing == false)
        for i in 14400..<15300 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 0, accel: 0, wearing: false, state: nil))
        }

        // Segment 2 (3 hours sleep)
        for i in 15300..<26100 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 55, accel: 0.01, state: 2))
        }

        let detected = SleepDetect.detect(samples)
        XCTAssertEqual(detected.count, 2, "An off-wrist band gap must not be merged as an in-bed bathroom break")
    }

    func testGapWithMostlyOffWristSamplesDoesNotMerge() {
        var samples: [V18Sample] = []
        let baseUnix = 1795039200

        for i in 0..<3600 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 85, accel: 0.15, state: 0))
        }
        for i in 3600..<14400 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 55, accel: 0.01, state: 2))
        }
        // 15-minute gap with mostly off-wrist samples and an isolated worn sample
        for i in 14400..<15300 {
            let isGlitch = (i == 14500)
            samples.append(makeV18Sample(unix: baseUnix + i, hr: isGlitch ? 60 : 0, accel: 0, wearing: isGlitch, state: nil))
        }
        for i in 15300..<26100 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 55, accel: 0.01, state: 2))
        }

        let detected = SleepDetect.detect(samples)
        XCTAssertEqual(detected.count, 2, "A gap dominated by off-wrist records with an isolated worn sample must not merge as an in-bed break")
    }

    func testGenuineSleepExceedingTwelveHoursIsPreserved() {
        var samples: [V18Sample] = []
        let baseUnix = 1795039200

        // 1. Active daytime baseline (1 hour)
        for i in 0..<3600 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 85, accel: 0.15, state: 0))
        }

        // 2. Continuous 13-hour recovery sleep (46,800 seconds)
        let sleepStart = baseUnix + 3600
        let sleepEnd = sleepStart + 13 * 3600
        for u in sleepStart..<sleepEnd {
            samples.append(makeV18Sample(unix: u, hr: 55, accel: 0.01, state: 2))
        }

        // 3. Morning wake baseline (30 minutes)
        for u in sleepEnd..<(sleepEnd + 1800) {
            samples.append(makeV18Sample(unix: u, hr: 85, accel: 0.15, state: 0))
        }

        let detected = SleepDetect.detect(samples)
        XCTAssertEqual(detected.count, 1, "Genuine sleep > 12 hours must not be discarded")
        if let night = detected.first {
            XCTAssertEqual(night.startUnix, sleepStart)
            XCTAssertEqual(night.endUnix, sleepEnd - 1)
            XCTAssertEqual(night.durationS, 13 * 3600)
        }
    }

    func testLeadingAwakeUpIsTrimmedFromOvernightOnset() {
        var samples: [V18Sample] = []
        let baseUnix = 1795039200

        // 1. Active baseline (1 hour)
        for i in 0..<3600 {
            samples.append(makeV18Sample(unix: baseUnix + i, hr: 85, accel: 0.15, state: 0))
        }

        // 2. Awake in bed reading/moving for 10 minutes (state 3, HR 78, accel 0.04)
        let awakeLeadStart = baseUnix + 3600
        let awakeLeadEnd = awakeLeadStart + 600
        for u in awakeLeadStart..<awakeLeadEnd {
            samples.append(makeV18Sample(unix: u, hr: 78, accel: 0.04, state: 3))
        }

        // 3. Settled sleep for 7 hours (state 2, HR 54, accel 0.01)
        let settledStart = awakeLeadEnd
        let settledEnd = settledStart + 7 * 3600
        for u in settledStart..<settledEnd {
            samples.append(makeV18Sample(unix: u, hr: 54, accel: 0.01, state: 2))
        }

        // 4. Morning wake baseline (30 minutes)
        for u in settledEnd..<(settledEnd + 1800) {
            samples.append(makeV18Sample(unix: u, hr: 85, accel: 0.15, state: 0))
        }

        let detected = SleepDetect.detect(samples)
        XCTAssertEqual(detected.count, 1)
        if let night = detected.first {
            XCTAssertEqual(night.startUnix, settledStart, "Sustained leading up(3) state must be trimmed from sleep onset")
            XCTAssertEqual(night.endUnix, settledEnd - 1)
        }
    }
}
