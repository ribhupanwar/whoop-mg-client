import XCTest
@testable import Strap

final class SleepSessionTests: XCTestCase {
    func testNovember22DetectedWindowEndsBeforeAwakeArchiveFrontier() {
        let start = 1_795_288_513
        let end = 1_795_309_557
        func session(edited: Bool) -> SleepSession {
            SleepSession(version: 6, sourceStartUnix: start, startUnix: start, endUnix: end,
                         staging: .unavailable, heartRate: [], movementBouts: 0, isEdited: edited)
        }
        let lastAwake = 1_795_310_187
        XCTAssertFalse(session(edited: false).canEndNow(lastObservedUnix: lastAwake, nowUnix: lastAwake + 1))
        XCTAssertTrue(session(edited: false).canEndNow(lastObservedUnix: end - 1, nowUnix: end + 60))
        XCTAssertFalse(session(edited: false).canEndNow(lastObservedUnix: end - 1, nowUnix: end + 901))
        XCTAssertFalse(session(edited: true).canEndNow(lastObservedUnix: end - 1, nowUnix: end + 60))
        XCTAssertFalse(session(edited: false).canEndNow(lastObservedUnix: nil, nowUnix: end + 60))
    }

    func testCorruptedExtremeCorrectionKeysCannotCrashAliasResolution() {
        let night = period(3600)
        let edit = [start + 120, start + 3300]
        let overrides = [String(Int.min): edit, String(Int.max): edit]
        XCTAssertNil(SleepCorrectionStore.times(for: night, overrides: overrides))
        let saved = SleepCorrectionStore.saving(edit, for: night, overrides: overrides)
        XCTAssertEqual(saved[String(night.startUnix)], edit)
        XCTAssertEqual(saved[String(Int.min)], edit, "Do not destroy unrelated historical overrides")
        XCTAssertEqual(saved[String(Int.max)], edit)
    }

