import Foundation
import XCTest
@testable import Strap

final class ActivityExertionTests: XCTestCase {
    private func makeSample(
        unix: Int, hr: Int, accel: Double, steps: Int? = nil, gait: Int? = nil
    ) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(
                version: 18, flags: 0x80, recordIndex: UInt32(unix % 100000),
                unix: UInt32(unix), subsecQ15: 0
            ),
            heartRate: hr,
            rrIntervalsMS: [UInt16(60000 / max(1, hr))],
            dynamicAccelG: accel,
            gravityXG: 0, gravityYG: 0, gravityZG: 1,
            stepCounter: steps, stepCadence: nil, activityClass: gait,
            skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: nil, sleepState: 0,
            cardiacFlags: nil, hrQualityFlags: nil,
            spo2CandidateRaw: nil, spo2CandidatePct: nil,
            spo2CandidateKind: .absent,
            signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
        )
    }

    func testSedentaryStressDoesNotAutoSaveAsCardio() {
        var samples: [V18Sample] = []
        let baseUnix = 1795000000

        // 1. Resting baseline (300s at HR 65, accel 0.01)
        for i in 0..<300 {
            samples.append(makeSample(unix: baseUnix + i, hr: 65, accel: 0.01))
        }

        // 2. 600s sedentary stress: HR elevated to 125 BPM, but sitting still (accel 0.005, 0 steps)
        for i in 300..<900 {
            samples.append(makeSample(unix: baseUnix + i, hr: 125, accel: 0.005))
        }

        let detected = ActivityDetect.detect(samples, sleepPeriods: [])
        XCTAssertTrue(detected.isEmpty, "Sitting still with elevated HR due to psychological stress must NOT auto-save as a workout")
    }

    func testSustainedCardioWithMovementAutoSavesAndCalculatesStrain() {
        var samples: [V18Sample] = []
        let baseUnix = 1795000000

        // 1. Resting baseline (300s at HR 65, accel 0.01)
        for i in 0..<300 {
            samples.append(makeSample(unix: baseUnix + i, hr: 65, accel: 0.01))
        }

        // 2. 900s stationary bike/cycling: HR 145 BPM, continuous active motion (accel 0.06), no step counter
        for i in 300..<1200 {
            samples.append(makeSample(unix: baseUnix + i, hr: 145, accel: 0.06))
        }

        let detected = ActivityDetect.detect(samples, sleepPeriods: [], restingHR: 65, maxHR: 190)
        XCTAssertEqual(detected.count, 1, "Sustained cardio exercise with measured motion must be auto-detected")

        guard let cardio = detected.first else {
            XCTFail("Expected 1 cardio session")
            return
        }
        XCTAssertEqual(cardio.kind, "cardio")
        XCTAssertNotNil(cardio.strain, "Cardio session must calculate strain")
        if let strain = cardio.strain {
            XCTAssertGreaterThan(strain, 3.0, "15 minutes of cardio at 145 bpm must produce non-trivial strain")
        }
    }

    func testSustainedLowCadenceStrengthTrainingAutoSavesAndCalculatesStrain() {
        var samples: [V18Sample] = []
        let baseUnix = 1795000000

        // 1. Resting baseline (300s at HR 65, accel 0.01)
        for i in 0..<300 {
            samples.append(makeSample(unix: baseUnix + i, hr: 65, accel: 0.01))
        }

        // 2. 900s gym resistance training: HR 135 BPM, dynamic acceleration 0.05, low-cadence steps (~30 spm)
        var stepCount = 500
        for i in 300..<1200 {
            if i % 2 == 0 { stepCount += 1 }
            samples.append(makeSample(unix: baseUnix + i, hr: 135, accel: 0.05, steps: stepCount))
        }

        let detected = ActivityDetect.detect(samples, sleepPeriods: [], restingHR: 65, maxHR: 190)
        XCTAssertEqual(detected.count, 1, "Sustained strength training workout with low cadence must be auto-detected")

        guard let workout = detected.first else {
            XCTFail("Expected 1 workout session")
            return
        }
        XCTAssertEqual(workout.kind, "workout")
        XCTAssertNotNil(workout.strain, "Workout session must calculate strain")
        if let strain = workout.strain {
            XCTAssertGreaterThan(strain, 2.5, "15 minutes of weightlifting at 135 bpm must produce non-trivial strain")
        }
    }

    func testCasualStrollIsRejectedWhileBriskWalkIsAutoSaved() {
        let baseUnix = 1795000000

        // 1. Casual stroll (75 spm, HR 75, not elevated above baseline 65 + 20 = 85)
        var strollSamples: [V18Sample] = []
        for i in 0..<300 {
            strollSamples.append(makeSample(unix: baseUnix + i, hr: 65, accel: 0.01))
        }
        var strollSteps = 100
        for i in 300..<900 {
            if i % 4 != 0 { strollSteps += 1 } // ~75 spm
            strollSamples.append(makeSample(unix: baseUnix + i, hr: 75, accel: 0.04, steps: strollSteps))
        }
        let strollDetected = ActivityDetect.detect(strollSamples, sleepPeriods: [])
        XCTAssertTrue(strollDetected.isEmpty, "Casual walking stroll must NOT be auto-saved as a workout")

        // 2. Brisk walk (115 spm, HR 115, sustained elevated HR and brisk cadence >= 100 spm for 15 min)
        var walkSamples: [V18Sample] = []
        for i in 0..<300 {
            walkSamples.append(makeSample(unix: baseUnix + i, hr: 65, accel: 0.01))
        }
        var walkSteps = 1000
        for i in 300..<1200 {
            // ~115 spm
            if i % 60 < 57 { walkSteps += 2 }
            walkSamples.append(makeSample(unix: baseUnix + i, hr: 115, accel: 0.06, steps: walkSteps))
        }
        let walkDetected = ActivityDetect.detect(walkSamples, sleepPeriods: [], restingHR: 65, maxHR: 190)
        XCTAssertEqual(walkDetected.count, 1, "Brisk walking session must be auto-detected")
        if let walk = walkDetected.first {
            XCTAssertEqual(walk.kind, "walk")
            XCTAssertNotNil(walk.strain)
        }
    }
}
