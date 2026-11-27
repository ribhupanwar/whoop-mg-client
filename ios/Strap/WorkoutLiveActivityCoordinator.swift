import Combine
import Foundation

@MainActor
protocol WorkoutLiveActivitySink: AnyObject {
    func start(session: WorkoutSession, isConnected: Bool)
    func update(session: WorkoutSession?, phase: WorkoutPhase, heartRate: Int?, maxHeartRate: Double?,
                distanceMeters: Double, elapsedSeconds: Int, steps: Int?,
                stepsObservedAt: Date?, isConnected: Bool, estimatedStrain: Double?)
    func end()
}

@MainActor
final class DefaultWorkoutLiveActivitySink: WorkoutLiveActivitySink {
    func start(session: WorkoutSession, isConnected: Bool) {
        WorkoutLiveActivityController.shared.start(session: session, isConnected: isConnected)
    }

    func update(session: WorkoutSession?, phase: WorkoutPhase, heartRate: Int?, maxHeartRate: Double?,
                distanceMeters: Double, elapsedSeconds: Int, steps: Int?,
                stepsObservedAt: Date?, isConnected: Bool, estimatedStrain: Double?) {
        WorkoutLiveActivityController.shared.update(
            session: session, phase: phase, heartRate: heartRate, maxHeartRate: maxHeartRate,
            distanceMeters: distanceMeters, elapsedSeconds: elapsedSeconds, steps: steps,
            stepsObservedAt: stepsObservedAt, isConnected: isConnected, estimatedStrain: estimatedStrain
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
        sink: WorkoutLiveActivitySink = DefaultWorkoutLiveActivitySink(),
        maxHeartRate: @escaping () -> Double? = { nil },
        isPreview: @escaping () -> Bool = { false },
        onDayChange: @escaping () -> Void = {}
    ) {
        self.band = band
        self.recorder = recorder
        self.sink = sink
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
            .receive(on: RunLoop.main)
            .sink { [weak self] observed in
                self?.handleLiveHR(
                    bpm: self?.band.liveHeartRate,
                    observedAt: observed,
                    connected: self?.band.isConnected ?? false,
                    now: Date()
                )
            }
            .store(in: &cancellables)

        band.$isConnected
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] connected in
                guard let self else { return }
                if self.recorder.phase == .recording || self.recorder.phase == .paused {
                    self.recorder.tick()
                    self.pushUpdate(now: Date(), connectedOverride: connected)
                }
                if !connected {
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
        switch phase {
        case .recording:
            if let session = recorder.currentSession {
                if startedSessionID != session.id {
                    startedSessionID = session.id
                    lastRecordedHRAt = nil
                    sink.start(session: session, isConnected: band.isConnected)
                }
                recorder.tick()
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
        guard let observedAt else { return }
        if recorder.phase == .recording,
           observedAt != lastRecordedHRAt,
           let freshBPM = LiveHeartRateState.fresh(bpm, receivedAt: observedAt, connected: connected, now: now) {
            recorder.addHeartRateSample(freshBPM)
            lastRecordedHRAt = observedAt
        }
        if recorder.phase == .recording || recorder.phase == .paused {
            recorder.tick()
            pushUpdate(now: now, connectedOverride: connected)
        }
    }

    private func pushUpdate(now: Date = Date(), connectedOverride: Bool? = nil) {
        let connected = connectedOverride ?? band.isConnected
        let freshBPM = LiveHeartRateState.fresh(
            band.liveHeartRate, receivedAt: band.lastLiveHRAt, connected: connected, now: now
        )
        let today = JournalStore.dayKey(for: now)
        let estimatedStrain = band.liveDayStrainDateKey == today ? band.liveDayStrain : nil
        sink.update(
            session: recorder.currentSession,
            phase: recorder.phase,
            heartRate: freshBPM,
            maxHeartRate: maxHeartRateProvider(),
            distanceMeters: recorder.distanceMeters,
            elapsedSeconds: recorder.elapsedSeconds,
            steps: band.recordedTodayFromLedger,
            stepsObservedAt: band.capturedTodayStepAt,
            isConnected: connected,
            estimatedStrain: estimatedStrain
        )
    }
}