    func testMakeAllIgnoresExtremeLegacyKeysWithoutCrashing() {
        let night = period(3600)
        let edit = [start + 120, start + 3300]
        let overrides = [String(Int.min): edit, String(Int.max): edit]
        let result = SleepSession.makeAll(samples: [], periods: [night], overrides: overrides)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].startUnix, night.startUnix)
        XCTAssertEqual(result[0].endUnix, night.endUnix + 1)
        XCTAssertFalse(result[0].isEdited)
    }

    func testSavedBoundsSurviveColdReloadWithoutStaleStagesOrScores() throws {
        let rows = (0..<3600).map { sample(start + $0) }
        let old = SleepSession.make(samples: rows, period: period(3600))
        let times = [start + 300, start + 3300]
        let overrides = [String(start): times]
        let immediate = old.applyingSavedBounds(overrides)
        XCTAssertEqual(immediate.startUnix, times[0])
        XCTAssertEqual(immediate.endUnix, times[1])
        XCTAssertTrue(immediate.isEdited)
        XCTAssertNil(immediate.asleepHours, "Old stages do not describe newly edited bounds")
        let reopened = try JSONDecoder().decode(SleepSession.self, from: JSONEncoder().encode(immediate))
        XCTAssertEqual(reopened.applyingSavedBounds(overrides), immediate)
        let fresh = SleepSession.makeAll(samples: rows, periods: [period(3600)], overrides: overrides)
        let retained = SleepSession.retainingUncovered(previous: [reopened], fresh: fresh,
            coverageStart: start, coverageEnd: start + 3599, samples: rows, overrides: overrides)
        let corrected = try XCTUnwrap(retained.first)
        XCTAssertEqual(corrected.startUnix, times[0])
        XCTAssertEqual(corrected.endUnix, times[1])
        let report = try XCTUnwrap(SleepReport.analyze(samples: rows, session: corrected, needHours: 8,
                                                      nights: [], sleepBaseline: nil))
        XCTAssertEqual(report.hours, try XCTUnwrap(corrected.asleepHours), accuracy: 1e-9)
        XCTAssertLessThan(report.hours, try XCTUnwrap(old.asleepHours))
        XCTAssertEqual(report.hoursVsNeededPct, report.hours / 8 * 100, accuracy: 1e-9)
        let baseline = Baseline.fromDaily(lnRMSSD: Array(repeating: log(28.0), count: 7), rhr: Array(repeating: 60, count: 7))
        let recovery = Recovery.score(lnRMSSD: log(28), rhr: 60, sleepHours: corrected.asleepHours,
                                      sleepNeedHours: 8, baseline: baseline)
        XCTAssertEqual(try XCTUnwrap(recovery.sleepComponent), Stats.rounded(report.hoursVsNeededPct, 1))
    }


    func testOfflineWakeEditPersistsButCannotReuseOldRecoveryOrSleepScore() throws {
        let rows = (0..<3600).map { sample(start + $0) }
        let old = SleepSession.make(samples: rows, period: period(3600))
        XCTAssertTrue(old.isComplete)
        let editedBounds = [start + 300, start + 3300]
        let overrides = [String(start): editedBounds]
        let offline = SleepSession.retainingUncovered(
            previous: [old], fresh: [], coverageStart: nil, coverageEnd: nil,
            samples: [], overrides: overrides
        )
        let corrected = try XCTUnwrap(offline.first)
        XCTAssertEqual(offline.count, 1)
        XCTAssertEqual(corrected.startUnix, editedBounds[0])
        XCTAssertEqual(corrected.endUnix, editedBounds[1])
        XCTAssertTrue(corrected.isEdited)
        XCTAssertNil(corrected.asleepHours,
                     "No recovered sensor coverage means no defensible sleep duration")
        XCTAssertNil(SleepReport.analyze(samples: [], session: corrected,
                                         needHours: 8, nights: [], sleepBaseline: nil))
        let reopened = try JSONDecoder().decode([SleepSession].self,
                                                 from: JSONEncoder().encode(offline))
        XCTAssertEqual(reopened, offline)
        XCTAssertEqual(SleepSession.retainingUncovered(
            previous: reopened, fresh: [], coverageStart: nil, coverageEnd: nil,
            samples: [], overrides: overrides
        ), reopened, "Repeated offline replay must not move saved wake time")
    }

    func testAuthoritativeNightMergeClearsObsoleteBiometricsButKeepsRecordedSteps() {
        let old = DayMetrics(dateKey: "2026-11-17", state: "sleep", restingHR: 63, lnRMSSD: log(28),
            hrvWindowSeconds: 600, sleepHours: 7, sleepStartUnix: start, sleepEndUnix: start + 8 * 3600,
            strain: 4, steps: 9000, sleepDurationReliable: true)
        let edited = DayMetrics(dateKey: old.dateKey, state: "sleep", restingHR: nil, lnRMSSD: nil,
            hrvWindowSeconds: 0, sleepHours: 0, sleepStartUnix: start + 300, sleepEndUnix: start + 3600,
            strain: nil, steps: nil, sleepDurationReliable: false)
        let merged = DailyAnalysis.mergeDay(previous: old, fresh: edited, replacesSleep: true)
        XCTAssertNil(merged.restingHR)
        XCTAssertNil(merged.lnRMSSD)
        XCTAssertEqual(merged.hrvWindowSeconds, 0)
        XCTAssertEqual(merged.sleepStartUnix, edited.sleepStartUnix)
        XCTAssertEqual(merged.steps, 9000)
        let partial = DailyAnalysis.mergeDay(previous: old, fresh: edited, replacesSleep: false)
        XCTAssertEqual(partial.restingHR, 63)
        XCTAssertEqual(partial.lnRMSSD, old.lnRMSSD)
        XCTAssertEqual(partial.sleepStartUnix, old.sleepStartUnix)
    }

    private let start = 1_800_000_000

    private func sample(_ unix: Int, hr: Int = 55, stepCounter: Int? = nil) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(version: 18, flags: 0x80, recordIndex: UInt32(unix), unix: UInt32(unix), subsecQ15: 0),
            heartRate: hr, rrIntervalsMS: [], dynamicAccelG: 0.01,
            gravityXG: 0, gravityYG: 0, gravityZG: 1,
            stepCounter: stepCounter, stepCadence: nil, activityClass: 0,
            skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: nil, sleepState: nil, cardiacFlags: nil, hrQualityFlags: nil,
            spo2CandidateRaw: nil, spo2CandidatePct: nil, spo2CandidateKind: .absent,
            signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
        )
    }
    private func confirmedSleepSample(_ unix: Int) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(version: 18, flags: 0x80, recordIndex: UInt32(unix), unix: UInt32(unix), subsecQ15: 0),
            heartRate: 62, rrIntervalsMS: [], dynamicAccelG: 0.01,
            gravityXG: 0, gravityYG: 0, gravityZG: 1,
            stepCounter: nil, stepCadence: nil, activityClass: 0,
            skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: nil, sleepState: 2, cardiacFlags: nil, hrQualityFlags: nil,
            spo2CandidateRaw: nil, spo2CandidatePct: nil, spo2CandidateKind: .absent,
            signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
        )
    }

    func testDelayedHistoryExtendsUnownedEditedBoundaryButPreservesExplicitCorrection() {
        let oldEnd = start + 6 * 3600
        let newEnd = oldEnd + 28 * 60
        let old = SleepSession(version: SleepSession.algorithmVersion,
            sourceStartUnix: start, startUnix: start, endUnix: oldEnd,
            staging: .unavailable, heartRate: [], movementBouts: 0,
            isEdited: true, sourceEndUnix: oldEnd, bandSleepConfirmed: true)
        let fresh = SleepSession(version: SleepSession.algorithmVersion,
            sourceStartUnix: start, startUnix: start, endUnix: newEnd,
            staging: .unavailable, heartRate: [], movementBouts: 0,
            isEdited: false, sourceEndUnix: newEnd, bandSleepConfirmed: true)
        let late = (oldEnd..<newEnd).map { confirmedSleepSample($0) }
        let repaired = SleepSession.retainingUncovered(previous: [old], fresh: [fresh],
            coverageStart: start, coverageEnd: newEnd - 1, samples: late)
        XCTAssertEqual(repaired.map(\.endUnix), [newEnd])
        let protected = SleepSession.retainingUncovered(previous: [old], fresh: [fresh],
            coverageStart: start, coverageEnd: newEnd - 1, samples: late,
            overrides: [String(start): [start, oldEnd]])
        XCTAssertEqual(protected.map(\.endUnix), [oldEnd])
        let insufficient = SleepSession.retainingUncovered(previous: [old], fresh: [fresh],
            coverageStart: start, coverageEnd: newEnd - 1, samples: Array(late.prefix(299)))
        XCTAssertEqual(insufficient.map(\.endUnix), [oldEnd])
    }

    private func period(_ seconds: Int, quiet: Double = 0.2) -> SleepPeriod {
        SleepPeriod(startUnix: start, endUnix: start + seconds - 1, quietFraction: quiet, meanHR: 55, wakeEvents: 1436)
    }
    private func knownNight() -> SleepSession {
        let wakeEnd = start + 27 * 60
        let end = start + 492 * 60
        let staging = SleepStaging(
            segments: [
                SleepStageSegment(startUnix: start, endUnix: wakeEnd, stage: .wake),
                SleepStageSegment(startUnix: wakeEnd, endUnix: end, stage: .light)
            ],
            deepMinutes: 0, lightMinutes: 465, remMinutes: 0, wakeMinutes: 27,
            epochs: 984, hrCoverage: 1, reason: nil
        )
        return SleepSession(version: SleepSession.algorithmVersion, sourceStartUnix: start,
                            startUnix: start, endUnix: end, staging: staging,
                            heartRate: [], movementBouts: 29, isEdited: true, sourceEndUnix: end)
    }
    func testAlgorithmUpgradeRetainsOlderNightAndManualBoundsWithPartialCoverage() {
        let current = knownNight()
        for edited in [false, true] {
            let legacy = SleepSession(version: 1, sourceStartUnix: current.sourceStartUnix,
                startUnix: current.startUnix, endUnix: current.endUnix, staging: current.staging,
                heartRate: current.heartRate, movementBouts: current.movementBouts,
                isEdited: edited, sourceEndUnix: current.sourceEndUnix)
            let kept = SleepSession.retainingUncovered(previous: [legacy], fresh: [],
                coverageStart: legacy.startUnix + 3600, coverageEnd: legacy.endUnix - 1)
            XCTAssertEqual(kept, [legacy], "A recipe upgrade must not delete a retained night")
        }
    }

    func testAlgorithmUpgradeRecalculatesOlderEditedNightOnlyWithCompleteCoverage() {
        let rows = (0..<600).map { sample(start + $0) }
        let current = SleepSession.make(samples: rows, period: period(600),
                                       correctedTimes: [start, start + 600])
        let legacy = SleepSession(version: 1, sourceStartUnix: current.sourceStartUnix,
            startUnix: current.startUnix, endUnix: current.endUnix, staging: current.staging,
            heartRate: current.heartRate, movementBouts: current.movementBouts,
            isEdited: true, sourceEndUnix: current.sourceEndUnix)
        let refreshed = SleepSession.retainingUncovered(previous: [legacy], fresh: [],
            coverageStart: start, coverageEnd: start + 599, samples: rows)
        XCTAssertEqual(refreshed.count, 1)
        XCTAssertEqual(refreshed.first?.version, SleepSession.algorithmVersion)
        XCTAssertEqual(refreshed.first?.startUnix, legacy.startUnix)
        XCTAssertEqual(refreshed.first?.endUnix, legacy.endUnix)
        XCTAssertEqual(refreshed.first?.isEdited, true)
        XCTAssertTrue(refreshed.first?.isComplete == true)
    }

    func testDiagnosticCSVUsesEditedBoundsAndDoesNotFillMissingSeconds() throws {
        let rows = [1700, 1800, 1801, 2000, 3000].map {
            sample(start + $0, stepCounter: $0 == 1801 ? 123 : nil)
        }
        let edited = SleepSession.make(samples: rows, period: period(3600),
                                       correctedTimes: [start + 1800, start + 3000])
        let csv = try SleepDiagnostics.csv(samples: rows, session: edited)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 4, "Header plus only three observed in-window samples")
        let values = lines.dropFirst().map { $0.split(separator: ",", omittingEmptySubsequences: false) }
        let header = lines[0].split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(header.count, 26)
        XCTAssertTrue(values.allSatisfy { $0.count == header.count })
        let stepIndex = try XCTUnwrap(header.firstIndex(of: "step_motion_counter"))
        XCTAssertEqual(values.map { String($0[stepIndex]) }, ["", "123", ""])
        let tempIndex = try XCTUnwrap(header.firstIndex(of: "skin_temp_c"))
        let oxygenIndex = try XCTUnwrap(header.firstIndex(of: "spo2_candidate_pct"))
        XCTAssertTrue(values.allSatisfy { $0[tempIndex].isEmpty && $0[oxygenIndex].isEmpty })
        XCTAssertEqual(values.map { Int($0[3])! }, [start + 1800, start + 1801, start + 2000])
        XCTAssertTrue(values.allSatisfy { $0[7].isEmpty }, "Missing R-R stays empty")
        XCTAssertThrowsError(try SleepDiagnostics.csv(samples: [], session: edited))
    }

    func testDiagnosticPreSleepExportIncludesOnlyAvailableEarlierSamples() throws {
        let rows = [-1900, -1800, -900, -1, 0, 1, 60].map { sample(start + $0) }
        let session = SleepSession.make(samples: rows, period: period(60))
        let csv = try SleepDiagnostics.csv(samples: rows, session: session, preSleepSeconds: 1800)
        let lines = csv.split(separator: "\n").dropFirst()
        let timestamps = lines.compactMap { Int($0.split(separator: ",", omittingEmptySubsequences: false)[3]) }
        XCTAssertEqual(timestamps, [start - 1800, start - 900, start - 1, start, start + 1])
        XCTAssertFalse(timestamps.contains(start - 1900))
        XCTAssertFalse(timestamps.contains(start + 60))
        XCTAssertEqual(try SleepDiagnostics.csv(samples: rows, session: session),
                       try SleepDiagnostics.csv(samples: rows, session: session, preSleepSeconds: 0))
    }

    func testDiagnosticExportWritesAReadableLocalCSV() throws {
        let rows = (0..<60).map { sample(start + $0) }
        let session = SleepSession.make(samples: rows, period: period(60))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try SleepDiagnostics.write(samples: rows, session: session, directory: directory)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8),
                       try SleepDiagnostics.csv(samples: rows, session: session))
        XCTAssertEqual(url.pathExtension, "csv")
    }

    func testOneTotalDrivesAsleepEfficiencyAndReportWithoutDoubleSubtraction() throws {
        let session = knownNight()
        XCTAssertEqual(try XCTUnwrap(session.asleepHours), 7.75, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(session.awakeHours), 0.45, accuracy: 1e-9)
        XCTAssertEqual(session.timeInBedHours, 8.2, accuracy: 1e-9)
        XCTAssertEqual(session.unclassifiedHours, 0, accuracy: 1e-9)
        let report = try XCTUnwrap(SleepReport.analyze(
            samples: [], session: session, needHours: 8, nights: [], sleepBaseline: nil
        ))
        XCTAssertEqual(report.hours, 7.75, accuracy: 1e-9)
        XCTAssertEqual(report.hoursVsNeededPct, 96.875, accuracy: 1e-9)
        XCTAssertEqual(report.efficiencyPct, 100 * 465.0 / 492, accuracy: 1e-9)
        XCTAssertEqual(report.wakeEvents, 29)
        XCTAssertEqual(CoachFormat.duration(report.hours), "7:45")
    }
    func testEditingRecomputesExactBoundsNotOldQuietFraction() {
        let samples = (0..<7200).map { sample(start + $0) }
        let times = [start + 1800, start + 5400]
        let a = SleepSession.make(samples: samples, period: period(7200, quiet: 0.2), correctedTimes: times)
        let b = SleepSession.make(samples: samples, period: period(7200, quiet: 0.9), correctedTimes: times)
        XCTAssertEqual(a, b, "An obsolete detector fraction must not change sleep duration")
        XCTAssertEqual(a.startUnix, times[0])
        XCTAssertEqual(a.endUnix, times[1])
        XCTAssertEqual(a.timeInBedHours, 1, accuracy: 1e-9)
        XCTAssertEqual(a.staging.totalMinutes, 60, accuracy: 1e-9)
        XCTAssertTrue(a.isComplete)
        XCTAssertTrue(a.heartRate.allSatisfy { times[0] <= $0.unix && $0.unix < times[1] })
        XCTAssertEqual(a.movementBouts, 0, "Do not copy the old 1436-event counter")
    }
    func testRepeatedBuildAndReloadPreserveSameResult() throws {
        let samples = (0..<3600).map { sample(start + $0) }
        let first = SleepSession.make(samples: samples, period: period(3600))
        let repeated = SleepSession.make(samples: samples, period: period(3600))
        XCTAssertEqual(first, repeated)
        let decoded = try JSONDecoder().decode(SleepSession.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(decoded, first)
    }
    func testLowCoverageIsNotHoursOfAwakeOrDebt() {
        let samples = (0..<900).map { sample(start + $0) }
        let session = SleepSession.make(samples: samples, period: period(3600))
        XCTAssertNil(session.asleepHours)
        XCTAssertNil(session.awakeHours)
        XCTAssertEqual(session.classifiedAwakeHours, 0)
        XCTAssertEqual(session.unclassifiedHours, 1, accuracy: 1e-9)
        XCTAssertNil(SleepReport.analyze(samples: samples, session: session, needHours: 8, nights: [], sleepBaseline: nil))
    }
    func testPartialStagesCannotProduceFullNightScore() {
        let samples = (0..<3600).filter { !(1200..<1500).contains($0) }.map { sample(start + $0) }
        let session = SleepSession.make(samples: samples, period: period(3600))
        XCTAssertTrue(session.staging.stageable)
        XCTAssertFalse(session.isComplete)
        XCTAssertNil(session.asleepHours)
        XCTAssertNil(session.awakeHours)
        XCTAssertEqual(session.unclassifiedHours, 300.0 / 3600, accuracy: 1e-9)
        XCTAssertNil(SleepReport.analyze(samples: samples, session: session, needHours: 8, nights: [], sleepBaseline: nil))
    }
    func testHRBucketsPreserveLongGapAndEditedScope() {
        let samples = [sample(start), sample(start + 1), sample(start + 600)]
        let session = SleepSession.make(samples: samples, period: period(1800))
        XCTAssertEqual(session.heartRate.count, 2)
        XCTAssertEqual(session.heartRate[1].unix - session.heartRate[0].unix, 600)
    }
    func testCorrectionsRejectMalformedOrOverlongWindows() {
        XCTAssertNil(SleepCorrectionStore.validated([start]))
        XCTAssertNil(SleepCorrectionStore.validated([start + 1, start]))
        XCTAssertNil(SleepCorrectionStore.validated([start, start + 24 * 3600 + 1]))
        XCTAssertNil(SleepCorrectionStore.validated([0, 3600]))
    }
    func testCorrectionSurvivesSmallOnsetShiftButNotAnotherNight() {
        let times = [start + 1800, start + 7200]
        XCTAssertEqual(SleepCorrectionStore.times(for: period(9000), overrides: [String(start - 300): times]), times)
        XCTAssertNil(SleepCorrectionStore.times(for: period(9000), overrides: [String(start - 86400): times]))
    }
    func testOneEditReplacesOverlappingFragmentsWithoutDoubleCounting() {
        let samples = (0..<7200).map { sample(start + $0) }
        let fragments = [
            SleepPeriod(startUnix: start, endUnix: start + 3599, quietFraction: 0.9, meanHR: 55, wakeEvents: 0),
            SleepPeriod(startUnix: start + 3900, endUnix: start + 7199, quietFraction: 0.9, meanHR: 55, wakeEvents: 0)
        ]
        let sessions = SleepSession.makeAll(
            samples: samples, periods: fragments,
            overrides: [String(start): [start, start + 7200]]
        )
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.reduce(0.0) { $0 + $1.timeInBedHours }, 2, accuracy: 1e-9)
    }

    func testMissingArchiveCoverageRetainsOldNightAndAddsNonOverlappingNewNight() {
        let old = knownNight()
        let next = SleepSession.make(samples: [], period: SleepPeriod(
            startUnix: old.endUnix + 3600, endUnix: old.endUnix + 7200 - 1,
            quietFraction: 0, meanHR: 0, wakeEvents: 0
        ))
        let merged = SleepSession.retainingUncovered(
            previous: [old], fresh: [next], coverageStart: nil, coverageEnd: nil
        )
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0], old)
        XCTAssertEqual(merged[1], next)
    }

    func testRollingPartialArchivePreservesPreviousNight() {
        let previous = DayMetrics(
            dateKey: "2026-11-12", state: "sleep", restingHR: nil, lnRMSSD: nil,
            hrvWindowSeconds: 0, sleepHours: 7.75, sleepStartUnix: start,
            sleepEndUnix: start + 8 * 3600 - 1, strain: nil, steps: nil,
            sleepDurationReliable: true
        )
        let emptyDay = DayMetrics(
            dateKey: previous.dateKey, state: "awake", restingHR: nil, lnRMSSD: nil,
            hrvWindowSeconds: 0, sleepHours: 0, sleepStartUnix: nil,
            sleepEndUnix: nil, strain: nil, steps: nil, sleepDurationReliable: false
        )
        XCTAssertFalse(DailyAnalysis.replacesSleep(previous: previous, fresh: emptyDay,
                                                  coverageStart: start + 12 * 3600, coverageEnd: start + 24 * 3600))
        XCTAssertTrue(DailyAnalysis.replacesSleep(previous: previous, fresh: emptyDay,
                                                 coverageStart: start, coverageEnd: start + 24 * 3600))
        XCTAssertNil(emptyDay.reliableSleepHours)
        XCTAssertEqual(previous.reliableSleepHours, 7.75)
        XCTAssertEqual(previous.night?.endUnix, start + 8 * 3600)
    }

    func testDifferingOverlappingCorrectionsNeverCreateTwoNights() {
        let fragments = [
            period(3600),
            SleepPeriod(startUnix: start + 3900, endUnix: start + 7199,
                        quietFraction: 0.9, meanHR: 55, wakeEvents: 0)
        ]
        let overrides = [
            String(start): [start, start + 7200],
            String(start + 3900): [start, start + 6900]
        ]
        let sessions = SleepSession.makeAll(samples: [], periods: fragments, overrides: overrides)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.endUnix, start + 6900)
        XCTAssertEqual(SleepSession.makeAll(samples: [], periods: fragments, overrides: overrides), sessions)
    }

    func testSavingRecoveredCorrectionRemovesOldAliasesButKeepsAnotherNight() {
        let shifted = SleepPeriod(startUnix: start + 300, endUnix: start + 7199,
                                  quietFraction: 0.9, meanHR: 55, wakeEvents: 0)
        let nextKey = String(start + 86400)
        let overrides = [
            String(start): [start, start + 7200],
            String(start + 3900): [start, start + 6900],
            nextKey: [start + 86400, start + 93600]
        ]
        let times = [start, start + 6600]
        let saved = SleepCorrectionStore.saving(times, for: shifted, overrides: overrides)
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved[String(shifted.startUnix)], times)
        XCTAssertNil(saved[String(start)])
        XCTAssertNil(saved[String(start + 3900)])
        XCTAssertEqual(saved[nextKey], overrides[nextKey])
        XCTAssertEqual(SleepCorrectionStore.saving(times, for: shifted, overrides: saved), saved)
    }

    func testMissingRawCoverageRetainsEditedCanonicalNight() {
        let old = knownNight()
        XCTAssertEqual(SleepSession.retainingUncovered(
            previous: [old], fresh: [], coverageStart: nil, coverageEnd: nil
        ), [old])
        XCTAssertEqual(SleepSession.retainingUncovered(
            previous: [old], fresh: [], coverageStart: start, coverageEnd: nil
        ), [old])
        XCTAssertEqual(SleepSession.retainingUncovered(
            previous: [], fresh: [old], coverageStart: nil, coverageEnd: nil
        ), [old])
    }

    func testCompleteRetainedTailDoesNotReplaceSavedCanonicalNight() throws {
        let old = knownNight()
        let tailStart = start + 5 * 3600
        let tailPeriod = SleepPeriod(startUnix: tailStart, endUnix: old.endUnix - 1,
                                     quietFraction: 0.9, meanHR: 55, wakeEvents: 0)
        let samples = (tailStart..<old.endUnix).map { sample($0) }
        let tail = SleepSession.make(samples: samples, period: tailPeriod)
        XCTAssertTrue(tail.isComplete, "The tail can have full HR coverage without being a full night")
        let retained = SleepSession.retainingUncovered(
            previous: [old], fresh: [tail], coverageStart: tailStart, coverageEnd: old.endUnix - 1
        )
        XCTAssertEqual(retained, [old])
        XCTAssertEqual(try XCTUnwrap(retained.last?.asleepHours), 7.75, accuracy: 1e-9)
        let decoded = try JSONDecoder().decode([SleepSession].self, from: JSONEncoder().encode(retained))
        XCTAssertEqual(decoded, retained)
        XCTAssertEqual(SleepSession.retainingUncovered(
            previous: [old], fresh: [tail], coverageStart: start, coverageEnd: old.endUnix - 1
        ), [old], "Full archive replay must preserve a manually edited canonical night")
        let edited = SleepSession.make(samples: samples, period: tailPeriod,
                                       correctedTimes: [tailStart, old.endUnix])
        XCTAssertEqual(SleepSession.retainingUncovered(
            previous: [old], fresh: [edited], coverageStart: tailStart, coverageEnd: old.endUnix - 1
        ), [edited], "An intentional new window must not be replaced by an old saved window")
    }

    func testEditedNightRefreshesWhenCompleteHistoryArrives() throws {
        let source = period(7200)
        let times = [start + 600, start + 4200]
        let old = SleepSession.make(samples: [], period: source, correctedTimes: times)
        XCTAssertNil(old.asleepHours)
        let rows = (times[0]..<times[1]).map { sample($0) }
        // Detector drift must neither move the edit nor prevent its refresh.
        let shifted = SleepPeriod(startUnix: start + 900, endUnix: start + 4199,
                                  quietFraction: 0.9, meanHR: 55, wakeEvents: 0)
        let fresh = SleepSession.make(samples: rows, period: shifted)
        let result = SleepSession.retainingUncovered(
            previous: [old], fresh: [fresh], coverageStart: times[0], coverageEnd: times[1] - 1,
            samples: rows, overrides: [String(source.startUnix): times]
        )
        let updated = try XCTUnwrap(result.first)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(updated.startUnix, times[0])
        XCTAssertEqual(updated.endUnix, times[1])
        XCTAssertEqual(updated.sourcePeriod, old.sourcePeriod)
        XCTAssertTrue(updated.isEdited)
        XCTAssertTrue(updated.isComplete)
        XCTAssertNotNil(updated.asleepHours)
        XCTAssertFalse(updated.heartRate.isEmpty)
        XCTAssertNotNil(SleepReport.analyze(samples: rows, session: updated, needHours: 8,
                                           nights: [], sleepBaseline: nil))
        XCTAssertEqual(SleepSession.retainingUncovered(
            previous: result, fresh: [fresh], coverageStart: times[0], coverageEnd: times[1] - 1,
            samples: rows, overrides: [String(source.startUnix): times]
        ), result, "Replaying the same history must be stable")
    }

    func testEditedNightRefreshesPreviouslyCompleteMeasurements() throws {
        let source = period(3600)
        let times = [start, start + 3600]
        let originalRows = (start..<(start + 3600)).map { sample($0) }
        let old = SleepSession.make(samples: originalRows, period: source, correctedTimes: times)
        XCTAssertTrue(old.isComplete)
        // Recovered packets replace the original constant HR with actual values.
        let rows = (start..<(start + 3600)).map { sample($0, hr: 65) }
        let expected = SleepSession.make(samples: rows, period: source, correctedTimes: times)
        let result = SleepSession.retainingUncovered(
            previous: [old], fresh: [], coverageStart: start, coverageEnd: start + 3599,
            samples: rows
        )
        XCTAssertEqual(result, [expected])
        XCTAssertNotEqual(result.first?.heartRate, old.heartRate)
    }

    func testGappedReplayCannotEraseCompleteEditedNight() {
        let old = knownNight()
        // Archive endpoints alone do not prove that the interior was recovered.
        let rows = [sample(old.startUnix), sample(old.endUnix - 1)]
        XCTAssertEqual(SleepSession.retainingUncovered(
            previous: [old], fresh: [], coverageStart: old.startUnix,
            coverageEnd: old.endUnix - 1, samples: rows
        ), [old])
    }

    func testShortenedEditedNightDoesNotRegainExcludedTailAfterTrimming() throws {
        let source = period(8 * 3600)
        let old = SleepSession.make(samples: (0..<7200).map { sample(start + $0) },
                                    period: source, correctedTimes: [start, start + 7200])
        XCTAssertTrue(old.isComplete)
        XCTAssertEqual(old.sourcePeriod.startUnix, source.startUnix)
        XCTAssertEqual(old.sourcePeriod.endUnix, source.endUnix, "Keep the original bounds for re-editing")
        let tailStart = start + 5 * 3600
        let samples = (tailStart..<(start + 8 * 3600)).map { sample($0) }
        let tailPeriod = SleepPeriod(startUnix: tailStart, endUnix: source.endUnix,
                                     quietFraction: 0.9, meanHR: 55, wakeEvents: 0)
        let tail = SleepSession.make(samples: samples, period: tailPeriod)
        let saved = [String(start): [start, start + 7200]]
        let retained = SleepSession.retainingUncovered(
            previous: [old], fresh: [tail], coverageStart: tailStart, coverageEnd: source.endUnix,
            samples: samples, overrides: saved
        )
        XCTAssertEqual(retained, [old], "03:00–06:00 must not be re-added after an explicit 02:00 wake edit")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let daily = DailyAnalysis.metrics(from: samples, sex: .male, maxHR: nil,
                                          calendar: calendar, analyzedSleepSessions: retained)
        XCTAssertEqual(daily.reduce(0.0) { $0 + $1.sleepHours }, try XCTUnwrap(old.asleepHours), accuracy: 1e-9)

        let changed = SleepCorrectionStore.saving([start, start + 3600], for: old.sourcePeriod, overrides: saved)
        let updated = SleepSession.retainingUncovered(
            previous: retained, fresh: [tail], coverageStart: tailStart, coverageEnd: source.endUnix,
            samples: samples, overrides: changed
        )
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated.first?.endUnix, start + 3600)
        XCTAssertEqual(updated.first?.sourceEndUnix, source.endUnix + 1)
        XCTAssertNil(updated.first?.asleepHours, "New out-of-archive bounds are unknown, not the stale old total")
        XCTAssertEqual(updated.first?.sourcePeriod.startUnix, old.sourceStartUnix)
        let expiredDay = JournalStore.dayKey(for: Date(timeIntervalSince1970: TimeInterval(start)), calendar: calendar)
        let laterDaily = DailyAnalysis.metrics(from: [sample(start + 3 * 86400)], sex: .male, maxHR: nil,
                                               calendar: calendar, analyzedSleepSessions: updated)
        let correctedDay = try XCTUnwrap(laterDaily.first { $0.dateKey == expiredDay })
        XCTAssertEqual(correctedDay.sleepEndUnix, start + 3600 - 1)
        XCTAssertFalse(correctedDay.sleepDurationReliable ?? true)
        XCTAssertNil(correctedDay.reliableSleepHours, "An edited expired night must not keep stale dashboard/debt hours")
    }

    func testOvercountedStagesCannotBecomeCompleteSleep() {
        let old = knownNight()
        let invalid = SleepStaging(
            segments: old.staging.segments,
            deepMinutes: 60, lightMinutes: 465, remMinutes: 0,
            wakeMinutes: 27, epochs: 984, hrCoverage: 1, reason: nil
        )
        let session = SleepSession(
            version: old.version, sourceStartUnix: old.sourceStartUnix,
            startUnix: old.startUnix, endUnix: old.endUnix,
            staging: invalid, heartRate: old.heartRate,
            movementBouts: old.movementBouts, isEdited: old.isEdited,
            sourceEndUnix: old.sourceEndUnix
        )
        XCTAssertFalse(session.isComplete)
        XCTAssertNil(session.asleepHours)
        XCTAssertNil(session.efficiencyPct)
    }

    func testManualSleepCorrectionPersistsWithoutArchiveCoverage() {
        let old = knownNight()
        let correctedEnd = old.endUnix - 1800
        let result = SleepSession.retainingUncovered(
            previous: [old], fresh: [], coverageStart: nil, coverageEnd: nil,
            overrides: [String(old.sourceStartUnix): [old.startUnix, correctedEnd]]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.endUnix, correctedEnd)
        XCTAssertTrue(result.first?.isEdited == true)
        XCTAssertNil(result.first?.asleepHours,
                     "Without archive samples the corrected window cannot invent sleep stages")
    }

    func testRecoveredCorrectionAppliesWhenDetectorOnsetKeyChanges() {
        let old = knownNight()
        let shiftedSource = old.sourceStartUnix + 300
        let shifted = SleepSession(version: old.version, sourceStartUnix: shiftedSource,
                                   startUnix: old.startUnix, endUnix: old.endUnix,
                                   staging: old.staging, heartRate: old.heartRate,
                                   movementBouts: old.movementBouts, isEdited: true,
                                   sourceEndUnix: old.sourceEndUnix)
        let editedEnd = old.endUnix - 1800
        let overrides = [String(old.sourceStartUnix): [old.startUnix, editedEnd]]
        let retained = SleepSession.retainingUncovered(
            previous: [shifted], fresh: [], coverageStart: old.startUnix,
            coverageEnd: old.endUnix - 1, overrides: overrides
        )
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(retained.first?.endUnix, editedEnd,
                       "A correction saved under the earlier detector onset must still apply")
    }

    func testMissingLegacySourceEndDecodesSafely() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(knownNight())) as? [String: Any])
        object.removeValue(forKey: "sourceEndUnix")
        let decoded = try JSONDecoder().decode(SleepSession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.sourceEndUnix)
        XCTAssertEqual(decoded.sourcePeriod.endUnix, decoded.endUnix - 1)
    }

    func testDetectedNonemptyTailCannotOverwriteVerifiedDailyDuration() {
        let previous = DayMetrics(
            dateKey: "2026-11-12", state: "sleep", restingHR: nil, lnRMSSD: nil,
            hrvWindowSeconds: 0, sleepHours: 7.75, sleepStartUnix: start,
            sleepEndUnix: start + 8 * 3600 - 1, strain: nil, steps: nil,
            sleepDurationReliable: true
        )
        let tail = DayMetrics(
            dateKey: previous.dateKey, state: "sleep", restingHR: nil, lnRMSSD: nil,
            hrvWindowSeconds: 0, sleepHours: 3, sleepStartUnix: start + 5 * 3600,
            sleepEndUnix: previous.sleepEndUnix, strain: nil, steps: nil,
            sleepDurationReliable: true
        )
        XCTAssertFalse(DailyAnalysis.replacesSleep(previous: previous, fresh: tail,
                                                  coverageStart: tail.sleepStartUnix, coverageEnd: tail.sleepEndUnix))
        XCTAssertTrue(DailyAnalysis.replacesSleep(previous: previous, fresh: tail,
                                                 coverageStart: start, coverageEnd: tail.sleepEndUnix))
        XCTAssertTrue(DailyAnalysis.replacesSleep(previous: previous, fresh: tail,
                                                 coverageStart: tail.sleepStartUnix, coverageEnd: tail.sleepEndUnix,
                                                 isEdited: true))
    }

    func testTerminalUpFollowedByUnknownStateTrimsSleepEnd() {
        // Regression for 2026-11-14 archive: sleep(2), sustained up(3),
        // then terminal state 0. The trailing zero must not hide the up run.
        let base = start
        var rows: [V18Sample] = []
        rows.reserveCapacity(8 * 3600)
        for second in 0..<(8 * 3600) {
            let unix = base + second
            let state: Int = second < 6 * 3600 ? 2 : (second < 7 * 3600 ? 3 : 0)
            let isQuiet = second < 6 * 3600
            rows.append(V18Sample(
                header: BandRecordHeader(version: 18, flags: 0x80, recordIndex: UInt32(unix), unix: UInt32(unix), subsecQ15: 0),
                heartRate: isQuiet ? 55 : 90, rrIntervalsMS: [],
                dynamicAccelG: isQuiet ? 0.01 : 0.12,
                gravityXG: 0, gravityYG: 0, gravityZG: 1,
                stepCounter: nil, stepCadence: nil, activityClass: 0,
                skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
                sleepStateByte: nil, sleepState: state, cardiacFlags: nil, hrQualityFlags: nil,
                spo2CandidateRaw: nil, spo2CandidatePct: nil, spo2CandidateKind: .absent,
                signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
            ))
        }
        let periods = SleepDetect.detect(rows, gapToleranceS: 7200)
        XCTAssertTrue(periods.contains { $0.endUnix <= base + 6 * 3600 },
                      "Terminal state 0 must not conceal sustained up(3) wake")
    }

    func testLegacySleepReportRejectsNonfiniteNeedAndInvalidPeriods() {
        for need in [0.0, -1.0, .infinity, .nan] {
            XCTAssertNil(SleepReport.analyze(samples: [], periods: [period(3600)],
                                            needHours: need, nights: [], sleepBaseline: nil))
        }
        XCTAssertNil(SleepReport.analyze(samples: [], periods: [],
                                        needHours: 8, nights: [], sleepBaseline: nil))
    }

    func testEqualDistanceSleepCorrectionAliasesAreDeterministic() {
        let night = SleepPeriod(startUnix: start, endUnix: start + 8 * 3600 - 1,
                                quietFraction: 0.8, meanHR: 55, wakeEvents: 0)
        let earlier = [start + 60, start + 7 * 3600]
        let later = [start + 120, start + 7 * 3600 + 60]
        let a = [String(start - 60): later, String(start + 60): earlier]
        let b = [String(start + 60): earlier, String(start - 60): later]
        XCTAssertEqual(SleepCorrectionStore.times(for: night, overrides: a), earlier)
        XCTAssertEqual(SleepCorrectionStore.times(for: night, overrides: b), earlier)
    }

    func testZeroOrNonfiniteNeedRefusesScore() {
        for need in [0.0, -1.0, .infinity, .nan] {
            XCTAssertNil(SleepReport.analyze(samples: [], session: knownNight(), needHours: need, nights: [], sleepBaseline: nil))
        }
    }

    func testRestDiagnosticsShowMeasuredCounts() {
        let short = (0..<10).map { sample(start + $0) }
        XCTAssertEqual(Hrv.restingQualityReason(short),
                       "Longest continuous quiet run: 10s; need 60s")
        let noBeats = (0..<60).map { sample(start + $0) }
        XCTAssertEqual(Hrv.restingQualityReason(noBeats),
                       "Quiet run found; R-R: 0 beats in 0s, but insufficient clean consecutive pairs")
    }
}

