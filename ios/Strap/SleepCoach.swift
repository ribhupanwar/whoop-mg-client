import Foundation

// MARK: - Inputs

enum SleepIntent: String, Codable, CaseIterable, Identifiable {
    case hard
    case easy
    case rest

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Extra sleep need for tomorrow's intent (hours).
    var extraHours: Double {
        switch self {
        case .hard: return 0.5
        case .easy: return 0.0
        case .rest: return 0.25
        }
    }
}

/// One recorded night. `dateKey` is the wake-up morning (yyyy-MM-dd) so
/// lexicographic sort == chronological sort. Built by `AppStore.recordedNights`
/// from the captured per-day metrics.
struct RecordedNight: Equatable {
    let dateKey: String
    let neededHours: Double
    let actualHours: Double
}

// MARK: - Output

struct SleepRecommendation: Equatable {
    let needHours: Double
    let timeInBedHours: Double
    /// Minutes since midnight, always 0..<1440 (wraps past midnight).
    let bedtimeMinutes: Int
    /// nil == debt unknown (no recorded nights yet).
    let debtHours: Double?
}

// MARK: - Coach math (our own published-science coach, Kitamura 2016 debt model)

enum SleepCoach {
    /// Stated assumptions, not sensor readings: 90% sleep efficiency and
    /// 15 min assumed latency. This band cannot measure either.
    static let efficiency = 0.90
    static let latencyHours = 0.25
    /// At most 2 h of debt joins one night's need.
    static let debtCapHours = 2.0
    static let debtWindowNights = 14

    /// Running balance of (need − actual), floored at 0, over the last
    /// 14 recorded nights. Returns nil when no nights are recorded.
    static func sleepDebt(nights: [RecordedNight]) -> Double? {
        guard !nights.isEmpty else { return nil }
        let recent = nights.sorted { $0.dateKey < $1.dateKey }.suffix(debtWindowNights)
        var balance = 0.0
        for night in recent {
            balance = max(0.0, balance + (night.neededHours - night.actualHours))
        }
        return balance
    }

    /// need = base + extra(intent) + min(debt, 2.0)
    /// timeInBed = need / 0.90 + 0.25
    /// bedtime = wake − timeInBed (wrapped into 0..<1440)
    static func recommendation(
        baseNeedHours: Double,
        intent: SleepIntent,
        debtHours: Double?,
        wakeMinutes: Int
    ) -> SleepRecommendation {
        let debt = debtHours ?? 0.0
        let need = baseNeedHours + intent.extraHours + min(debt, debtCapHours)
        let timeInBed = need / efficiency + latencyHours
        let wake = ((wakeMinutes % 1440) + 1440) % 1440
        let bedMinutes = Int((timeInBed * 60.0).rounded())
        let bedtime = ((wake - bedMinutes) % 1440 + 1440) % 1440
        return SleepRecommendation(
            needHours: need,
            timeInBedHours: timeInBed,
            bedtimeMinutes: bedtime,
            debtHours: debtHours
        )
    }
}

// MARK: - Formatting helpers

enum CoachFormat {
    /// Minutes since midnight → "HH:mm", wrapped.
    static func clock(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// Hours → "h:mm" (rounded to the minute).
    static func duration(_ hours: Double) -> String {
        let m = Int((hours * 60.0).rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}