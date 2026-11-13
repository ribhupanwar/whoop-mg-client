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
                            heartRate: [], movementBouts: 29, isEdited: true)
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

    func testZeroOrNonfiniteNeedRefusesScore() {
        for need in [0.0, -1.0, .infinity, .nan] {
            XCTAssertNil(SleepReport.analyze(samples: [], session: knownNight(), needHours: need, nights: [], sleepBaseline: nil))
        }
    }
}