extension SleepSessionTests {
    func testDaytimeLegacyCandidateCannotReplaceRecordedOvernightSleep() {
        let night = knownNight()
        // Use the source timezone so traveling does not reclassify a saved nap.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let noon = Int(utc.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 13, minute: 9))!.timeIntervalSince1970)
        let candidate = SleepSession(version: 4, sourceStartUnix: noon, startUnix: noon,
            endUnix: noon + 7200, staging: night.staging, heartRate: [], movementBouts: 0,
            isEdited: false, timezoneIdentifier: "UTC")
        XCTAssertEqual(candidate.classification, .pendingCandidate)
        var summary = CaptureSummary.empty
        summary.sleepSessions = [candidate]
        XCTAssertNil(summary.latestSleepSession)
        let nap = SleepSession(version: SleepSession.algorithmVersion, sourceStartUnix: noon,
            startUnix: noon, endUnix: noon + 7200, staging: night.staging, heartRate: [], movementBouts: 0,
            isEdited: false, bandSleepConfirmed: true, timezoneIdentifier: "UTC")
        XCTAssertEqual(nap.classification, .nap)
        summary.sleepSessions = [nap]
        XCTAssertNil(summary.latestSleepSession, "Confirmed naps cannot become the night's Sleep/Recovery source")
    }
}

