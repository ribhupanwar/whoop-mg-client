import XCTest
@testable import Strap

final class GenericWorkoutConfirmationTests: XCTestCase {
    func testMorningStepsAndMildHeartRateDoNotBecomeWorkout() {
        XCTAssertFalse(ActivityDetect.confirmsGenericWorkout(
            durationS: 14 * 60, concurrentSeconds: 45, hasPreActivityBaseline: true
        ))
    }

    func testMissingBaselineDoesNotInventExertion() {
        XCTAssertFalse(ActivityDetect.confirmsGenericWorkout(
            durationS: 14 * 60, concurrentSeconds: 250, hasPreActivityBaseline: false
        ))
    }

    func testSustainedExerciseWithIndependentEvidenceRemainsEligible() {
        XCTAssertTrue(ActivityDetect.confirmsGenericWorkout(
            durationS: 14 * 60, concurrentSeconds: 250, hasPreActivityBaseline: true
        ))
    }

    func testShortIncidentalMovementIsNotExercise() {
        XCTAssertFalse(ActivityDetect.confirmsGenericWorkout(
            durationS: 8 * 60, concurrentSeconds: 150, hasPreActivityBaseline: true
        ))
    }
}

final class ActivityModelTests: XCTestCase {
    func testSetVolume() {
        let set = WorkSet(reps: 10, loadKG: 62.5)
        XCTAssertEqual(set.volumeKG, 625.0)
    }

    func testLiftSummaryCountsSetsRepsAndLoad() {
        let activity = ManualActivity(
            dateKey: "2026-11-10",
            kind: .lift,
            name: "Push",
            minutes: 55,
            sets: [
                WorkSet(reps: 8, loadKG: 60),
                WorkSet(reps: 8, loadKG: 60),
                WorkSet(reps: 6, loadKG: 70)
            ]
        )
        XCTAssertEqual(activity.totalReps, 22)
        XCTAssertEqual(activity.volumeKG, 1_380.0)
        XCTAssertEqual(activity.summary, "3 sets · 22 reps · 1380 kg")
    }

    func testNonLiftSummaryIsMinutes() {
        let activity = ManualActivity(
            dateKey: "2026-11-10", kind: .run, name: "Easy 5k", minutes: 32
        )
        XCTAssertEqual(activity.summary, "32 min")
        XCTAssertFalse(activity.kind.usesSets, "a run has no load or rep count")
    }

    func testEmptyLiftFallsBackToMinutes() {
        let activity = ManualActivity(
            dateKey: "2026-11-10", kind: .lift, name: "Lift", minutes: 40
        )
        XCTAssertEqual(activity.summary, "40 min")
    }
}

final class LiveZonesTests: XCTestCase {
    /// reserve 140: Z1 120–134, Z2 134–148, Z3 148–162, Z4 162–176, Z5 176–190.
    private var zones: [HRZone] {
        Karvonen.zones(restingHR: 50, maxHR: 190)!
    }

    private func sample(_ unix: Int, _ hr: Int) -> LiveSample {
        LiveSample(unix: unix, heartRate: hr, rrIntervalsMS: [])
    }

    func testSamplesLandInTheirZone() {
        let buckets = LiveZones.seconds(
            samples: [sample(0, 125), sample(1, 140), sample(2, 180)],
            zones: zones
        )
        XCTAssertEqual(buckets, [1, 1, 0, 0, 1])
    }

    func testEachSampleCoversUntilTheNext() {
        let buckets = LiveZones.seconds(samples: [sample(0, 125), sample(4, 140)], zones: zones)
        XCTAssertEqual(buckets, [4, 1, 0, 0, 0])
    }

    func testLongGapsDoNotInventUnobservedZoneSeconds() {
        let buckets = LiveZones.seconds(samples: [sample(0, 125), sample(60, 140)], zones: zones)
        XCTAssertEqual(buckets, [1, 1, 0, 0, 0])
    }

    func testBelowFirstZoneAndAboveMaxCountForNothing() {
        let buckets = LiveZones.seconds(
            samples: [sample(0, 100), sample(1, 195), sample(2, 130)],
            zones: zones
        )
        XCTAssertEqual(buckets, [1, 0, 0, 0, 0])
    }

    func testReplayOrderAndExactMaximum() {
        let rows = [sample(2, 190), sample(0, 125), sample(1, 140)]
        XCTAssertEqual(LiveZones.seconds(samples: rows + rows, zones: zones), [1, 1, 0, 0, 1])
    }

