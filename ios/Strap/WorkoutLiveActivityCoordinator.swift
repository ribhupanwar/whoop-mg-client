import Combine
import Foundation

@MainActor
protocol WorkoutLiveActivitySink: AnyObject {
    func start(session: WorkoutSession, isConnected: Bool)
    func update(session: WorkoutSession?, phase: WorkoutPhase, heartRate: Int?, maxHeartRate: Double?,
                distanceMeters: Double, elapsedSeconds: Int, steps: Int?,
                stepsObservedAt: Date?, isConnected: Bool, estimatedStrain: Double?,
                estimatedActiveCalories: Int?, stepsAreEstimated: Bool)
    func end()
}

@MainActor
final class DefaultWorkoutLiveActivitySink: WorkoutLiveActivitySink {
    func start(session: WorkoutSession, isConnected: Bool) {
        WorkoutLiveActivityController.shared.start(session: session, isConnected: isConnected)
    }

    func update(session: WorkoutSession?, phase: WorkoutPhase, heartRate: Int?, maxHeartRate: Double?,
                distanceMeters: Double, elapsedSeconds: Int, steps: Int?,
                stepsObservedAt: Date?, isConnected: Bool, estimatedStrain: Double?,
                estimatedActiveCalories: Int?, stepsAreEstimated: Bool) {
        WorkoutLiveActivityController.shared.update(
            session: session, phase: phase, heartRate: heartRate, maxHeartRate: maxHeartRate,
            distanceMeters: distanceMeters, elapsedSeconds: elapsedSeconds, steps: steps,
            stepsObservedAt: stepsObservedAt, isConnected: isConnected, estimatedStrain: estimatedStrain,
            estimatedActiveCalories: estimatedActiveCalories, stepsAreEstimated: stepsAreEstimated
        )
    }

    func end() {
        WorkoutLiveActivityController.shared.end()
    }
}

/// Application-level, event-driven coordinator for workout HR sampling,
/// ActivityKit Live Activity lifecycle, and midnight/disconnect refreshes.
/// Operates independently of SwiftUI view visibility (`GPSRunView`).
@MainActor
final class WorkoutLiveActivityCoordinator {
    private let band: BandLink
    private let recorder: WorkoutRecorder
    private let sink: WorkoutLiveActivitySink
    private let maxHeartRateProvider: () -> Double?
    private let isPreviewProvider: () -> Bool
    private let onDayChange: () -> Void

    private var cancellables: Set<AnyCancellable> = []
    private var lastRecordedHRAt: Date?
    private var startedSessionID: UUID?

    init(
        band: BandLink,
        recorder: WorkoutRecorder = .shared,
        sink: WorkoutLiveActivitySink? = nil,
        maxHeartRate: @escaping () -> Double? = { nil },
        isPreview: @escaping () -> Bool = { false },
        onDayChange: @escaping () -> Void = {}
    ) {
        self.band = band
        self.recorder = recorder
        self.sink = sink ?? DefaultWorkoutLiveActivitySink()
        self.maxHeartRateProvider = maxHeartRate
        self.isPreviewProvider = isPreview
        self.onDayChange = onDayChange
        bind()
    }

    private func bind() {
        recorder.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.handlePhaseChange(phase)
            }
            .store(in: &cancellables)

