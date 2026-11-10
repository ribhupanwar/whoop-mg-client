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
}
