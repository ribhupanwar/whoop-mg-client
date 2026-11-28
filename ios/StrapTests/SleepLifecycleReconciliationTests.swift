import XCTest
@testable import Strap

final class SleepLifecycleReconciliationTests: XCTestCase {
    func testPrematureTerminationReconcilesWhenDelayedHistoryExtendsNight() {
        var lifecycle = SleepLifecycleSnapshot()
        let start = 1_795_200_000
        let prematureEnd = start + 3_900 // ~1h5m premature end
        let fullEnd = start + 7 * 3_600

        lifecycle.confirm(sessionID: "\(start)-\(prematureEnd)", startUnix: start)
        lifecycle.observeProvisionalWake(sessionID: "\(start)-\(prematureEnd)")
        lifecycle.end(sessionID: "\(start)-\(prematureEnd)", at: prematureEnd)
        lifecycle.finishProcessing(sessionID: "\(start)-\(prematureEnd)", hasJournalQuestions: true)
        XCTAssertEqual(lifecycle.phase, .journalPending)

        let extended = SleepPeriod(
            startUnix: start, endUnix: fullEnd - 1,
            quietFraction: 0.98, meanHR: 64, wakeEvents: 1
        )
        let reconciled = lifecycle.reconcileAutomaticExtension(
            extended, id: "\(start)-\(fullEnd)", isEdited: false, isOngoing: false
        )
        XCTAssertTrue(reconciled)
        XCTAssertEqual(lifecycle.phase, .processing)
        XCTAssertEqual(lifecycle.sessionID, "\(start)-\(fullEnd)")
        XCTAssertEqual(lifecycle.endedAtUnix, fullEnd)
        XCTAssertFalse(lifecycle.journalPresented)

        lifecycle.finishProcessing(sessionID: "\(start)-\(fullEnd)", hasJournalQuestions: true)
        XCTAssertEqual(lifecycle.phase, .journalPending)
    }

    func testLateOnsetShiftReconcilesAndOngoingNightReopensToDetected() {
        var lifecycle = SleepLifecycleSnapshot()
        let lateStart = 1_795_203_600
        let earlyStart = lateStart - 2_400
        let firstEnd = lateStart + 4_200
        let ongoingEnd = lateStart + 10_800

        lifecycle.confirm(sessionID: "\(lateStart)-\(firstEnd)", startUnix: lateStart)
        lifecycle.end(sessionID: "\(lateStart)-\(firstEnd)", at: firstEnd)
        lifecycle.finishProcessing(sessionID: "\(lateStart)-\(firstEnd)", hasJournalQuestions: false)
        XCTAssertEqual(lifecycle.phase, .completed)

        let shifted = SleepPeriod(
            startUnix: earlyStart, endUnix: ongoingEnd - 1,
            quietFraction: 0.97, meanHR: 63, wakeEvents: 0
        )
        let reconciled = lifecycle.reconcileAutomaticExtension(
            shifted, id: "\(earlyStart)-\(ongoingEnd)", isEdited: false, isOngoing: true
        )
        XCTAssertTrue(reconciled)
        XCTAssertEqual(lifecycle.phase, .detected)
        XCTAssertEqual(lifecycle.confirmedStartUnix, earlyStart)
        XCTAssertNil(lifecycle.endedAtUnix)
        XCTAssertEqual(lifecycle.sessionID, "\(earlyStart)-\(ongoingEnd)")
    }

    func testEditedWakeBoundaryIsNeverOverriddenByAutomaticExtension() {
        var lifecycle = SleepLifecycleSnapshot()
        let start = 1_795_200_000
        let manualEnd = start + 5 * 3_600
        let extendedEnd = start + 8 * 3_600

        lifecycle.confirm(sessionID: "\(start)-\(manualEnd)", startUnix: start)
        lifecycle.end(sessionID: "\(start)-\(manualEnd)", at: manualEnd, resultingSessionID: "\(start)-\(manualEnd)")
        lifecycle.finishProcessing(sessionID: "\(start)-\(manualEnd)", hasJournalQuestions: false)

        let extended = SleepPeriod(
            startUnix: start, endUnix: extendedEnd - 1,
            quietFraction: 0.98, meanHR: 62, wakeEvents: 0
        )
        XCTAssertFalse(
            lifecycle.reconcileAutomaticExtension(
                extended, id: "\(start)-\(extendedEnd)", isEdited: true, isOngoing: false
            )
        )
        XCTAssertEqual(lifecycle.endedAtUnix, manualEnd)
        XCTAssertEqual(lifecycle.phase, .completed)
    }

