import Foundation

// MARK: - Inputs

enum SleepIntent: String, Codable, CaseIterable, Identifiable {
    case hard
    case easy
    case rest

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Planning labels have no validated effect on sleep duration.
    var extraHours: Double { 0 }
}

/// One recorded night. `dateKey` is the wake-up morning (yyyy-MM-dd) so
/// lexicographic sort == chronological sort. Built by `AppStore.recordedNights`
/// from the captured per-day metrics.
struct RecordedNight: Equatable {
    let dateKey: String
    let neededHours: Double
    let actualHours: Double
    var efficiency: Double? = nil
}

// MARK: - Output

struct SleepRecommendation: Equatable {
    let baselineHours: Double
    let appliedDebtHours: Double
    let additionalHours: Double
    let measuredEfficiency: Double?
    let needHours: Double
    let timeInBedHours: Double
    /// Minutes since midnight, always 0..<1440 (wraps past midnight).
    let bedtimeMinutes: Int
    let wakeMinutes: Int
    /// nil == debt unknown (no recorded nights yet).
    let debtHours: Double?
}

// MARK: - Coach math (our own published-science coach, Kitamura 2016 debt model)

enum SleepCoach {
    static let defaultBaselineHours = 8.0
    static let minimumHistoryNights = 3
    /// At most 2 h of debt joins one night's need.
    static let debtCapHours = 2.0
    static let debtWindowNights = 14

    /// Running balance of (need − actual), floored at 0, over the last
    /// 14 nights. Three distinct nights are required before applying an estimate.
    static func sleepDebt(nights: [RecordedNight]) -> Double? {
        let valid = nights.filter {
            (5...12).contains($0.neededHours) && (0..<24).contains($0.actualHours)
        }
        let distinct = Dictionary(valid.map { ($0.dateKey, $0) }, uniquingKeysWith: { _, latest in latest })
        let recent = distinct.values.sorted { $0.dateKey < $1.dateKey }.suffix(debtWindowNights)
        guard recent.count >= minimumHistoryNights else { return nil }
        var balance = 0.0
        for night in recent {
            balance = max(0.0, balance + (night.neededHours - night.actualHours))
        }
        return balance
    }

    static func recentNights(_ nights: [RecordedNight], ending now: Date, calendar: Calendar = .current) -> [RecordedNight] {
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: 1 - debtWindowNights, to: today) ?? today
        let lower = JournalStore.dayKey(for: first, calendar: calendar)
        let upper = JournalStore.dayKey(for: today, calendar: calendar)
        return nights.filter { (lower...upper).contains($0.dateKey) }
    }

    static func efficiency(nights: [RecordedNight]) -> Double? {
        let distinct = Dictionary(nights.map { ($0.dateKey, $0) }, uniquingKeysWith: { _, latest in latest })
        let values = distinct.values.compactMap(\.efficiency).filter { $0 > 0 && $0 <= 1 }
        guard values.count >= minimumHistoryNights else { return nil }
        return Stats.median(values)
    }

    static func matchesSavedCorrection(
        start: Int, end: Int, corrections: [String: [Int]]
    ) -> Bool {
        guard let times = SleepCorrectionStore.times(
            for: SleepPeriod(startUnix: start, endUnix: end, quietFraction: 0, meanHR: 0, wakeEvents: 0),
            overrides: corrections
        ) else { return true }
        return times[0] == start && times[1] == end + 1
    }

    static func recommendation(
        baseNeedHours: Double,
        intent: SleepIntent,
        debtHours: Double?,
        wakeMinutes: Int,
        measuredEfficiency: Double? = nil,
        scheduledWake: Date? = nil,
        calendar: Calendar = .current
    ) -> SleepRecommendation {
        let baseline = (5...12).contains(baseNeedHours) ? baseNeedHours : defaultBaselineHours
        let debt = debtHours.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let appliedDebt = min(debt ?? 0, debtCapHours)
        let additional = intent.extraHours
        let need = baseline + additional + appliedDebt
        let efficiency = measuredEfficiency.flatMap { $0 > 0 && $0 <= 1 ? $0 : nil }
        let timeInBed = need / (efficiency ?? 1)
        let wake = ((wakeMinutes % 1440) + 1440) % 1440
        // An overnight plan cannot fit a time-in-bed estimate above 24 hours.
        let usableEfficiency = timeInBed <= 24 ? efficiency : nil
        let plannedHours = usableEfficiency == nil ? need : timeInBed
        let bedMinutes = Int((plannedHours * 60.0).rounded())
        let bedtime = ((wake - bedMinutes) % 1440 + 1440) % 1440
        return SleepRecommendation(
            baselineHours: baseline,
            appliedDebtHours: appliedDebt,
            additionalHours: additional,
            measuredEfficiency: usableEfficiency,
            needHours: need,
            timeInBedHours: plannedHours,
            bedtimeMinutes: bedtime,
            wakeMinutes: wake,
            debtHours: debt
        )
    }
}

// MARK: - Formatting helpers

enum CoachFormat {
    static func minutesSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Minutes since midnight → "HH:mm", wrapped.
    static func clock(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    static func localClock(_ minutes: Int) -> String {
        let wrapped = ((minutes % 1440) + 1440) % 1440
        let utc = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = utc
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: Double(wrapped * 60)))
    }

    /// Hours → "h:mm" (rounded to the minute).
    static func duration(_ hours: Double) -> String {
        let m = Int((hours * 60.0).rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}