    func testNoZonesGivesEmpty() {
        XCTAssertEqual(LiveZones.seconds(samples: [sample(0, 120)], zones: nil), [])
    }
}

final class ActivityStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: ActivityStore!

    override func setUp() {
        super.setUp()
        suiteName = "strap.activity.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = ActivityStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveAndReadBack() {
        let activity = ManualActivity(
            dateKey: "2026-11-10", kind: .lift, name: "Push", minutes: 50,
            sets: [WorkSet(reps: 5, loadKG: 80)]
        )
        store.save(activity)
        XCTAssertEqual(store.manualActivities(), [activity])
    }

    func testSavingSameIdReplaces() {
        var activity = ManualActivity(
            dateKey: "2026-11-10", kind: .walk, name: "Walk", minutes: 20
        )
        store.save(activity)
        activity.minutes = 35
        store.save(activity)
        XCTAssertEqual(store.manualActivities().count, 1)
        XCTAssertEqual(store.manualActivities().first?.minutes, 35)
    }

    func testDelete() {
        let activity = ManualActivity(
            dateKey: "2026-11-10", kind: .walk, name: "Walk", minutes: 20
        )
        store.save(activity)
        store.deleteManual(id: activity.id)
        XCTAssertTrue(store.manualActivities().isEmpty)
    }

    func testLiveSessionsPersistSeparately() {
        let record = LiveActivityRecord(
            dateKey: "2026-11-10", startedUnix: 1_700_000_000,
            endedUnix: 1_700_001_800, meanHR: 132.0, maxHR: 168, beats: 220,
            hrv: .empty, zoneSeconds: [0, 300, 900, 300, 0]
        )
        store.saveLive(record)
        XCTAssertEqual(store.liveActivities(), [record])
        XCTAssertTrue(store.manualActivities().isEmpty, "a measured session must not look self-reported")
    }

    // MARK: Band-detected sessions

    private func session(start: Int, end: Int, steps: Int = 500) -> ActivitySession {
        ActivitySession(
            startUnix: start, endUnix: end, kind: "walk", steps: steps,
            meanHR: 110, walkTicks: 0, runTicks: 0
        )
    }

    func testDetectedSessionsSurviveARedraw() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let start = Int(now.timeIntervalSince1970) - 3_600
        store.mergeDetected([session(start: start, end: start + 600)], now: now)
        store.mergeDetected([session(start: start, end: start + 600)], now: now)
        XCTAssertEqual(store.detectedActivities().count, 1)
    }

    func testDeleteDetectedActivityPersistsAndSuppressesShiftedSyncReplay() {
        let epoch = 1_800_000_000
        let now = Date(timeIntervalSince1970: TimeInterval(epoch + 10_000))
        let original = session(start: epoch, end: epoch + 600)
        store.mergeDetected([original], now: now)
        store.deleteDetected(original, now: now)
        XCTAssertTrue(store.detectedActivities().isEmpty)

        let shiftedReplay = session(start: epoch + 10, end: epoch + 610)
        store.mergeDetected([shiftedReplay], now: now)
        XCTAssertTrue(store.detectedActivities().isEmpty)

        let relaunched = ActivityStore(defaults: defaults)
        XCTAssertTrue(relaunched.detectedActivities().isEmpty)
    }

    func testDeleteLiveActivityPersists() {
        let record = LiveActivityRecord(
            dateKey: "2026-11-10", startedUnix: 1_800_000_000,
            endedUnix: 1_800_000_600, meanHR: 120, maxHR: 150, beats: 80,
            hrv: .empty, zoneSeconds: []
        )
        store.saveLive(record)
        store.deleteLive(id: record.id)
        XCTAssertTrue(store.liveActivities().isEmpty)
        XCTAssertTrue(ActivityStore(defaults: defaults).liveActivities().isEmpty)
    }

    func testDeletedDetectionDoesNotHideAnAdjacentRealActivity() {
        let epoch = 1_800_000_000
        let now = Date(timeIntervalSince1970: TimeInterval(epoch + 10000))
        let original = session(start: epoch, end: epoch + 600)
        let adjacent = session(start: epoch + 601, end: epoch + 1201)
        store.mergeDetected([original, adjacent], now: now)
        store.deleteDetected(original, now: now)
        store.mergeDetected([original, adjacent], now: now)
        XCTAssertEqual(store.detectedActivities(), [adjacent])
    }

    func testSavingSameLiveSessionDoesNotDuplicateTheRowOrZoneTotals() {
        let record = LiveActivityRecord(
            dateKey: "2026-11-10", startedUnix: 1_800_000_000,
            endedUnix: 1_800_000_600, meanHR: 120, maxHR: 150, beats: 80,
            hrv: .empty, zoneSeconds: [600]
        )
        store.saveLive(record)
        store.saveLive(record)
        XCTAssertEqual(store.liveActivities().count, 1)
    }

    func testOverlappingDetectionKeepsTheLongerOne() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let start = Int(now.timeIntervalSince1970) - 3_600
        store.mergeDetected([session(start: start, end: start + 600)], now: now)
        store.mergeDetected([session(start: start + 10, end: start + 1_200)], now: now)
        XCTAssertEqual(store.detectedActivities().count, 1)
        XCTAssertEqual(store.detectedActivities().first?.durationS, 1_191)
    }

    func testCorruptDetectedArchiveIsNotOverwrittenByNewSync() {
        let damaged = Data("unreadable-detected-history".utf8)
        defaults.set(damaged, forKey: "strap.detected.activities.v1")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store.mergeDetected([session(start: 1_799_996_400, end: 1_799_997_000)], now: now)
        XCTAssertEqual(defaults.data(forKey: "strap.detected.activities.v1"), damaged)
    }

    func testCorruptDeletionTombstonesSurviveSyncAndDelete() {
        let damaged = Data("unreadable-deletion-history".utf8)
        defaults.set(damaged, forKey: "strap.detected.activities.deleted.v1")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let activity = session(start: 1_799_996_400, end: 1_799_997_000)
        store.mergeDetected([activity], now: now)
        store.deleteDetected(activity, now: now)
        XCTAssertEqual(defaults.data(forKey: "strap.detected.activities.deleted.v1"), damaged)
        XCTAssertTrue(store.detectedActivities().isEmpty)
    }

    func testDeleteDoesNotOverwriteCorruptDetectedHistory() {
        let damaged = Data("unreadable-detected-history".utf8)
        defaults.set(damaged, forKey: "strap.detected.activities.v1")
        let activity = session(start: 1_799_996_400, end: 1_799_997_000)
        store.deleteDetected(activity, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(defaults.data(forKey: "strap.detected.activities.v1"), damaged)
        XCTAssertNil(defaults.data(forKey: "strap.detected.activities.deleted.v1"))
    }

    func testHistoricalSessionsSurviveNewSyncAndAppRelaunch() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = session(start: 1_700_000_000, end: 1_700_000_600)
        let recent = session(start: 1_799_996_400, end: 1_799_997_000)
        store.mergeDetected([old], now: now)
        store.mergeDetected([recent], now: now)
        XCTAssertEqual(store.detectedActivities(), [old, recent])
        XCTAssertEqual(ActivityStore(defaults: defaults).detectedActivities(), [old, recent])
    }
}