extension SleepSessionTests {
    func testBackgroundQuietTailCannotDriftSavedWakeBoundary() {
        let old = knownNight()
        let unedited = SleepSession(version: old.version, sourceStartUnix: old.sourceStartUnix,
            startUnix: old.startUnix, endUnix: old.endUnix, staging: old.staging,
            heartRate: [], movementBouts: 0, isEdited: false, sourceEndUnix: old.endUnix)
        let drifted = SleepSession(version: old.version, sourceStartUnix: old.sourceStartUnix,
            startUnix: old.startUnix, endUnix: old.endUnix + 3600, staging: old.staging,
            heartRate: [], movementBouts: 0, isEdited: false, sourceEndUnix: old.endUnix + 3600)
        let retained = SleepSession.retainingUncovered(previous: [unedited], fresh: [drifted],
            coverageStart: old.startUnix, coverageEnd: drifted.endUnix, samples: [])
        XCTAssertEqual(retained, [unedited])
    }
}

extension SleepSessionTests {
    func testEmptyReanalysisCannotEraseCompleteCachedNightDespiteArchiveEndpoints() {
        let current = knownNight()
        let stored = SleepSession(version: 1, sourceStartUnix: current.sourceStartUnix,
            startUnix: current.startUnix, endUnix: current.endUnix, staging: current.staging,
            heartRate: [], movementBouts: current.movementBouts, isEdited: false,
            sourceEndUnix: current.endUnix)
        // Two distant packets span the night but supply no usable overnight
        // evidence. A new recipe cannot treat these endpoints as full coverage.
        let rows = [sample(stored.startUnix - 10), sample(stored.endUnix + 10)]
        let retained = SleepSession.retainingUncovered(previous: [stored], fresh: [],
            coverageStart: rows.first?.unix, coverageEnd: rows.last?.unix, samples: rows)
        XCTAssertEqual(retained, [stored])
    }
}