        recorder.$distanceMeters
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.recorder.phase == .recording else { return }
                self.recorder.tick()
                self.pushUpdate()
            }
            .store(in: &cancellables)

        band.$lastLiveHRAt
            .dropFirst()
            // Pair the BPM with the timestamp before asynchronous delivery.
            .map { [weak band] observed in
                (band?.liveHeartRate, observed, band?.isConnected ?? false)
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] observation in
                guard let self else { return }
                self.handleLiveHR(
                    bpm: observation.0,
                    observedAt: observation.1,
                    connected: observation.2 && self.band.isConnected,
                    now: Date()
                )
            }
            .store(in: &cancellables)

        band.$status
            .dropFirst()
            .map { [weak band] _ in band?.isConnected ?? false }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] connected in
                guard let self else { return }
                if self.recorder.phase == .recording || self.recorder.phase == .paused {
                    self.recorder.tick()
                    self.pushUpdate(now: Date(), connectedOverride: connected)
                }
                if !connected {
                    self.recorder.breakEnergyInterval()
                    self.band.refreshRecordedTodaySteps()
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(band.$capturedTodayFromLedger, band.$capturedTodayStepAt)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self, self.recorder.phase == .recording || self.recorder.phase == .paused else { return }
                self.recorder.tick()
                self.pushUpdate()
            }
            .store(in: &cancellables)

        band.$liveWorkoutSteps
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.recorder.phase == .recording else { return }
                self.recorder.tick()
                self.pushUpdate()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .merge(with: NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.band.refreshRecordedTodaySteps()
                self.onDayChange()
            }
            .store(in: &cancellables)
    }

    func handlePhaseChange(_ phase: WorkoutPhase) {
        reconcileBandSteps()
        switch phase {
        case .recording:
            if let session = recorder.currentSession {
                if startedSessionID != session.id {
                    startedSessionID = session.id
                    lastRecordedHRAt = nil
                    sink.start(session: session, isConnected: band.isConnected)
                }
                recorder.tick()
                requestWorkoutStepsIfNeeded(now: Date())
                pushUpdate()
            }
        case .paused:
            recorder.tick()
            pushUpdate()
        case .saved:
            let completed = recorder.currentSession
            startedSessionID = nil
            lastRecordedHRAt = nil
            sink.end()
            if let completed, !isPreviewProvider() {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await LocalWellnessNotice.post(.workout, id: completed.id.uuidString) {
                        !self.isPreviewProvider()
                    }
                }
            }
        case .discarded, .idle:
            startedSessionID = nil
            lastRecordedHRAt = nil
            sink.end()
        case .preparing, .saving:
            break
        }
    }

    func handleLiveHR(bpm: Int?, observedAt: Date?, connected: Bool, now: Date = Date()) {
        if !connected || bpm.map({ !(35...220).contains($0) }) != false { recorder.breakEnergyInterval() }
        guard let observedAt else { return }
        if recorder.phase == .recording,
           (lastRecordedHRAt.map { observedAt > $0 } ?? true),
           let freshBPM = LiveHeartRateState.fresh(bpm, receivedAt: observedAt, connected: connected, now: now) {
            recorder.addHeartRateSample(freshBPM, observedAt: observedAt)
            lastRecordedHRAt = observedAt
            requestWorkoutStepsIfNeeded(now: now)
        }
        if recorder.phase == .recording || recorder.phase == .paused {
            recorder.tick()
            pushUpdate(now: now, connectedOverride: connected)
        }
    }

    private func requestWorkoutStepsIfNeeded(now: Date) {
        guard !isPreviewProvider(), recorder.phase == .recording,
              let session = recorder.currentSession else { return }
        let kind = WorkoutActivityAttributes.displayKind(session.activityKind)
        guard kind == .walking || kind == .running else { return }
        band.refreshWorkoutStepHistoryIfNeeded(now: now)
    }

    private func reconcileBandSteps() {
        let session = recorder.currentSession
        let kind = session.map { WorkoutActivityAttributes.displayKind($0.activityKind) }
        let eligible = !isPreviewProvider() && (kind == .walking || kind == .running)
        let active = recorder.phase == .recording || recorder.phase == .paused
        band.reconcileWorkoutStepStream(sessionID: eligible && active ? session?.id : nil,
                                        recording: recorder.phase == .recording)
    }

    private func pushUpdate(now: Date = Date(), connectedOverride: Bool? = nil) {
        reconcileBandSteps()
        let connected = connectedOverride ?? band.isConnected
        let liveSteps = band.liveWorkoutSteps
        let freshBPM = LiveHeartRateState.fresh(
            band.liveHeartRate, receivedAt: band.lastLiveHRAt, connected: connected, now: now
        )
        let estimatedStrain = recorder.liveActivityStrain
        sink.update(
            session: recorder.currentSession,
            phase: recorder.phase,
            heartRate: freshBPM,
            maxHeartRate: maxHeartRateProvider(),
            distanceMeters: recorder.distanceMeters,
            elapsedSeconds: recorder.elapsedSeconds,
            steps: liveSteps?.count ?? band.recordedTodayFromLedger,
            stepsObservedAt: liveSteps?.observedAt ?? band.capturedTodayStepAt,
            isConnected: connected,
            estimatedStrain: estimatedStrain,
            estimatedActiveCalories: recorder.liveCalories,
            stepsAreEstimated: liveSteps != nil
        )
    }
}
