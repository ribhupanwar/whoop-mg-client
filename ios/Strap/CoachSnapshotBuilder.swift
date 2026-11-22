import Foundation

/// Builds a structured, multi-day grounded biometric snapshot for STRAP Coach.
/// Exposes today's in-progress data, yesterday's finalized baseline, 7-day norms,
/// recent workouts, and Health Monitor status without fabricating numbers.
struct CoachBiometricSnapshotBuilder {
    static func build(
        days: [DayMetrics],
        recoveryScore: Double?,
        dayStrain: Double?,
        lastCaptureHRV: Double?,
        measuredRHR: Double?,
        recordedNights: [RecordedNight],
        detectedActivities: [ActivitySession],
        manualActivities: [ManualActivity] = [],
        healthMonitor: HealthMonitorSnapshot? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let todayKey = JournalStore.dayKey(for: now, calendar: calendar)
        let yesterdayKey = calendar.date(byAdding: .day, value: -1, to: now)
            .map { JournalStore.dayKey(for: $0, calendar: calendar) }
        let historyStartKey = calendar.date(byAdding: .day, value: -7, to: now)
            .map { JournalStore.dayKey(for: $0, calendar: calendar) } ?? todayKey
        let sortedDays = days.sorted { $0.dateKey < $1.dateKey }

        var sections: [String] = []

        // 1. TODAY's In-Progress Metrics
        let recText = recoveryScore.map { "\(Int($0.rounded()))%" } ?? "Pending"
        let strainText = dayStrain.map { String(format: "%.1f / 21.0", $0) } ?? "Unavailable"
        let hrvText = lastCaptureHRV.map { String(format: "%.0f ms", $0) } ?? "Unavailable"
        let rhrText = measuredRHR.map { String(format: "%.0f bpm", $0) } ?? "Unavailable"

        var todayLines = [
            "• TODAY (\(todayKey)):",
            "  - Recovery: \(recText)",
            "  - Live Day Strain: \(strainText)",
            "  - Latest recorded HRV: \(hrvText)",
            "  - Current Resting HR: \(rhrText)"
        ]
        if let lastNight = recordedNights.last(where: { $0.dateKey == todayKey }) {
            todayLines.append("  - Last Night's Sleep: \(String(format: "%.1f", lastNight.actualHours))h actual vs \(String(format: "%.1f", lastNight.neededHours))h needed")
        }
        sections.append(todayLines.joined(separator: "\n"))

        // 2. YESTERDAY's Finalized Metrics
        if let yesterday = sortedDays.last(where: { $0.dateKey == yesterdayKey }) {
            var yLines = ["• YESTERDAY (\(yesterday.dateKey)):"]
            if let yStrain = yesterday.strain {
                yLines.append("  - Final Day Strain: \(String(format: "%.1f", yStrain))")
            }
            yLines.append("  - Sleep Duration: \(String(format: "%.1f", yesterday.sleepHours)) hrs")
            if let yRHR = yesterday.restingHR {
                yLines.append("  - Resting HR: \(String(format: "%.0f bpm", yRHR))")
            }
            if let yLn = yesterday.lnRMSSD {
                yLines.append("  - RMSSD HRV: \(String(format: "%.0f ms", exp(yLn)))")
            }
            sections.append(yLines.joined(separator: "\n"))
        }

        // 3. 7-DAY BASELINE TRENDS
        let last7 = sortedDays.filter { $0.dateKey >= historyStartKey && $0.dateKey < todayKey }
        if !last7.isEmpty {
            let validHRVs = last7.compactMap { $0.lnRMSSD.map { exp($0) } }
            let validRHRs = last7.compactMap { $0.restingHR }
            let validStrains = last7.compactMap { $0.strain }
    
            var trendLines = [
                "• 7-DAY BASELINE TRENDS:",
                "  - Recorded days: \(last7.count) of 7"
            ]
            if let minH = validHRVs.min(), let maxH = validHRVs.max() {
                trendLines.append("  - Typical HRV Range: \(Int(round(minH)))–\(Int(round(maxH))) ms")
            }
            if let minR = validRHRs.min(), let maxR = validRHRs.max() {
                trendLines.append("  - Typical RHR Range: \(Int(round(minR)))–\(Int(round(maxR))) bpm")
            }
            if !validStrains.isEmpty {
                let avgStrain = validStrains.reduce(0.0, +) / Double(validStrains.count)
                trendLines.append("  - Average Day Strain: \(String(format: "%.1f", avgStrain))")
            }
            sections.append(trendLines.joined(separator: "\n"))
        }

        // 4. RECENT WORKOUTS
        var workoutLines = ["• RECENT WORKOUTS:"]
        var renderedWorkouts = 0
        for w in detectedActivities.sorted(by: { $0.startUnix > $1.startUnix }).prefix(4) {
            let dur = Int(round(w.minutes))
            let s = w.strain.map { String(format: "Strain %.1f", $0) } ?? "No strain"
            let hr = w.meanHR.map { String(format: "Avg HR %.0f bpm", $0) } ?? ""
            let details = [s, hr].filter { !$0.isEmpty }.joined(separator: ", ")
            workoutLines.append("  - \(w.kind.capitalized): \(dur) min (\(details))")
            renderedWorkouts += 1
        }
        for m in manualActivities.prefix(max(0, 4 - renderedWorkouts)) {
            let label = m.name.isEmpty ? m.kind.label : m.name
            workoutLines.append("  - \(label): \(m.minutes) min (Manual log)")
            renderedWorkouts += 1
        }
        if renderedWorkouts == 0 {
            workoutLines.append("  - None recorded in recent window.")
        }
        sections.append(workoutLines.joined(separator: "\n"))

        // 5. HEALTH MONITOR VITALS
        if let hm = healthMonitor {
            let vLines = [
                "• HEALTH MONITOR CORRIDORS:",
                "  - Resting HR: \(hm[.rhr].statusText)",
                "  - Heart Rate Variability: \(hm[.hrv].statusText)",
                "  - Respiratory Rate: \(hm[.respiration].statusText)",
                "  - Skin Temperature: \(hm[.temperature].statusText)",
                "  - Blood Oxygen: \(hm[.oxygen].statusText)"
            ]
            sections.append(vLines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }
}
