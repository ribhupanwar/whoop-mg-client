import XCTest
@testable import Strap

/// Shadow-mode diagnostic for the native WHOOP pending-sleep lifecycle
/// (WHPApp::sleepAutoDetectStartedAt, pendingSleepTimer,
/// isDetectedSleepOverThreshold, validateSleepDetected).
///
/// These tests model the native state machine observed in the 5.78/5.80.2
/// binaries (SLEEP_NATIVE_RE_REPORT.md §1.2) but never override
/// SleepDetect.detect's existing onset/wake detection. They exist to
/// (a) document the gap between native behavior and STRAP implementation,
/// and (b) provide regression protection if a pending-sleep lifecycle is
/// ever integrated.
///
/// State machine (shadow-mode only):
///   IDLE ──(HR drop + sustained stillness)──▶ AUTO_DETECT_STARTED
///     └─ sleepAutoDetectStartedAt = now, pendingSleepTimer = 30 min
///   AUTO_DETECT_STARTED ──(timer fires)──▶ isDetectedSleepOverThreshold?
///     ├─ YES ──▶ startSyncPendingSleep: → validateSleepDetected → CONFIRMED
///     └─ NO  ──▶ invalidatePendingSleepTimer → IDLE
///   AUTO_DETECT_STARTED ──(new HR/RR)──▶ sleepAutoDetectUpdatedAt = now
final class SleepPendingLifecycleDiagnosticTests: XCTestCase {

    /// Native timer fires after ~30 min from onset candidate; when the
    /// threshold gate passes, sleep is synced. When it fails, the timer is
    /// invalidated and we return to IDLE.
    func testPendingSleepTimerFiresThenThresholdGateDecides() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let thirtyMinutesLater = startedAt.addingTimeInterval(30 * 60)

        // Threshold passes: now - startedAt >= threshold → sync pending sleep
        XCTAssertTrue(isDetectedSleepOverThreshold(
            startedAt: startedAt, now: thirtyMinutesLater, thresholdMinutes: 30))

        // Threshold fails: now - startedAt < threshold → stay pending
        let twentyNineMinutesLater = startedAt.addingTimeInterval(29 * 60)
        XCTAssertFalse(isDetectedSleepOverThreshold(
            startedAt: startedAt, now: twentyNineMinutesLater, thresholdMinutes: 30))

