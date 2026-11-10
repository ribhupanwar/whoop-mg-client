import Foundation

/// Labelled sample data for design-preview mode ONLY. None of these values
/// are measurements; the banner makes that explicit wherever they appear.
/// Live mode never reads from this file.
enum SampleData {
    // Home trio + insight
    static let sleepRingPercent = 85
    static let recoveryRingPercent = 75
    static let strain = 2.1
    static let batteryPercent = 99

    // Dashboard metrics
    static let hrvMS = 52.0
    static let hrvCompare = 49
    static let rhr = 57.0
    static let rhrCompare = 56
    static let steps = 8430
    static let stepsCompare = 8929
    static let zones13 = "1:02"
    static let zones13Compare = "0:46"
    static let zones45 = "0:08"
    static let zones45Compare = "0:20"
    static let calories = 1169
    static let caloriesCompare = 2523

    // Health detail
    static let hrNow = 81
    static let hrRangeLow = 48
    static let hrRangeHigh = 162
    static let hrSeries: [Double] = [
        74, 68, 78, 76, 78, 80, 83, 74, 82, 74, 75, 76, 70, 74, 74, 76,
        76, 78, 77, 75, 75, 82, 77, 71, 76, 74, 77, 74, 66, 64, 70, 70,
        72, 74, 62, 72, 72, 72, 66, 61, 74, 72, 62, 72, 71, 74, 74, 70, 77
    ]

    // Stress
    static let stressGauge = 2.1
    static let stressHome = 0.7
    static let stressMiniSeries: [Double] = [
        0.4, 0.5, 0.35, 0.55, 0.4, 0.45, 0.3, 0.5, 0.4, 0.55, 0.45, 0.5
    ]
    static let stressDaySeries: [Double] = [
        0.4, 0.7, 0.3, 0.6, 0.2, 0.5, 0.1, 0.5, 0.3, 0.6, 2.2, 2.8, 2.4,
        2.9, 1.9, 2.5, 1.6, 2.3, 1.4, 1.8, 1.1, 1.6, 0.9, 1.4, 1.0, 1.2
    ]

    // Activities / tonight / plan
    static let lastNightSleep = "6:24"
    static let lastNightTimes = "00:26 – 07:33"
    static let bedtime = "22:28"
    static let latestAlarm = "07:45"
    static let planActualSleep = "7:22"

    // Sleep analysis
    static let sleepPerformance = 66
    static let hoursVsNeeded = 62
    static let sleepConsistency = 55
    static let sleepEfficiency = 84
    static let highSleepStress = 0
    static let sleepHours = "5:49"
    static let asleepMinutes = 349.0   // 5:49
    static let awakeMinutes = 67.0     // 1:07 → 84% efficiency of 6:56 in bed
    static let wakeEvents = 13
    static let weeklySleepPerformance: [Double] = [80, 80, 84, 65, 84, 82, 66]
    // Weekly trends (Wed–Tue), labelled sample. Hours are decimal hours.
    static let weekDays = ["Wed", "Thu", "Fri", "Sat", "Sun", "Mon", "Tue"]
    static let weeklyHoursSleep: [Double] = [6.28, 6.33, 7.03, 5.40, 6.65, 6.82, 5.82]
    static let weeklyHoursNeeded: [Double] = [8.73, 9.47, 10.05, 10.22, 9.70, 9.57, 9.33]
    static let weeklyHoursVsNeeded: [Double] = [72, 67, 70, 53, 69, 71, 62]
    static let weeklyConsistency: [Double] = [70, 79, 87, 81, 87, 83, 55]
    static let weeklyEfficiency: [Double] = [92, 94, 93, 88, 90, 93, 84]
    static let weeklyDebtMinutes: [Double] = [94, 94, 90, 128, 91, 82, 105]
    // Per night [high, medium, low] share-heights (sum ≈ hours/8h × 100).
    static let weeklyStressSegments: [[Double]] = [
        [0, 0, 79], [0, 4, 75], [0, 7, 81], [0, 10, 58],
        [0, 4, 79], [3, 14, 68], [0, 4, 69]
    ]
    // Bed→wake spans as minutes since 21:00 (axis 0…780 = 9 PM…10 AM).
    static let weeklyBedWake: [(Double, Double)] = [
        (120, 531), (144, 548), (95, 551), (189, 561),
        (95, 541), (136, 579), (268, 682)
    ]
    // Last-night detail panels.
    static let needBase = "8:00"
    static let needDebt = "+1:20"
    static let needTomorrow = "+0:00"
    static let needTotal = "9:20"
    static let sleepStressSeries: [Double] = [
        1.2, 1.5, 0.9, 0.6, 0.8, 0.4, 2.0, 0.7, 0.4, 0.6, 0.3, 0.5,
        0.3, 0.4, 0.3, 0.5, 0.3, 0.7, 1.0, 0.5, 0.3, 0.4, 0.3, 0.9, 0.5, 0.3, 0.4
    ]
    static let sleepHRSeries: [Double] = [
        58, 56, 54, 52, 51, 50, 52, 55, 53, 51, 49, 48, 50, 53, 56, 54,
        52, 51, 53, 57, 60, 58, 55, 54, 56, 59, 62, 60, 58, 61, 64, 63,
        66, 64, 62, 65, 68, 66, 64, 67, 70, 68, 66, 69, 72, 70, 68, 71
    ]

    // Health hub
    static let baselineDaysDone = 3
    static let baselineDaysTarget = 7
    static let highStressToday = "0:00"

    // Sleep coach demo: two nights at 7.5 h against an 8 h need → 1.0 h debt.
    // With wake 06:30 and easy intent: need 9.0, in bed 10:15, bedtime 20:15.
    static let nights: [RecordedNight] = [
        RecordedNight(dateKey: "2026-11-07", neededHours: 8.0, actualHours: 7.5),
        RecordedNight(dateKey: "2026-11-08", neededHours: 8.0, actualHours: 7.5)
    ]
    static let demoWakeMinutes = 6 * 60 + 30
}