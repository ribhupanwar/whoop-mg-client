import XCTest
@testable import Strap

final class WorkoutRecorderTests: XCTestCase {
    private var recorder: WorkoutRecorder!
    private var defaults: UserDefaults!
    private var testSuite: String!

    override func setUp() {
        super.setUp()
        testSuite = "workout-recorder-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: testSuite)!
        recorder = WorkoutRecorder.shared
        // Ensure clean state
        resetRecorderFully()
    }

    override func tearDown() {
        resetRecorderFully()
        defaults.removePersistentDomain(forName: testSuite)
        super.tearDown()
    }

    private func resetRecorderFully() {
        // Discard any active workout
        if recorder.phase != .idle && recorder.phase != .saved && recorder.phase != .discarded {
            recorder.discard()
        }
        // If in saved/discarded, start a new workout and discard to reset to idle
        if recorder.phase == .saved || recorder.phase == .discarded {
            recorder.start(activity: .run, trackRoute: false)
            recorder.discard()
        }
        let expectation = XCTestExpectation(description: "State reset")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Session Transitions

    func testStartFromIdleTransitionsToRecording() {
        resetRecorderFully()
        recorder.start(activity: .run, trackRoute: true)
        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertNotNil(recorder.currentSession)
        XCTAssertEqual(recorder.currentSession?.activityKind, ActivityKind.run.rawValue)
        XCTAssertTrue(recorder.currentSession?.hasGPS ?? false)
    }

    func testStartNonGPSActivityHasNoGPS() {
        resetRecorderFully()
        recorder.start(activity: .yoga, trackRoute: true)
        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertFalse(recorder.currentSession?.hasGPS ?? true)
    }

    func testPauseFromRecordingTransitionsToPaused() {
        resetRecorderFully()
        recorder.start(activity: .run, trackRoute: true)
        recorder.pause()
        XCTAssertEqual(recorder.phase, .paused)
    }

    func testPauseFromNonRecordingDoesNothing() {
        resetRecorderFully()
        // Ensure we're not in recording phase (could be idle, saved, or discarded)
        XCTAssertNotEqual(recorder.phase, .recording)
        recorder.pause()
        // Pause should not change phase when not recording
        XCTAssertNotEqual(recorder.phase, .paused)
    }

    func testResumeFromPausedTransitionsToRecording() {
        resetRecorderFully()
        recorder.start(activity: .run, trackRoute: true)
        recorder.pause()
        recorder.resume()
        XCTAssertEqual(recorder.phase, .recording)
    }

    func testResumeFromNonPausedDoesNothing() {
        resetRecorderFully()
        recorder.start(activity: .run, trackRoute: true)
        recorder.resume()
        XCTAssertEqual(recorder.phase, .recording)
    }

    func testStopSaveTransitionsToSaved() {
        resetRecorderFully()
        recorder.start(activity: .run, trackRoute: true)
        // Add some HR samples
        recorder.addHeartRateSample(140)
        recorder.addHeartRateSample(150)
        recorder.stop(save: true)
        XCTAssertEqual(recorder.phase, .saved)
        XCTAssertNotNil(recorder.currentSession)
    }

    func testStopDiscardTransitionsToDiscarded() {
        resetRecorderFully()
        recorder.start(activity: .run, trackRoute: true)
        recorder.stop(save: false)
        XCTAssertEqual(recorder.phase, .discarded)
        XCTAssertNil(recorder.currentSession)
    }

    func testDiscardCallsStopWithSaveFalse() {
        resetRecorderFully()
        recorder.start(activity: .run, trackRoute: true)
        recorder.discard()
        XCTAssertEqual(recorder.phase, .discarded)
    }

    // MARK: - Duplicate Prevention

    func testStartWhileRecordingDoesNothing() {
        resetRecorderFully()
        recorder.start(activity: .run, trackRoute: true)
        let firstSession = recorder.currentSession
        recorder.start(activity: .walk, trackRoute: true)
        XCTAssertEqual(recorder.currentSession?.id, firstSession?.id)
    }

    func testStartWhilePausedDoesNothing() {
        resetRecorderFully()
        recorder.start(activity: .run, trackRoute: true)
        recorder.pause()
        let firstSession = recorder.currentSession
        recorder.start(activity: .walk, trackRoute: true)
        XCTAssertEqual(recorder.currentSession?.id, firstSession?.id)
    }

    // MARK: - GPS-Off Workouts

    func testNonGPSActivityPersistsWithoutRoute() {
        resetRecorderFully()
        recorder.start(activity: .yoga, trackRoute: false)
        recorder.addHeartRateSample(120)
        recorder.stop(save: true)
        XCTAssertEqual(recorder.phase, .saved)
        XCTAssertEqual(recorder.currentSession?.route.count, 0)
        XCTAssertFalse(recorder.currentSession?.hasGPS ?? true)
    }

    func testGPSActivityWithTrackRouteFalseHasNoGPS() {
        resetRecorderFully()
        recorder.start(activity: .run, trackRoute: false)
        XCTAssertFalse(recorder.currentSession?.hasGPS ?? true)
    }

    // MARK: - Metric Provenance

    func testCaloriesRequiresProfileData() {
        resetRecorderFully()
        // No profile data set
        recorder.start(activity: .run, trackRoute: true)
        recorder.addHeartRateSample(140)
        recorder.stop(save: true)
        // Calories should be nil without profile
        XCTAssertNil(recorder.currentSession?.metrics.calories)
    }

    func testCaloriesWithProfileDataReturnsValue() {
        resetRecorderFully()
        recorder.updateProfile(
            weightKg: 70,
            maxHR: 190,
            restingHR: 60,
            sex: .male,
            heightCm: 180,
            age: 30
        )
        recorder.start(activity: .run, trackRoute: true)
        // Simulate > 60 seconds elapsed for calorie calculation
        recorder.setElapsedForTesting(90)
        // Add enough HR samples
        for _ in 0..<20 {
            recorder.addHeartRateSample(140)
        }
        recorder.stop(save: true)
        XCTAssertNotNil(recorder.currentSession?.metrics.calories)
        XCTAssertGreaterThan(recorder.currentSession?.metrics.calories ?? 0, 0)
    }

    func testActivityStrainRequiresProfileData() {
        resetRecorderFully()
        recorder.start(activity: .run, trackRoute: true)
        recorder.setElapsedForTesting(10)
        recorder.addHeartRateSample(140)
        recorder.stop(save: true)
        XCTAssertNil(recorder.currentSession?.metrics.activityStrain)
    }

    func testActivityStrainWithProfileDataReturnsValue() {
        resetRecorderFully()
        recorder.updateProfile(
            weightKg: 70,
            maxHR: 190,
            restingHR: 60,
            sex: .male,
            heightCm: 180,
            age: 30
        )
        recorder.start(activity: .run, trackRoute: true)
        // Need > 300 seconds for strain calculation
        recorder.setElapsedForTesting(360)
        // Add many HR samples
        for _ in 0..<20 {
            recorder.addHeartRateSample(140)
        }
        recorder.stop(save: true)
        XCTAssertNotNil(recorder.currentSession?.metrics.activityStrain)
    }

    func testHRZoneCalculation() {
        let zone = HeartRateZone.zone(for: 140, maxHR: 190, restingHR: 60)
        XCTAssertNotNil(zone)
        XCTAssertEqual(zone, .aerobic)
    }

    func testHRZoneRecovery() {
        let zone = HeartRateZone.zone(for: 100, maxHR: 190, restingHR: 60)
        XCTAssertEqual(zone, .recovery)
    }

    func testHRZoneVO2Max() {
        let zone = HeartRateZone.zone(for: 180, maxHR: 190, restingHR: 60)
        XCTAssertEqual(zone, .vo2max)
    }

    // MARK: - Historical GPS Runs (Compatibility)

    func testGPSRunHistoryStillReadable() {
        let history = GPSRunHistory(defaults: defaults)
        let run = GPSRunRecord(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1000),
            endedAt: Date(timeIntervalSince1970: 2800),
            movingSeconds: 1800,
            distanceMeters: 5000,
            splitSeconds: [360, 355, 365, 360, 360],
            route: [GPSRunPoint(latitude: 28.5, longitude: 77.2, unix: 1000, accuracyMeters: 8)]
        )
        XCTAssertTrue(history.save(run))
        let runs = history.all()
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.id, run.id)
    }

    func testWorkoutHistoryCoexistsWithGPSRunHistory() {
        let workoutHistory = WorkoutHistory(defaults: defaults)
        let gpsHistory = GPSRunHistory(defaults: defaults)

        var workout = WorkoutSession(
            id: UUID(),
            activityKind: ActivityKind.run.rawValue,
            activityLabel: "Run",
            startedAt: Date(),
            hasGPS: true
        )
        workout.endedAt = Date().addingTimeInterval(1800)
        workout.phase = .saved
        workout.metrics = WorkoutMetrics(
            elapsedSeconds: 1800,
            distanceMeters: 5000,
            averageHeartRate: 140,
            maximumHeartRate: 160,
            calories: 400,
            activityStrain: 8.5,
            splits: []
        )
        workout.route = [WorkoutRoutePoint(latitude: 28.5, longitude: 77.2, unix: Date().timeIntervalSince1970, accuracyMeters: 8, heartRate: 140)]

        XCTAssertTrue(workoutHistory.save(workout))
        XCTAssertEqual(workoutHistory.all().count, 1)

        let gpsRun = GPSRunRecord(
            id: UUID(),
            startedAt: Date().addingTimeInterval(-86400),
            endedAt: Date().addingTimeInterval(-84600),
            movingSeconds: 1800,
            distanceMeters: 5000,
            splitSeconds: [360, 360, 360, 360, 360],
            route: [GPSRunPoint(latitude: 28.5, longitude: 77.2, unix: Date().timeIntervalSince1970 - 86400, accuracyMeters: 8)]
        )
        XCTAssertTrue(gpsHistory.save(gpsRun))
        XCTAssertEqual(gpsHistory.all().count, 1)

        // Both histories work independently
        XCTAssertEqual(workoutHistory.all().count, 1)
        XCTAssertEqual(gpsHistory.all().count, 1)
    }

    // MARK: - Export Compatibility

    func testWorkoutSessionConvertsToGPSRunRecordForExport() {
        var workout = WorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            activityKind: ActivityKind.run.rawValue,
            activityLabel: "Run",
            startedAt: Date(timeIntervalSince1970: 1_762_000_000),
            hasGPS: true
        )
        workout.endedAt = Date(timeIntervalSince1970: 1_762_000_030)
        workout.metrics = WorkoutMetrics(
            elapsedSeconds: 20,
            distanceMeters: 111.2,
            averageHeartRate: 140,
            maximumHeartRate: 160,
            calories: 20,
            activityStrain: 1.0,
            splits: []
        )
        workout.route = [
            WorkoutRoutePoint(latitude: 0, longitude: 0, unix: 1_762_000_000.125, accuracyMeters: 2, heartRate: 135),
            WorkoutRoutePoint(latitude: 0, longitude: 0.001, unix: 1_762_000_010.375, accuracyMeters: 3, heartRate: 145)
        ]

        let record = GPSRunRecord(
            id: workout.id,
            startedAt: workout.startedAt,
            endedAt: workout.endedAt ?? Date(),
            movingSeconds: workout.metrics.elapsedSeconds,
            distanceMeters: workout.metrics.distanceMeters,
            splitSeconds: workout.metrics.splits.map { $0.elapsedSeconds },
            route: workout.route.map {
                GPSRunPoint(latitude: $0.latitude, longitude: $0.longitude, unix: $0.unix, accuracyMeters: $0.accuracyMeters)
            }
        )

        XCTAssertEqual(record.id, workout.id)
        XCTAssertEqual(record.distanceMeters, 111.2)
        XCTAssertEqual(record.route.count, 2)

        // Test GPX export
        let gpxData = try? GPSRunExport.render(record, format: .gpx, name: "Test")
        XCTAssertNotNil(gpxData)
        XCTAssertTrue((gpxData?.count ?? 0) > 0)

        // Test FIT export
        let fitData = try? GPSRunExport.render(record, format: .fit)
        XCTAssertNotNil(fitData)
        XCTAssertTrue((fitData?.count ?? 0) > 0)
    }
}