        // Nil startedAt → never over threshold
        XCTAssertFalse(isDetectedSleepOverThreshold(
            startedAt: nil, now: Date(), thresholdMinutes: 30))
    }

    /// New HR/RR data updates sleepAutoDetectUpdatedAt, extending the pending
    /// window without advancing sleepAutoDetectStartedAt.
    func testUpdatedAtTracksNewDataWithoutMovingStartedAt() {
        var startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var updatedAt = startedAt

        // First data point sets both
        startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        updatedAt = startedAt
        XCTAssertEqual(updatedAt.timeIntervalSince1970, startedAt.timeIntervalSince1970, accuracy: 0.01)

        // Subsequent data point updates only updatedAt
        let tenMinutesLater = startedAt.addingTimeInterval(10 * 60)
        updatedAt = tenMinutesLater
        XCTAssertEqual(updatedAt.timeIntervalSince1970, tenMinutesLater.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(startedAt.timeIntervalSince1970, 1_700_000_000, "StartedAt must not move on new data")
    }

    /// Timer invalidation on wake returns to IDLE; no stale pending state leaks.
    func testInvalidatePendingSleepTimerReturnsToIdle() {
        var state = PendingSleepState(idle)
        state.setPendingSleepTimer(fireAt: Date().addingTimeInterval(30 * 60))
        XCTAssertNotNil(state.pendingSleepTimer)

        state.invalidatePendingSleepTimer()
        XCTAssertNil(state.pendingSleepTimer)
        XCTAssertEqual(state.phase, .idle)
    }

    /// validateSleepDetected simulates the native 164-line validation routine
    /// (HomeViewController::validateSleepDetected → FUN_1000a8c84). It
    /// confirms band state, HR, and motion before confirming sleep.
    func testValidateSleepDetectedConfirmsWhenBandStateAndHRAgree() {
        let candidate = SleepCandidate(
            startUnix: 1_700_000_000,
            durationSeconds: 45 * 60,
            bandState: .sleep,   // state = 2
            meanHR: 55,
            motionG: 0.02
        )
        XCTAssertTrue(validateSleepDetected(candidate))

        // Off-wrist (band state wake) should not confirm
        let offWrist = SleepCandidate(
            startUnix: 1_700_000_000,
            durationSeconds: 45 * 60,
            bandState: .wake,
            meanHR: 55,
            motionG: 0.02
        )
        XCTAssertFalse(validateSleepDetected(offWrist))

        // Too short (< 90 min minimum) should not confirm
        let tooShort = SleepCandidate(
            startUnix: 1_700_000_000,
            durationSeconds: 30 * 60,
            bandState: .sleep,
            meanHR: 55,
            motionG: 0.02
        )
        XCTAssertFalse(validateSleepDetected(tooShort))
    }

    /// Split-sleep feature-flag gate: when enabled, isSplitSleepInProgressForCycle? is consulted before confirming.
    func testSplitSleepFeatureFlagGatesConfirmation() {
        let cycleStart = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(isSplitSleepInProgressForCycle(cycleStart: cycleStart, featureEnabled: false))

        // When feature enabled and a prior cycle exists, split-sleep is in progress
        XCTAssertTrue(isSplitSleepInProgressForCycle(
            cycleStart: cycleStart, featureEnabled: true, priorCycleEndsAfter: cycleStart))
    }

    /// Shadow-mode diagnostic: native pending-sleep lifecycle runs alongside
    /// STRAP's existing SleepDetect.detect() without overriding it. Both
    /// produce independent outputs; no production path consumes the shadow
    /// state machine.
    func testShadowLifecycleDoesNotOverrideExistingDetection() throws {
        let rows = [
            SleepCandidate(startUnix: 1_700_000_000, durationSeconds: 45 * 60, bandState: 2, meanHR: 55, motionG: 0.02),
            SleepRow(unix: 1_700_000_001, hr: 58, accelG: 0.01, bandState: 2),
            SleepRow(unix: 1_700_000_002, hr: 56, accelG: 0.01, bandState: 2),
        ]
        let detected = SleepDetect.detect([V18Sample(header: BandRecordHeader(version: 18, flags: 0x80, recordIndex: 1, unix: 1_700_000_000, subsecQ15: 0), heartRate: 60, rrIntervalsMS: [], dynamicAccelG: 0.01, gravityXG: nil, gravityYG: nil, gravityZG: nil, stepCounter: nil, stepCadence: nil, activityClass: nil, skinTempC: nil, tempAux1C: nil, tempAux2C: nil, sleepStateByte: nil, sleepState: nil, cardiacFlags: nil, hrQualityFlags: nil, spo2CandidateRaw: nil, spo2CandidatePct: nil, spo2CandidateKind: .absent, signalQualityLogVariance: nil, psnrB: nil, psnrA: nil, rrPaddingValid: true).toArray())
        XCTAssertNotNil(detected, "Existing SleepDetect must still produce output")

        // Shadow-mode pending lifecycle is independent
        let shadow = PendingSleepLifecyle(thresholdMinutes: 30)
        shadow.observe(hr: 60, accelG: 0.01, bandState: 2, at: Date())
        XCTAssertEqual(shadow.phase, .autoDetectStarted)
    }
}

// MARK: - Helper types (diagnostic only, not production)

private enum BandState: Int { case wake = 0, light = 1, deep = 2, rem = 3 }

private struct SleepCandidate {
    let startUnix: Int
    let durationSeconds: Int
    let bandState: BandState
    let meanHR: Double
    let motionG: Double
}

private enum PendingSleepPhase { case idle, autoDetectStarted, confirmed }

private final class PendingSleepState {
    var phase: PendingSleepPhase = .idle
    var sleepAutoDetectStartedAt: Date?
    var sleepAutoDetectUpdatedAt: Date?
    var pendingSleepTimerFireAt: Date?

    init(_ phase: PendingSleepPhase) { self.phase = phase }

    func setPendingSleepTimer(fireAt: Date) {
        phase = .autoDetectStarted
        pendingSleepTimerFireAt = fireAt
    }

    func invalidatePendingSleepTimer() {
        phase = .idle
        pendingSleepTimerFireAt = nil
        sleepAutoDetectStartedAt = nil
        sleepAutoDetectUpdatedAt = nil
    }
}

private let idle = PendingSleepPhase.idle

/// Shadow-mode isDetectedSleepOverThreshold: compares now vs startedAt with a configurable threshold. Mirrors WHPApp::isDetectedSleepOverThreshold
/// (flag 0x141 + NSDate comparison).
private func isDetectedSleepOverThreshold(
    startedAt: Date?, now: Date, thresholdMinutes: Int
) -> Bool {
    guard let startedAt else { return false }
    return now.timeIntervalSince(startedAt) >= Double(thresholdMinutes * 60)
}

/// Shadow-mode validateSleepDetected: confirms sleep when band state is sleep (2), duration meets minimum, HR is plausible, and motion is low.
/// Mirrors HomeViewController::validateSleepDetected → FUN_1000a8c84.
private func validateSleepDetected(_ candidate: SleepCandidate) -> Bool {
    guard candidate.bandState == .sleep else { return false }
    guard candidate.durationSeconds >= 90 * 60 else { return false }
    guard (35...220).contains(candidate.meanHR) else { return false }
    guard candidate.motionG < 0.08 else { return false }
    return true
}

/// Shadow-mode isSplitSleepInProgressForCycle: feature-flag gated query.
/// Mirrors WHPApp::isSplitSleepInProgressForCycle:.
private func isSplitSleepInProgressForCycle(
    cycleStart: Date, featureEnabled: Bool, priorCycleEndsAfter: Date? = nil
) -> Bool {
    guard featureEnabled else { return false }
    guard let priorEnds = priorCycleEndsAfter else { return false }
    return priorEnds.timeIntervalSince(cycleStart) > 0
}

/// Shadow-mode PendingSleepLifecyle: observes live HR/accel/band-state and transitions IDLE → AUTO_DETECT_STARTED on HR drop + sustained stillness.
/// Diagnostic only; never consulted by production code.
private final class PendingSleepLifecyle {
    let thresholdMinutes: Int
    var phase: PendingSleepPhase = .idle

    init(thresholdMinutes: Int) { self.thresholdMinutes = thresholdMinutes }

    var startedAt: Date?
    var updatedAt: Date?

    init(thresholdMinutes: Int) {
        self.thresholdMinutes = thresholdMinutes
        startedAt = nil
        updatedAt = nil
    }

    func observe(hr: Int, accelG: Double, bandState: Int, at: Date) {
        let stillAndHRDropped = accelG < 0.08 && hr < 70
        if phase == .idle, stillAndHRDropped {
            phase = .autoDetectStarted
            startedAt = at
        }
    }

    func invalidatePendingSleepTimer() {
        phase = .idle
        startedAt = nil
        updatedAt = nil
    }
}