    func testSeparateSubsequentNightDoesNotTriggerExtensionReconciliation() {
        var lifecycle = SleepLifecycleSnapshot()
        let night1Start = 1_795_100_000
        let night1End = night1Start + 7 * 3_600
        let night2Start = night1End + 16 * 3_600
        let night2End = night2Start + 7 * 3_600

        lifecycle.confirm(sessionID: "\(night1Start)-\(night1End)", startUnix: night1Start)
        lifecycle.end(sessionID: "\(night1Start)-\(night1End)", at: night1End)
        lifecycle.finishProcessing(sessionID: "\(night1Start)-\(night1End)", hasJournalQuestions: false)

        let nextNight = SleepPeriod(
            startUnix: night2Start, endUnix: night2End - 1,
            quietFraction: 0.98, meanHR: 64, wakeEvents: 0
        )
        XCTAssertFalse(
            lifecycle.reconcileAutomaticExtension(
                nextNight, id: "\(night2Start)-\(night2End)", isEdited: false, isOngoing: true
            )
        )
        lifecycle.confirm(sessionID: "\(night2Start)-\(night2End)", startUnix: night2Start)
        XCTAssertEqual(lifecycle.phase, .detected)
        XCTAssertEqual(lifecycle.confirmedStartUnix, night2Start)
    }

    func testCaptureSummaryMakeForwardsSleepTraceSink() {
        let base = 1_795_200_000
        var samples: [V18Sample] = []
        for offset in 0..<1800 {
            let header = BandRecordHeader(
                version: 18, flags: 128, recordIndex: UInt32(offset),
                unix: UInt32(base + offset), subsecQ15: 0
            )
            samples.append(V18Sample(
                header: header,
                heartRate: 92,
                rrIntervalsMS: [650],
                dynamicAccelG: 0.25,
                sleepState: 0
            ))
        }
        for offset in 1800..<9000 {
            let header = BandRecordHeader(
                version: 18, flags: 128, recordIndex: UInt32(offset),
                unix: UInt32(base + offset), subsecQ15: 0
            )
            samples.append(V18Sample(
                header: header,
                heartRate: 60,
                rrIntervalsMS: [1000],
                dynamicAccelG: 0.005,
                sleepState: 2
            ))
        }

        var gates: [String] = []
        let summary = CaptureSummary.make(
            samples: samples,
            sex: .male,
            maxHR: 190,
            sleepTraceSink: { trace in
                if let gate = trace["gate"] as? String { gates.append(gate) }
            }
        )
        XCTAssertFalse(summary.sleepPeriods.isEmpty)
        XCTAssertTrue(gates.contains("hrConfirm"))
    }
}

final class HomeProvisionalSleepNoticeTests: XCTestCase {
    private func shows(_ phase: SleepLifecyclePhase, id: String? = "100-18100",
                       latest: String? = "100-18100", edited: Bool = false,
                       today: Bool = true, preview: Bool = false) -> Bool {
        HomeProvisionalSleepNotice.shouldShow(phase: phase, lifecycleID: id, latestID: latest,
            isEdited: edited, isCurrentDay: today, isPreview: preview)
    }

    func testOnlyMatchingUneditedCurrentProvisionalWakeShowsNotice() {
        XCTAssertTrue(shows(.provisionalWake))
        XCTAssertFalse(shows(.provisionalWake, id: nil))
        XCTAssertFalse(shows(.provisionalWake, latest: nil))
        XCTAssertFalse(shows(.provisionalWake, latest: "100-25000"))
        XCTAssertFalse(shows(.provisionalWake, edited: true))
        XCTAssertFalse(shows(.provisionalWake, today: false))
        XCTAssertFalse(shows(.provisionalWake, preview: true))
    }

    func testResumedSleepAndCompletedShortNightAreNotSuppressed() {
        var lifecycle = SleepLifecycleSnapshot()
        let id = "100-18100" // five-hour window
        lifecycle.confirm(sessionID: id, startUnix: 100)
        lifecycle.observeProvisionalWake(sessionID: id)
        XCTAssertTrue(shows(lifecycle.phase))
        lifecycle.resume(sessionID: id)
        XCTAssertFalse(shows(lifecycle.phase))
        lifecycle.end(sessionID: id, at: 18100)
        XCTAssertFalse(shows(lifecycle.phase))
        lifecycle.finishProcessing(sessionID: id, hasJournalQuestions: false)
        XCTAssertEqual(lifecycle.phase, .completed)
        XCTAssertFalse(shows(lifecycle.phase))
        XCTAssertFalse(shows(.journalPending))
        XCTAssertFalse(shows(.idle))
    }
}