extension SleepSessionTests {
    func testDiagnosticExportDoesNotAssignStageAcrossUnclassifiedGap() throws {
        let staging = SleepStaging(
            segments: [
                SleepStageSegment(startUnix: start, endUnix: start + 10, stage: .wake),
                SleepStageSegment(startUnix: start + 20, endUnix: start + 30, stage: .light)
            ],
            deepMinutes: 0, lightMinutes: 0, remMinutes: 0, wakeMinutes: 0,
            epochs: 0, hrCoverage: 1, reason: nil
        )
        let session = SleepSession(version: SleepSession.algorithmVersion,
            sourceStartUnix: start, startUnix: start, endUnix: start + 30,
            staging: staging, heartRate: [], movementBouts: 0, isEdited: true,
            sourceEndUnix: start + 30)
        let csv = try SleepDiagnostics.csv(
            samples: [sample(start + 9), sample(start + 10), sample(start + 15),
                      sample(start + 20), sample(start + 29)], session: session)
        let lines = csv.split(separator: "\n")
        let header = lines[0].split(separator: ",", omittingEmptySubsequences: false)
        let stageIndex = try XCTUnwrap(header.firstIndex(of: "estimated_stage"))
        let stages = lines.dropFirst().map {
            String($0.split(separator: ",", omittingEmptySubsequences: false)[stageIndex])
        }
        XCTAssertEqual(stages, ["wake", "", "", "light", "light"])
    }
}