final class StepDrivenDetectTests: XCTestCase {
    private func sample(_ unix: Int, hr: Int, steps: Int, gait: Int? = 0, accel: Double? = 0.05) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(
                version: 18, flags: 0x80, recordIndex: UInt32(unix),
                unix: UInt32(unix), subsecQ15: 0
            ),
            heartRate: hr,
            rrIntervalsMS: [],
            dynamicAccelG: accel,
            gravityXG: nil,
            gravityYG: nil,
            gravityZG: nil,
            stepCounter: steps,
            stepCadence: nil,
            activityClass: gait,
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
    }

    /// A sustained brisk walk at 120 steps/min with elevated HR (135 bpm)
    /// satisfying the 10-minute automatic walking safeguard (600s floor)
    /// and sustained cardiovascular exertion requirements.
    private func walk(seconds: Int = 660, hr: Int = 135) -> [V18Sample] {
        (0..<seconds).map { sample($0, hr: hr, steps: $0 * 2, gait: nil) }
    }

    func testGaitWithoutMeasuredStepsCannotCreateActivity() {
        let samples = (0..<600).map { sample($0, hr: 75, steps: 0, gait: ActivityDetect.gaitWalk) }
        XCTAssertTrue(ActivityDetect.detect(samples).isEmpty)
    }

    func testLongArchiveGapSeparatesTwoMeasuredRuns() {
        // Reconnect/offload gaps must not extend one activity across an hour.
        // Each side has enough independently measured motion to qualify.
        let first = (0..<660).map { sample($0, hr: 145, steps: $0 * 3, gait: nil) }
        let second = (0..<660).map {
            sample(4_260 + $0, hr: 145, steps: 1_980 + $0 * 3, gait: nil)
        }
        let sessions = ActivityDetect.detect(first + second)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.map(\.kind), ["run", "run"])
        XCTAssertEqual(sessions[0].endUnix, 659)
        XCTAssertEqual(sessions[1].startUnix, 4_260)
    }

    func testMissingHourDoesNotJoinTwoShortWalksIntoOneWorkout() {
        var samples = walk(seconds: 120)
        samples += (0..<120).map { sample(3600 + $0, hr: 135, steps: 240 + $0 * 2, gait: nil) }
        XCTAssertTrue(ActivityDetect.detect(samples).isEmpty)
    }

    func testSustainedWalkIsDetectedWithoutAGaitByte() {
        let sessions = ActivityDetect.detect(walk())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.kind, "walk")
        XCTAssertEqual(sessions.first?.startUnix, 1)
        XCTAssertEqual(sessions.first?.steps, 1316)
    }

    func testFastSteppingIsLabelledARun() {
        let samples = (0..<360).map { sample($0, hr: 145, steps: $0 * 3, gait: nil) }
        XCTAssertEqual(ActivityDetect.detect(samples).first?.kind, "run")
    }

    func testTenMinuteComparatorDoesNotSilentlyChangeFiveMinuteRunningDefault() {
        // Public WHOOP duration guidance is a comparison target, not a
        // reason to silently discard STRAP's existing short measured runs.
        let sixMinuteRun = (0..<360).map {
            sample($0, hr: 145, steps: $0 * 3, gait: nil)
        }
        XCTAssertEqual(ActivityDetect.detect(sixMinuteRun).first?.kind, "run")
        XCTAssertTrue(ActivityDetect.detect(
            sixMinuteRun, minimumDurationS: ActivityDetect.comparisonMinSessionS
        ).isEmpty)

        let elevenMinuteRun = (0..<660).map {
            sample($0, hr: 145, steps: $0 * 3, gait: nil)
        }
        let compared = ActivityDetect.detect(
            elevenMinuteRun, minimumDurationS: ActivityDetect.comparisonMinSessionS
        )
        XCTAssertEqual(compared.count, 1)
        XCTAssertEqual(compared.first?.kind, "run")
    }

    func testStaleStillGaitDoesNotHideMeasuredRunning() {
        // Some firmware reports gait=0 even while the step counter rises.
        let samples = (0..<360).map { sample($0, hr: 145, steps: $0 * 3, gait: 0) }
        let sessions = ActivityDetect.detect(samples)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.kind, "run")
    }

    func testStillGaitWithoutStepsDoesNotCreateActivity() {
        let samples = (0..<360).map { sample($0, hr: 75, steps: 0, gait: 0) }
        XCTAssertTrue(ActivityDetect.detect(samples).isEmpty)
    }

    func testSleepWindowsAreNotWorkouts() {
        let periods = [
            SleepPeriod(
                startUnix: -60, endUnix: 400, quietFraction: 0.9,
                meanHR: 55, wakeEvents: 0
            )
        ]
        XCTAssertTrue(ActivityDetect.detect(walk(), sleepPeriods: periods).isEmpty)
    }

    func testFourMinuteWalkIsBelowTheFloor() {
        XCTAssertTrue(ActivityDetect.detect(walk(seconds: 240)).isEmpty)
    }

    func testShortBriskWalkBelowTenMinutesDoesNotAutoSave() {
        // Walks under 10 minutes (600s) are not auto-saved as official workouts.
        let samples = walk(seconds: 360)
        XCTAssertTrue(ActivityDetect.detect(samples).isEmpty)
        XCTAssertTrue(ActivityDetect.detect(
            samples, minimumDurationS: ActivityDetect.comparisonMinSessionS
        ).isEmpty)
    }

    func testCasualWalkWithRestingHRDoesNotBecomeWorkout() {
        // 11 minutes of walking with resting HR (75 bpm) must remain daily movement, not a workout.
        let samples = walk(seconds: 660, hr: 75)
        XCTAssertTrue(ActivityDetect.detect(samples).isEmpty)
        // Daily steps must still count completely
        XCTAssertGreaterThanOrEqual(StepCounter.total(samples) ?? 0, 1300)
    }

    func testTenMinuteComparisonModeAcceptsSustainedWalk() {
        let samples = walk(seconds: 660)
        let sessions = ActivityDetect.detect(
            samples, minimumDurationS: ActivityDetect.comparisonMinSessionS
        )
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.kind, "walk")
    }

    func testCooldownDoesNotExtendDetectedWalkEnd() {
        // The report's alleged session.end mutation does not exist in STRAP.
        // Trailing inactive records must not become part of a workout.
        let active = walk(seconds: 660)
        let cooldown = (660..<900).map {
            sample($0, hr: 75, steps: 1_318, gait: ActivityDetect.gaitStill)
        }
        let sessions = ActivityDetect.detect(active + cooldown)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.endUnix, 659)
    }

    func testShortPauseIsBridgedButTrailingCooldownIsNot() {
        let first = walk(seconds: 600)
        let pause = (600..<660).map {
            sample($0, hr: 110, steps: 1_198, gait: ActivityDetect.gaitStill)
        }
        let resumed = (660..<1020).map {
            sample($0, hr: 135, steps: 1_198 + ($0 - 660) * 2, gait: ActivityDetect.gaitStill)
        }
        let cooldown = (1020..<1200).map {
            sample($0, hr: 75, steps: 1_918, gait: ActivityDetect.gaitStill)
        }
        let sessions = ActivityDetect.detect(first + pause + resumed + cooldown)
        XCTAssertEqual(sessions.count, 1)
        // At second 1020 the step counter reaches 1,918 (+2 delta); trailing
        // stationary cooldown (1021..<1200) at 75 bpm must not extend the session.
        XCTAssertEqual(sessions.first?.endUnix, 1020)
    }

    func testElevatedHeartRateCooldownDoesNotExtendMeasuredWalk() {
        // Resting baseline, sustained walk, then 3 minutes of high HR at rest.
        let baseline = (0..<360).map { sample($0, hr: 75, steps: 0, gait: nil) }
        let walking = (360..<1020).map {
            sample($0, hr: 145, steps: ($0 - 359) * 2, gait: nil)
        }
        let stoppedSteps = 660 * 2
        let cooldown = (1020..<1200).map {
            sample($0, hr: 130, steps: stoppedSteps, gait: nil)
        }
        let sessions = ActivityDetect.detect(baseline + walking + cooldown)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.endUnix, 1019)
    }

    func testStepCounterWrapDoesNotSplitMeasuredWalk() {
        // A valid 16-bit wrap must not look like stopped movement.
        let samples = (0..<660).map { second in
            sample(second, hr: 135, steps: (65_000 + second * 2) % 65_536, gait: nil)
        }
        let sessions = ActivityDetect.detect(samples)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.startUnix, 1)
        XCTAssertEqual(sessions.first?.endUnix, 659)
        XCTAssertEqual(sessions.first?.kind, "walk")
    }

    func testInvalidComparisonDurationDoesNotCreateSessions() {
        XCTAssertTrue(ActivityDetect.detect(walk(), minimumDurationS: 0).isEmpty)
        XCTAssertTrue(ActivityDetect.detect(walk(), minimumDurationS: -10).isEmpty)
    }

    func testCasualWalkingAroundHouseDoesNotCreateWorkout() {
        // 15 minutes of casual strolling around house at 65 SPM, resting HR 72
        let samples = (0..<900).map { sample($0, hr: 72, steps: Int(Double($0) * 65.0 / 60.0), gait: 1) }
        let sessions = ActivityDetect.detect(samples)
        XCTAssertTrue(sessions.isEmpty, "Casual walking at 65 SPM must not create a workout")
        XCTAssertGreaterThan(StepCounter.total(samples) ?? 0, 900)
    }

    func testShoppingAndErrandsWithPausesDoesNotCreateWorkout() {
        // 30 minutes of stop-and-start shopping: 1 min walk at 70 SPM, 2 min pause, repeated 10 times
        var samples: [V18Sample] = []
        var t = 0
        var currentSteps = 100
        for _ in 0..<10 {
            for s in 0..<60 {
                samples.append(sample(t + s, hr: 76, steps: currentSteps + Int(Double(s) * 70.0 / 60.0), gait: 1))
            }
            t += 60
            currentSteps += 70
            for s in 0..<120 {
                samples.append(sample(t + s, hr: 74, steps: currentSteps, gait: 0))
            }
            t += 120
        }
        let sessions = ActivityDetect.detect(samples)
        XCTAssertTrue(sessions.isEmpty, "Shopping with pauses must not create a workout")
        XCTAssertGreaterThanOrEqual(StepCounter.total(samples) ?? 0, 700)
    }

    func testOfficeWalkingThroughoutDayDoesNotCreateWorkout() {
        // Intermittent 2-minute walks between desks at 75 SPM
        var samples: [V18Sample] = []
        var t = 0
        var currentSteps = 100
        for _ in 0..<6 {
            for s in 0..<1680 {
                samples.append(sample(t + s, hr: 70, steps: currentSteps, gait: 0))
            }
            t += 1680
            for s in 0..<120 {
                samples.append(sample(t + s, hr: 75, steps: currentSteps + Int(Double(s) * 75.0 / 60.0), gait: 1))
            }
            t += 120
            currentSteps += 150
        }
        let sessions = ActivityDetect.detect(samples)
        XCTAssertTrue(sessions.isEmpty, "Intermittent office walking must not become workouts")
        // Endpoint sampling omits a couple of boundary steps from this synthetic
        // fixture; 898 is the validated observable counter delta, not 900.
        XCTAssertGreaterThanOrEqual(StepCounter.total(samples) ?? 0, 898)
    }

    func testSyntheticHouseholdMovementAndElevatedHRMustCoincide() {
        let baseline = (0..<900).map { sample($0, hr: 74, steps: 0, accel: 0.01) }
        let chores = (900..<2700).map { second in
            let moving = second % 60 < 15
            return sample(second, hr: moving ? 82 : 115, steps: (second - 900) / 7,
                          gait: moving ? 1 : 2, accel: moving ? 0.24 : 0.01)
        }
        XCTAssertTrue(ActivityDetect.detect(baseline + chores).isEmpty)
        XCTAssertGreaterThan(StepCounter.total(chores) ?? 0, 0)
    }

    func testSyntheticDrivingVibrationWithoutHRRiseDoesNotCreateWorkout() {
        let baseline = (0..<900).map { sample($0, hr: 74, steps: 0, accel: 0.01) }
        let driving = (900..<4500).map { second in
            sample(second, hr: 82, steps: (second - 900) / 15, gait: 2,
                   accel: second.isMultiple(of: 2) ? 0.35 : 0.08)
        }
        XCTAssertTrue(ActivityDetect.detect(baseline + driving).isEmpty)
    }

    func testSyntheticTwoHourSedentaryHRRiseDoesNotCreateWorkout() {
        let baseline = (0..<900).map { sample($0, hr: 74, steps: 0, accel: 0.01) }
        let seated = (900..<8100).map { sample($0, hr: 118, steps: 0, gait: 2, accel: nil) }
        XCTAssertTrue(ActivityDetect.detect(baseline + seated).isEmpty)
    }

    func testSyntheticWalkEndsAtDrivingTransition() throws {
        let walking = walk()
        let driving = (660..<4260).map { second in
            sample(second, hr: 82, steps: 1318 + (second - 660) / 15, gait: 2, accel: 0.22)
        }
        let sessions = ActivityDetect.detect(walking + driving)
        XCTAssertEqual(sessions.count, 1)
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.kind, "walk")
        XCTAssertEqual(session.endUnix, 659)
    }

    func testSyntheticSustainedRunsWithOutdoorOrTreadmillMotion() throws {
        for motion in [0.05, 0.25] {
            let running = (0..<720).map { sample($0, hr: 155, steps: $0 * 3, gait: nil, accel: motion) }
            let sessions = ActivityDetect.detect(running)
            XCTAssertEqual(sessions.count, 1)
            let session = try XCTUnwrap(sessions.first)
            XCTAssertEqual(session.kind, "run")
            XCTAssertEqual(session.endUnix, 719)
        }
    }

    func testDailyStrainSurvivesActivityDeletionAndReplay() throws {
        let suite = "ActivityStrainDeletionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ActivityStore(defaults: defaults)
        let epoch = 1_800_000_000
        let baseline = (0..<900).map { sample(epoch + $0, hr: 72, steps: 0, accel: 0.01) }
        let exercise = (900..<1620).map {
            sample(epoch + $0, hr: 145, steps: ($0 - 899) * 3, gait: nil, accel: 0.22)
        }
        let samples = baseline + exercise
        let candidates = ActivityDetect.detect(samples)
        let workout = try XCTUnwrap(candidates.first)
        let now = Date(timeIntervalSince1970: Double(epoch + 1621))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        func dayStrain() -> Double? {
            DailyAnalysis.metrics(from: samples, sex: .male, maxHR: 190, calendar: calendar,
                                  analyzedSleepSessions: []).first?.strain
        }

        store.mergeDetected(candidates, now: now)
        XCTAssertEqual(store.detectedActivities(), [workout])
        let before = try XCTUnwrap(dayStrain())
        XCTAssertGreaterThan(before, 0)
        store.deleteDetected(workout, now: now)
        store.mergeDetected(candidates, now: now)
        let relaunched = ActivityStore(defaults: defaults)
        XCTAssertTrue(relaunched.detectedActivities().isEmpty)
        XCTAssertEqual(relaunched.deletedDetectedStartTimes(), [workout.startUnix])
        XCTAssertEqual(dayStrain(), before)
    }

    func testSynthetic189MinuteSparseEvidenceDoesNotChainIntoWorkout() throws {
        let baseline = (0..<900).map { sample($0, hr: 75, steps: 0, accel: 0.01) }
        let sparse = (900..<(900 + 189 * 60)).map { second in
            sample(second, hr: 110, steps: (second - 900) / 10, gait: 2,
                   accel: second % 60 < 12 ? 0.30 : 0.01)
        }
        var decisions: [ActivityDecision] = []
        XCTAssertTrue(ActivityDetect.detect(baseline + sparse, onDecision: { decisions.append($0) }).isEmpty)
        let rejection = try XCTUnwrap(decisions.first { $0.reason.contains("Sparse evidence") })
        XCTAssertEqual(rejection.supportedSeconds, 0)
        XCTAssertGreaterThan(rejection.movementSeconds, 0)
    }

    func testWorkoutStopsBeforeStationaryElevatedHRAndIntermittentMotion() throws {
        let baseline = (0..<900).map { sample($0, hr: 72, steps: 50, accel: 0.01) }
        let workout = (900..<1800).map { sample($0, hr: 135, steps: 50, accel: 0.23) }
        let sitting = (1800..<9000).map { second in
            sample(second, hr: 117, steps: 50,
                   accel: second % 60 < 6 ? 0.15 : nil)
        }
        let result = ActivityDetect.detect(baseline + workout + sitting)
        XCTAssertEqual(result.count, 1)
        let session = try XCTUnwrap(result.first)
        XCTAssertEqual(session.kind, "workout")
        // The 80%-dense confirmation window can absorb a short initial
        // transition but cannot keep an office-length tail open.
        XCTAssertLessThan(session.endUnix, 1800 + ActivityDetect.minSessionS)
    }

    func testCandidateClassificationDiagnosesDailyMovement() {
        let casualSamples = (0..<900).map { sample($0, hr: 72, steps: Int(Double($0) * 65.0 / 60.0), gait: 1) }
        let candidates = ActivityDetect.evaluateCandidates(casualSamples)
        for candidate in candidates {
            XCTAssertNotEqual(candidate.confidence, .confirmed)
        }
    }
}

