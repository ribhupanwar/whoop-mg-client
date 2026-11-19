import XCTest
@testable import Strap

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
    private func sample(_ unix: Int, hr: Int, steps: Int, gait: Int? = 0) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(
                version: 18, flags: 0x80, recordIndex: UInt32(unix),
                unix: UInt32(unix), subsecQ15: 0
            ),
            heartRate: hr,
            rrIntervalsMS: [],
            dynamicAccelG: 0.05,
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

    /// A six-minute walk at 120 steps/min with resting HR and no gait readout
    /// — the walk must come from the step counter alone. The trailing-minute
    /// rate is undefined on the first tick, so the session starts one second in.
    private func walk(seconds: Int = 360) -> [V18Sample] {
        (0..<seconds).map { sample($0, hr: 75, steps: $0 * 2, gait: nil) }
    }

    func testGaitWithoutMeasuredStepsCannotCreateActivity() {
        let samples = (0..<600).map { sample($0, hr: 75, steps: 0, gait: ActivityDetect.gaitWalk) }
        XCTAssertTrue(ActivityDetect.detect(samples).isEmpty)
    }

    func testMissingHourDoesNotJoinTwoShortWalksIntoOneWorkout() {
        var samples = walk(seconds: 120)
        samples += (0..<120).map { sample(3600 + $0, hr: 75, steps: 240 + $0 * 2, gait: nil) }
        XCTAssertTrue(ActivityDetect.detect(samples).isEmpty)
    }

    func testFiveMinuteWalkIsDetectedWithoutAGaitByte() {
        let sessions = ActivityDetect.detect(walk())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.kind, "walk")
        XCTAssertEqual(sessions.first?.startUnix, 1)
        XCTAssertEqual(sessions.first?.steps, 716)
    }

    func testFastSteppingIsLabelledARun() {
        let samples = (0..<360).map { sample($0, hr: 75, steps: $0 * 3, gait: nil) }
        XCTAssertEqual(ActivityDetect.detect(samples).first?.kind, "run")
    }

    func testStaleStillGaitDoesNotHideMeasuredRunning() {
        // Some firmware reports gait=0 even while the step counter rises.
        let samples = (0..<360).map { sample($0, hr: 75, steps: $0 * 3, gait: 0) }
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

    func testTenMinuteComparisonModeRejectsSixMinuteWalkWithoutChangingDefault() {
        let samples = walk(seconds: 360)
        XCTAssertEqual(ActivityDetect.detect(samples).count, 1)
        XCTAssertTrue(ActivityDetect.detect(
            samples, minimumDurationS: ActivityDetect.comparisonMinSessionS
        ).isEmpty)
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
        let first = walk(seconds: 360)
        let pause = (360..<420).map {
            sample($0, hr: 75, steps: 718, gait: ActivityDetect.gaitStill)
        }
        let resumed = (420..<780).map {
            sample($0, hr: 75, steps: 718 + ($0 - 420) * 2, gait: ActivityDetect.gaitStill)
        }
        let cooldown = (780..<960).map {
            sample($0, hr: 75, steps: 1_436, gait: ActivityDetect.gaitStill)
        }
        let sessions = ActivityDetect.detect(first + pause + resumed + cooldown)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.endUnix, 779)
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

    func testInvalidComparisonDurationDoesNotCreateSessions() {
        XCTAssertTrue(ActivityDetect.detect(walk(), minimumDurationS: 0).isEmpty)
        XCTAssertTrue(ActivityDetect.detect(walk(), minimumDurationS: -10).isEmpty)
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
}
