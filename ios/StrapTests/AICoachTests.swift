import XCTest
@testable import Strap

final class AICoachTests: XCTestCase {
    func testSnapshotBuilderIncludesTodayYesterdayAndBaseline() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let todayKey = JournalStore.dayKey(for: now, calendar: calendar)
        
        let yesterday = DayMetrics(
            dateKey: "2026-11-21",
            state: "sleep",
            restingHR: 56.0,
            lnRMSSD: log(48.0),
            hrvWindowSeconds: 300,
            sleepHours: 6.8,
            sleepStartUnix: 1795000000,
            sleepEndUnix: 1795024480,
            strain: 12.4,
            steps: 8500,
            sleepDurationReliable: true,
            respiratoryRate: 15.5,
            restingHRWindowSeconds: 300,
            respiratoryWindows: 1,
            skinTemperatureC: 34.2,
            skinTemperatureSeconds: 600,
            skinTemperatureSource: NightTemperature.source,
            oxygenCandidatePct: 97
        )
        
        let priorDays = (14...20).map { dayIndex in
            DayMetrics(
                dateKey: "2026-11-\(dayIndex)",
                state: "sleep",
                restingHR: 58.0,
                lnRMSSD: log(45.0),
                hrvWindowSeconds: 300,
                sleepHours: 7.0,
                sleepStartUnix: 1794900000,
                sleepEndUnix: 1794925200,
                strain: 10.0,
                steps: 7000,
                sleepDurationReliable: true,
                respiratoryRate: 15.0,
                restingHRWindowSeconds: 300,
                respiratoryWindows: 1,
                skinTemperatureC: 34.0,
                skinTemperatureSeconds: 600,
                skinTemperatureSource: NightTemperature.source,
                oxygenCandidatePct: 96
            )
        }
        
        let allDays = priorDays + [yesterday]
        let night = RecordedNight(dateKey: todayKey, neededHours: 8.0, actualHours: 7.2, efficiency: 0.88)
        let run = ActivitySession(
            startUnix: 1795030000,
            endUnix: 1795031920,
            kind: "run",
            steps: 4500,
            meanHR: 152.0,
            walkTicks: 100,
            runTicks: 1800,
            maxHR: 168,
            strain: 11.2
        )
        
        let snapshot = CoachBiometricSnapshotBuilder.build(
            days: allDays,
            recoveryScore: 68.0,
            dayStrain: 4.2,
            lastCaptureHRV: 45.0,
            measuredRHR: 58.0,
            recordedNights: [night],
            detectedActivities: [run],
            manualActivities: []
        )
        
        XCTAssertTrue(snapshot.contains("TODAY (\(todayKey))"))
        XCTAssertTrue(snapshot.contains("Recovery: 68%"))
        XCTAssertTrue(snapshot.contains("Live Day Strain: 4.2 / 21.0"))
        XCTAssertTrue(snapshot.contains("Current SWS HRV: 45 ms"))
        XCTAssertTrue(snapshot.contains("Current Resting HR: 58 bpm"))
        XCTAssertTrue(snapshot.contains("Last Night's Sleep: 7.2h actual vs 8.0h needed"))
        XCTAssertTrue(snapshot.contains("YESTERDAY (2026-11-21)"))
        XCTAssertTrue(snapshot.contains("Final Day Strain: 12.4"))
        XCTAssertTrue(snapshot.contains("Sleep Duration: 6.8 hrs"))
        XCTAssertTrue(snapshot.contains("7-DAY BASELINE TRENDS"))
        XCTAssertTrue(snapshot.contains("Qualifying Nights: 7 of 7"))
        XCTAssertTrue(snapshot.contains("Run: 32 min (Strain 11.2, Avg HR 152 bpm)"))
    }

    func testSnapshotBuilderWithEmptyDataDoesNotCrashOrFabricate() {
        let snapshot = CoachBiometricSnapshotBuilder.build(
            days: [],
            recoveryScore: nil,
            dayStrain: 0.0,
            lastCaptureHRV: nil,
            measuredRHR: nil,
            recordedNights: [],
            detectedActivities: [],
            manualActivities: []
        )
        
        XCTAssertTrue(snapshot.contains("Recovery: Pending"))
        XCTAssertTrue(snapshot.contains("Live Day Strain: 0.0 / 21.0"))
        XCTAssertTrue(snapshot.contains("Current SWS HRV: Unavailable"))
        XCTAssertTrue(snapshot.contains("Current Resting HR: Unavailable"))
        XCTAssertTrue(snapshot.contains("None recorded in recent window."))
    }
}
