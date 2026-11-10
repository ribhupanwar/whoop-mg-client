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

    func testLongGapsAreClamped() {
        let buckets = LiveZones.seconds(samples: [sample(0, 125), sample(60, 140)], zones: zones)
        XCTAssertEqual(buckets, [5, 1, 0, 0, 0])
    }

    func testBelowFirstZoneAndAboveMaxCountForNothing() {
        let buckets = LiveZones.seconds(
            samples: [sample(0, 100), sample(1, 195), sample(2, 130)],
            zones: zones
        )
        XCTAssertEqual(buckets, [1, 0, 0, 0, 0])
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
        store.mergeDetected([session(start: 1_700_000_000, end: 1_700_000_600)])
        store.mergeDetected([session(start: 1_700_000_000, end: 1_700_000_600)])
        XCTAssertEqual(store.detectedActivities().count, 1)
    }

    func testOverlappingDetectionKeepsTheLongerOne() {
        store.mergeDetected([session(start: 1_700_000_000, end: 1_700_000_600)])
        store.mergeDetected([session(start: 1_700_000_010, end: 1_700_001_200)])
        XCTAssertEqual(store.detectedActivities().count, 1)
        XCTAssertEqual(store.detectedActivities().first?.durationS, 1_191)
    }

    func testSessionsOlderThanSixtyDaysArePruned() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store.mergeDetected([session(start: 1_700_000_000, end: 1_700_000_600)], now: now)
        XCTAssertTrue(store.detectedActivities().isEmpty)
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
            signalQualityLogVariance: nil
        )
    }

    /// A six-minute walk at 120 steps/min with resting HR and no gait readout
    /// — the walk must come from the step counter alone. The trailing-minute
    /// rate is undefined on the first tick, so the session starts one second in.
    private func walk(seconds: Int = 360) -> [V18Sample] {
        (0..<seconds).map { sample($0, hr: 75, steps: $0 * 2, gait: nil) }
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
}
