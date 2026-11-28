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
                stepsObservedAt: Date?, isConnected: Bool, estimatedStrain: Double?, estimatedActiveCalories: Int?,
                stepsAreEstimated: Bool) {
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
    func testBandIMUStepsAdvanceWithoutRecountingDuplicateOrGappedBlocks() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        func block(_ unix: UInt32) -> Gen5IMUBuffer {
            let axis = (0..<100).map { sample in
                1 + 0.22 * sin(2 * Double.pi * 1.8 * (Double(unix) + Double(sample) / 100))
            }
            let zero = Array(repeating: 0.0, count: 100)
            return Gen5IMUBuffer(version: 21, recordIndex: unix, unix: unix, rawSubsecond: 0,
                                 accelerationG: [axis, zero, zero], angularVelocityDPS: [zero, zero, zero])
        }
        var accumulator = LiveWorkoutStepAccumulator()
        for second in UInt32(1)..<11 {
            XCTAssertNil(accumulator.ingest(block(second), at: date))
        }
        let first = try XCTUnwrap(accumulator.ingest(block(11), at: date))
        let next = try XCTUnwrap(accumulator.ingest(block(12), at: date))
        XCTAssertGreaterThan(first.count, 0)
        XCTAssertGreaterThan(next.count, first.count)
        XCTAssertLessThanOrEqual(next.count - first.count, 4)
        XCTAssertNil(accumulator.ingest(block(12), at: date))
        XCTAssertNil(accumulator.ingest(block(14), at: date))
        accumulator.interrupt()
        XCTAssertNil(accumulator.ingest(block(15), at: date))
        for second in UInt32(16)..<25 {
            XCTAssertNil(accumulator.ingest(block(second), at: date))
        }
        let resumed = try XCTUnwrap(accumulator.ingest(block(25), at: date))
        XCTAssertGreaterThan(resumed.count - next.count, 4, "Restart should credit the qualifying warm-up run")
    }

    func testContinuousStationaryIntervalRestoresGaitWarmupCredit() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        func block(_ unix: UInt32, moving: Bool) -> Gen5IMUBuffer {
            let axis = (0..<100).map { sample in
                moving ? 1 + 0.22 * sin(2 * Double.pi * 1.8 * (Double(unix) + Double(sample) / 100)) : 1.0
            }
            let zero = Array(repeating: 0.0, count: 100)
            return Gen5IMUBuffer(version: 21, recordIndex: unix, unix: unix, rawSubsecond: 0,
                                 accelerationG: [axis, zero, zero], angularVelocityDPS: [zero, zero, zero])
        }
        var accumulator = LiveWorkoutStepAccumulator()
        for second in UInt32(1)...40 {
            _ = accumulator.ingest(block(second, moving: second <= 15),
                at: date.addingTimeInterval(Double(second)))
        }
        let stationary = try XCTUnwrap(accumulator.ingest(block(41, moving: false), at: date.addingTimeInterval(41)))
        var resumed: LiveWorkoutStepReading?
        for second in UInt32(42)...71 {
            if let reading = accumulator.ingest(block(second, moving: true), at: date.addingTimeInterval(Double(second))),
               reading.count > stationary.count {
                resumed = reading
                break
            }
        }
        let firstCredit = try XCTUnwrap(resumed)
        XCTAssertGreaterThan(firstCredit.count - stationary.count, 4)
    }

    func testOverlappingGaitWindowsAreCreditedAtMostOnceAfterClassificationDrop() {
        var ledger = LiveGaitCreditLedger()
        func windows() -> [LiveGaitPedometer.WindowCredit] {
            (3...10).map { .init(endSecond: $0, steps: 2) }
        }
        let first = ledger.accept(windows(), endingAt: 11)
        XCTAssertEqual(first.map { $0.second }, Array(UInt32(4)...11))
        XCTAssertTrue(ledger.accept([], endingAt: 12).isEmpty)
        let resumed = ledger.accept(windows(), endingAt: 13)
        XCTAssertEqual(resumed.map { $0.second }, [12, 13])
        XCTAssertTrue(ledger.accept(windows(), endingAt: 13).isEmpty)
        XCTAssertTrue(ledger.accept(windows(), endingAt: 11).isEmpty)
        XCTAssertEqual(ledger.accept(windows(), endingAt: 30).count, 8)
    }

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
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(decoded.freshIslandSteps(at: now))
        var observed = decoded
        observed.stepsObservedAt = now
        XCTAssertEqual(observed.freshIslandSteps(at: now.addingTimeInterval(120)), 1800)
        XCTAssertNil(observed.freshIslandSteps(at: now.addingTimeInterval(121)))
        XCTAssertNil(observed.freshIslandSteps(at: now.addingTimeInterval(-1)))
        observed.isConnected = false
        XCTAssertNil(observed.freshIslandSteps(at: now))
        var rotating = decoded
        rotating.estimatedActiveCalories = 12
        rotating.estimatedStrain = 2.4
        XCTAssertEqual(rotating.compactMetrics(for: .running, hasGPS: true),
                       [.pace, .distance, .calories, .strain, .elapsed])
        XCTAssertEqual(rotating.compactMetrics(for: .walking, hasGPS: true),
                       [.steps, .distance, .calories, .strain, .elapsed])
        XCTAssertEqual(rotating.compactMetrics(for: .other, hasGPS: false),
                       [.calories, .strain, .elapsed])
        XCTAssertEqual(rotating.compactMetrics(for: .running, hasGPS: false),
                       [.calories, .strain, .elapsed])
        rotating.elapsedSeconds = 0
        XCTAssertEqual(rotating.compactMetric(for: .walking, hasGPS: true), .steps)
        rotating.elapsedSeconds = 10
        XCTAssertEqual(rotating.compactMetric(for: .walking, hasGPS: true), .distance)
        rotating.elapsedSeconds = 20
        XCTAssertEqual(rotating.compactMetric(for: .walking, hasGPS: true), .calories)
        XCTAssertEqual(WorkoutActivityAttributes.displayKind("indoorWalk"), .walking)
        XCTAssertEqual(WorkoutActivityAttributes.displayKind("treadmill"), .running)
        XCTAssertEqual(WorkoutActivityAttributes.displayKind("lift"), .other)
    }
}
