import XCTest
@testable import Strap

final class SleepSessionTests: XCTestCase {
    private let start = 1_800_000_000

    private func sample(_ unix: Int) -> V18Sample {
        V18Sample(
            header: BandRecordHeader(version: 18, flags: 0x80, recordIndex: UInt32(unix), unix: UInt32(unix), subsecQ15: 0),
            heartRate: 55, rrIntervalsMS: [], dynamicAccelG: 0.01,
            gravityXG: 0, gravityYG: 0, gravityZG: 1,
            stepCounter: nil, stepCadence: nil, activityClass: 0,
            skinTempC: nil, tempAux1C: nil, tempAux2C: nil,
            sleepStateByte: nil, sleepState: nil, cardiacFlags: nil, hrQualityFlags: nil,
            spo2CandidateRaw: nil, spo2CandidatePct: nil, spo2CandidateKind: .absent,
            signalQualityLogVariance: nil, psnrB: nil, psnrA: nil
        )
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

    func testEditedEightHourTwelveMinuteWindowKeepsObservedSleepSeparateFromUnknown() {
        let observedSeconds = 211 * 60 - 10
        let editedEnd = start + 492 * 60
        let samples = (0..<observedSeconds).map { sample(start + $0) }
        let session = SleepSession.make(
            samples: samples, period: period(492 * 60),
            correctedTimes: [start, editedEnd]
        )

        XCTAssertTrue(session.isEdited)
        XCTAssertEqual(session.startUnix, start)
        XCTAssertEqual(session.endUnix, editedEnd)
        XCTAssertEqual(session.timeInBedHours, 8.2, accuracy: 1e-9)
        XCTAssertEqual(session.staging.hrCoverage, Double(observedSeconds) / Double(492 * 60), accuracy: 1e-12)
        XCTAssertFalse(session.isComplete)
        XCTAssertNil(session.asleepHours)
        XCTAssertEqual(session.staging.totalMinutes * 60, Double(observedSeconds), accuracy: 1e-9)
        XCTAssertEqual(session.unclassifiedHours, Double(492 * 60 - observedSeconds) / 3600.0, accuracy: 1e-9)
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
        ), [tail], "Full retained coverage allows authoritative reanalysis")
        let edited = SleepSession.make(samples: samples, period: tailPeriod,
                                       correctedTimes: [tailStart, old.endUnix])
        XCTAssertEqual(SleepSession.retainingUncovered(
            previous: [old], fresh: [edited], coverageStart: tailStart, coverageEnd: old.endUnix - 1
        ), [edited], "An intentional new window must not be replaced by an old saved window")
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

    func testZeroOrNonfiniteNeedRefusesScore() {
        for need in [0.0, -1.0, .infinity, .nan] {
            XCTAssertNil(SleepReport.analyze(samples: [], session: knownNight(), needHours: need, nights: [], sleepBaseline: nil))
        }
    }
}
