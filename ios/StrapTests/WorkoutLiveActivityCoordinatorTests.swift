import XCTest
@testable import Strap

@MainActor
private final class MockWorkoutLiveActivitySink: WorkoutLiveActivitySink {
    struct UpdateCall: Equatable {
        let sessionID: UUID?
        let phase: WorkoutPhase
        let heartRate: Int?
        let zone: Int?
        let distanceMeters: Double
        let elapsedSeconds: Int
        let steps: Int?
        let isConnected: Bool
        let estimatedStrain: Double?
        let estimatedActiveCalories: Int?
    }

    var startedSessions: [(WorkoutSession, Bool)] = []
    var updates: [UpdateCall] = []
    var endCount = 0

    func start(session: WorkoutSession, isConnected: Bool) {
        startedSessions.append((session, isConnected))
    }

    func update(session: WorkoutSession?, phase: WorkoutPhase, heartRate: Int?, maxHeartRate: Double?,
                distanceMeters: Double, elapsedSeconds: Int, steps: Int?,
                stepsObservedAt: Date?, isConnected: Bool, estimatedStrain: Double?, estimatedActiveCalories: Int?) {
        let zone: Int? = {
            guard let bpm = heartRate, let maxHeartRate, maxHeartRate > 0 else { return nil }
            return min(5, max(1, Int((Double(bpm) / maxHeartRate) / 0.1) - 4))
        }()
        updates.append(UpdateCall(
            sessionID: session?.id,
            phase: phase,
            heartRate: heartRate,
            zone: zone,
            distanceMeters: distanceMeters,
            elapsedSeconds: elapsedSeconds,
            steps: steps,
            isConnected: isConnected,
            estimatedStrain: estimatedStrain,
            estimatedActiveCalories: estimatedActiveCalories
        ))
    }

    func end() {
        endCount += 1
    }
}

@MainActor
final class WorkoutLiveActivityCoordinatorTests: XCTestCase {
    func testWidgetReloadCoalescerFiresTrailingUpdateAfterCooldown() async throws {
        var now: TimeInterval = 100
        let coalescer = WidgetReloadCoalescer(minimumInterval: 0.15, now: { now })
        var fires = 0

        coalescer.requestReload { fires += 1 }
        XCTAssertEqual(fires, 1, "First request should fire immediately")

        now += 0.02
        coalescer.requestReload { fires += 2 }
        coalescer.requestReload { fires += 10 }
        XCTAssertEqual(fires, 1, "Requests inside cooldown should coalesce")

        now += 0.20
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(fires, 11, "Only the latest trailing request should fire after cooldown")
    }

    func testCoordinatorRecordsDedupedHRPauseResumeAndDisconnectWithoutView() {
        let band = BandLink(restoreIdentifier: nil)
        let recorder = WorkoutRecorder()
        let sink = MockWorkoutLiveActivitySink()
        let coordinator = WorkoutLiveActivityCoordinator(
            band: band,
            recorder: recorder,
            sink: sink,
            maxHeartRate: { 190 },
            isPreview: { true }
        )

        recorder.start(activity: .lift, trackRoute: false)
        coordinator.handlePhaseChange(.recording)
        XCTAssertEqual(sink.startedSessions.count, 1)
        XCTAssertEqual(sink.startedSessions.first?.0.hasGPS, false)

        let t1 = Date()
        coordinator.handleLiveHR(bpm: 142, observedAt: t1, connected: true, now: t1)
        // Duplicate timestamp must not record a second sample.
        coordinator.handleLiveHR(bpm: 142, observedAt: t1, connected: true, now: t1.addingTimeInterval(1))
        let t2 = t1.addingTimeInterval(2)
        coordinator.handleLiveHR(bpm: 150, observedAt: t2, connected: true, now: t2)
        coordinator.handleLiveHR(bpm: 142, observedAt: t1, connected: true, now: t2)

        recorder.pause()
        coordinator.handlePhaseChange(.paused)
        XCTAssertEqual(sink.updates.last?.phase, .paused)

        // HR arriving while paused must not be added to workout samples.
        let t3 = t2.addingTimeInterval(2)
        coordinator.handleLiveHR(bpm: 165, observedAt: t3, connected: true, now: t3)

        recorder.resume()
        coordinator.handlePhaseChange(.recording)
        let t4 = t3.addingTimeInterval(2)
        coordinator.handleLiveHR(bpm: 155, observedAt: t4, connected: true, now: t4)

        // BLE disconnect must report disconnected without forwarding stale HR.
        coordinator.handleLiveHR(bpm: 155, observedAt: t4, connected: false, now: t4.addingTimeInterval(1))
        XCTAssertEqual(sink.updates.last?.isConnected, false)
        XCTAssertNil(sink.updates.last?.heartRate)

        recorder.stop(save: true)
        coordinator.handlePhaseChange(.saved)
        XCTAssertEqual(sink.endCount, 1)
        XCTAssertEqual(recorder.savedWorkouts.first?.metrics.averageHeartRate, 149)
        XCTAssertEqual(recorder.savedWorkouts.first?.metrics.maximumHeartRate, 155)
        if let savedID = recorder.savedWorkouts.first?.id {
            recorder.deleteWorkout(id: savedID)
        }
    }

    func testWorkoutContentStateBackwardCompatibleDecoding() throws {
        let legacyJSON = """
        {
            "heartRate": 148,
            "zone": 3,
            "distanceMeters": 1250.0,
            "paceSecondsPerKilometer": 310,
            "steps": 1800,
            "paused": false,
            "lastSampleAt": 0
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkoutActivityAttributes.ContentState.self, from: legacyJSON)
        XCTAssertEqual(decoded.heartRate, 148)
        XCTAssertEqual(decoded.zone, 3)
        XCTAssertEqual(decoded.steps, 1800)
        XCTAssertNil(decoded.elapsedSeconds)
        XCTAssertNil(decoded.timerAnchor)
        XCTAssertNil(decoded.isConnected)
        XCTAssertNil(decoded.estimatedStrain)
        XCTAssertNil(decoded.estimatedActiveCalories)
        var rotating = decoded
        rotating.estimatedActiveCalories = 12
        rotating.elapsedSeconds = 0
        XCTAssertEqual(rotating.compactMetric, .steps)
        rotating.elapsedSeconds = 10
        XCTAssertEqual(rotating.compactMetric, .calories)
        rotating.elapsedSeconds = 20
        XCTAssertEqual(rotating.compactMetric, .pace)
    }
}