extension ActivityStoreTests {
    func testBulkReplayDeduplicatesThousandsOfExactCopiesBeforeOverlapMerging() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let start = Int(now.timeIntervalSince1970) - 3600
        let original = session(start: start, end: start + 600)
        let longer = session(start: start + 30, end: start + 660)
        store.mergeDetected(Array(repeating: original, count: 2000) + Array(repeating: longer, count: 2000), now: now)
        XCTAssertEqual(store.detectedActivities().count, 1)
        XCTAssertEqual(store.detectedActivities().first?.startUnix, longer.startUnix)
        store.deleteDetected(longer, now: now)
        store.mergeDetected(Array(repeating: original, count: 2000), now: now)
        XCTAssertTrue(store.detectedActivities().isEmpty)
    }
}

extension ActivityStoreTests {
    func testCorruptLiveArchiveSurvivesSaveAndDelete() {
        let key = "strap.live.sessions.v1"
        let damaged = Data("{not valid JSON".utf8)
        defaults.set(damaged, forKey: key)
        let record = LiveActivityRecord(
            dateKey: "2026-11-10", startedUnix: 1_700_000_000,
            endedUnix: 1_700_001_800, meanHR: 132.0, maxHR: 168, beats: 220,
            hrv: .empty, zoneSeconds: [0, 300, 900, 300, 0]
        )
        store.saveLive(record)
        XCTAssertEqual(defaults.data(forKey: key), damaged)
        store.deleteLive(id: record.id)
        XCTAssertEqual(defaults.data(forKey: key), damaged)
    }