extension SleepSessionTests {
    func testDiagnosticLookbackNearUnixEpochKeepsAvailableRows() throws {
        let night = knownNight()
        let nearEpoch = SleepSession(
            version: night.version, sourceStartUnix: 10,
            startUnix: 10, endUnix: 100,
            staging: night.staging, heartRate: [], movementBouts: 0,
            isEdited: false, sourceEndUnix: 100)
        let csv = try SleepDiagnostics.csv(
            samples: [sample(5), sample(20), sample(100)],
            session: nearEpoch, preSleepSeconds: 1800)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 3, "Only observed rows before end are exported")
        XCTAssertEqual(lines.dropFirst().map { Int($0.split(separator: ",")[3])! },
                       [5, 20])
    }
}


extension SleepSessionTests {
    func testDiagnosticRejectsInvalidEditedSleepWindow() {
        let night = knownNight()
        let invalid = SleepSession(
            version: night.version, sourceStartUnix: night.sourceStartUnix,
            startUnix: night.endUnix, endUnix: night.startUnix,
            staging: night.staging, heartRate: [], movementBouts: 0,
            isEdited: true, sourceEndUnix: night.sourceEndUnix)
        XCTAssertThrowsError(try SleepDiagnostics.csv(
            samples: [sample(night.startUnix)], session: invalid)) { error in
            guard case SleepDiagnostics.ExportError.noNight = error else {
                return XCTFail("Invalid window should report noNight, got \(error)")
            }
        }
    }
    func testLateQuietHistoryCannotExtendSavedWakeWithoutConfirmedSleepState() throws {
        // A new build must not extend the canonical wake merely because
        // late on-wrist quiet samples arrived with no confirmed sleep state.
        let oldSeconds = 7 * 3600
        let lateSeconds = 26 * 60
        let rows = (0..<(oldSeconds + lateSeconds)).map { sample(start + $0) }
        let saved = SleepSession.make(samples: Array(rows.prefix(oldSeconds)),
                                      period: period(oldSeconds))
        let replacement = SleepSession.make(samples: rows,
                                            period: period(oldSeconds + lateSeconds))
        XCTAssertTrue(saved.isComplete)
        XCTAssertTrue(replacement.isComplete)
        let merged = SleepSession.retainingUncovered(
            previous: [saved], fresh: [replacement],
            coverageStart: start, coverageEnd: start + rows.count - 1, samples: rows)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].endUnix, saved.endUnix,
                       "Unknown-state quiet tail must not move a saved wake boundary")
    }

}