    func testWrongTypeLiveArchiveSurvivesSaveAndDelete() {
        let key = "strap.live.sessions.v1"
        defaults.set("legacy unreadable data", forKey: key)
        let record = LiveActivityRecord(
            dateKey: "2026-11-10", startedUnix: 1_700_000_000,
            endedUnix: 1_700_001_800, meanHR: nil, maxHR: nil, beats: 0,
            hrv: .empty, zoneSeconds: []
        )
        store.saveLive(record)
        store.deleteLive(id: record.id)
        XCTAssertEqual(defaults.string(forKey: key), "legacy unreadable data")
    }

    func testConcurrentActivityMergeAndPreferencesSnapshotsDoNotDeadlock() {
        let epoch = 1_800_000_000
        let now = Date(timeIntervalSince1970: TimeInterval(epoch))
        let writer = BackgroundPreferencesWriter(defaults: defaults)
        let group = DispatchGroup()

        // 1. Concurrent activity merges on background queue
        for i in 0..<50 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let s = self.session(start: epoch + i * 100, end: epoch + i * 100 + 50)
                self.store.mergeDetected([s], now: now)
                group.leave()
            }
        }

        // 2. Concurrent preferences snapshot writes on background queue
        for i in 0..<50 {
            group.enter()
            let dummy = ["key": "val_\(i)"]
            writer.write(dummy, forKey: "strap.test.pref.\(i)") { _ in
                group.leave()
            }
        }

        // 3. UI thread repeatedly queries isDetectedDeleted and detectedActivities
        let deadline = Date().addingTimeInterval(5.0)
        var uiQueries = 0
        let probe = session(start: epoch, end: epoch + 60)
        while Date() < deadline && uiQueries < 200 {
            _ = store.isDetectedDeleted(probe)
            _ = store.detectedActivities()
            uiQueries += 1
            Thread.sleep(forTimeInterval: 0.001)
        }

        let result = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success, "Concurrent merge and preferences writes must complete without deadlock")
        XCTAssertGreaterThan(uiQueries, 50, "UI thread queries must not be starved")
    }

    func testNotificationCenterReentrancyDoesNotDeadlock() {
        let epoch = 1_800_000_000
        let now = Date(timeIntervalSince1970: TimeInterval(epoch))
        let probe = session(start: epoch, end: epoch + 600)

        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: nil
        ) { _ in
            notificationCount += 1
            // Reentrant query from inside NotificationCenter observer callback:
            // Must not deadlock against detectedLock or persistLock.
            _ = self.store.isDetectedDeleted(probe)
            _ = self.store.detectedActivities()
        }

        defer { NotificationCenter.default.removeObserver(observer) }

        // Perform merge and delete; both trigger UserDefaults.didChangeNotification
        store.mergeDetected([probe], now: now)
        XCTAssertFalse(store.detectedActivities().isEmpty)
        XCTAssertFalse(store.isDetectedDeleted(probe))

        store.deleteDetected(probe, now: now)
        XCTAssertTrue(store.detectedActivities().isEmpty)
        XCTAssertTrue(store.isDetectedDeleted(probe))
        XCTAssertGreaterThan(notificationCount, 0)
    }

    func testSimultaneousDetectedActivitiesQueriesDuringActiveBackgroundMerge() {
        let epoch = 1_800_000_000
        let now = Date(timeIntervalSince1970: TimeInterval(epoch))
        let candidate = session(start: epoch, end: epoch + 900)
        store.mergeDetected([candidate], now: now)

        let exp = expectation(description: "Background merge loop")
        exp.expectedFulfillmentCount = 20

        let queryGroup = DispatchGroup()

        // Active background merge queue simulating BandLink history drain
        for i in 0..<20 {
            DispatchQueue.global(qos: .utility).async {
                let s = self.session(start: epoch + (i + 1) * 1000, end: epoch + (i + 1) * 1000 + 600)
                self.store.mergeDetected([s], now: now)
                exp.fulfill()
            }
        }

        // Multiple concurrent readers simulating SwiftUI scene update and AttributeGraph evaluations
        for _ in 0..<5 {
            queryGroup.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                for _ in 0..<100 {
                    _ = self.store.detectedActivities()
                    _ = self.store.isDetectedDeleted(candidate)
                    _ = self.store.deletedDetectedStartTimes()
                }
                queryGroup.leave()
            }
        }

        wait(for: [exp], timeout: 5.0)
        let queryResult = queryGroup.wait(timeout: .now() + 5.0)
        XCTAssertEqual(queryResult, .success, "Simultaneous UI queries must complete without timeout or contention")
    }
}
