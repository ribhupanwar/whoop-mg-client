import Foundation

// MARK: - Settings

enum Sex: String, Codable, CaseIterable, Identifiable {
    case female
    case male
    case unspecified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .unspecified: return "Not set"
        }
    }
}

/// One customisable row of the shared Home/Dashboard stack. Raw values are the
/// persisted keys: renaming a case without keeping its string silently resets
/// that row's saved position and visibility.
enum DashboardRow: String, Codable, CaseIterable, Identifiable {
    case hrv
    case restingHR
    case steps
    case zonesLow
    case zonesHigh
    case vo2Max
    case calories
    case stress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hrv: return "Heart rate variability"
        case .restingHR: return "Resting heart rate"
        case .steps: return "Steps"
        case .zonesLow: return "HR zones 1–3 · weekly"
        case .zonesHigh: return "HR zones 4–5 · weekly"
        case .vo2Max: return "VO₂ max"
        case .calories: return "Calories"
        case .stress: return "Stress monitor"
        }
    }

    /// Saved order with unknown keys dropped and rows added since that save
    /// appended at the end — so an upgrade shows a new row without losing the
    /// arrangement the wearer already made.
    static func sanitized(order names: [String]) -> [DashboardRow] {
        var seen = Set<DashboardRow>()
        var rows: [DashboardRow] = []
        for name in names {
            guard let row = DashboardRow(rawValue: name), seen.insert(row).inserted else { continue }
            rows.append(row)
        }
        rows.append(contentsOf: allCases.filter { !seen.contains($0) })
        return rows
    }

    static func sanitized(hidden names: [String]) -> [DashboardRow] {
        var seen = Set<DashboardRow>()
        return names.compactMap { name in
            guard let row = DashboardRow(rawValue: name), seen.insert(row).inserted else { return nil }
            return row
        }
    }
}

/// Persisted user settings. Defaults match the spec: age 30, sleep need 8 h,
/// wake 07:00, design preview OFF (live mode never invents a value).
struct AppSettings: Codable, Equatable {
    var age: Int = 30
    var sex: Sex = .unspecified
    /// Body mass and height only price the calorie estimate (Mifflin–St Jeor
    /// basal + Keytel active). Nil means the app shows "—" and names the gap.
    var weightKG: Double? = nil
    var heightCM: Double? = nil
    var restingHROverride: Double? = nil
    var maxHROverride: Double? = nil
    var sleepNeedHours: Double = 8.0
    var wakeTimeMinutes: Int = 7 * 60
    var sleepIntent: SleepIntent = .easy
    var designPreview: Bool = false
    /// Optional Apple Health export. OFF by default; the toggle is the only
    /// path that ever asks HealthKit for permission.
    var healthKitEnabled: Bool = false
    /// Home/Dashboard arrangement. Every row appears in `dashboardOrder`;
    /// hidden rows keep their position so unhiding restores it.
    var dashboardOrder: [DashboardRow] = DashboardRow.allCases
    var hiddenDashboardRows: [DashboardRow] = []

    enum CodingKeys: String, CodingKey {
        case age, sex, restingHROverride, maxHROverride
        case weightKG, heightCM
        case sleepNeedHours, wakeTimeMinutes, sleepIntent, designPreview
        case healthKitEnabled
        case dashboardOrder, hiddenDashboardRows
    }

    init() {}

    /// Field-by-field so settings saved before a new key existed still load
    /// instead of falling back to every default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        age = try container.decodeIfPresent(Int.self, forKey: .age) ?? 30
        sex = try container.decodeIfPresent(Sex.self, forKey: .sex) ?? .unspecified
        weightKG = try container.decodeIfPresent(Double.self, forKey: .weightKG)
        heightCM = try container.decodeIfPresent(Double.self, forKey: .heightCM)
        restingHROverride = try container.decodeIfPresent(Double.self, forKey: .restingHROverride)
        maxHROverride = try container.decodeIfPresent(Double.self, forKey: .maxHROverride)
        sleepNeedHours = try container.decodeIfPresent(Double.self, forKey: .sleepNeedHours) ?? 8.0
        wakeTimeMinutes = try container.decodeIfPresent(Int.self, forKey: .wakeTimeMinutes) ?? 7 * 60
        sleepIntent = try container.decodeIfPresent(SleepIntent.self, forKey: .sleepIntent) ?? .easy
        designPreview = try container.decodeIfPresent(Bool.self, forKey: .designPreview) ?? false
        healthKitEnabled = try container.decodeIfPresent(Bool.self, forKey: .healthKitEnabled) ?? false
        let order = try container.decodeIfPresent([String].self, forKey: .dashboardOrder)
        dashboardOrder = DashboardRow.sanitized(order: order ?? [])
        let hidden = try container.decodeIfPresent([String].self, forKey: .hiddenDashboardRows)
        hiddenDashboardRows = DashboardRow.sanitized(hidden: hidden ?? [])
    }
}

// MARK: - Journal (self-report only; the band sends no journal data)

enum Mood: String, Codable, CaseIterable, Identifiable {
    case great
    case good
    case okay
    case low

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum Soreness: String, Codable, CaseIterable, Identifiable {
    case none
    case mild
    case moderate
    case high

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Our own seven-question list — not copied from any proprietary journal.
enum JournalQuestion: String, Codable, CaseIterable, Identifiable {
    case alcohol
    case lateCaffeine
    case lateMeal
    case screensInBed
    case illnessFeel
    case travel
    case lateWorkout

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alcohol: return "Alcohol?"
        case .lateCaffeine: return "Late caffeine?"
        case .lateMeal: return "Late meal?"
        case .screensInBed: return "Screens in bed?"
        case .illnessFeel: return "Illness feel?"
        case .travel: return "Travel?"
        case .lateWorkout: return "Late workout?"
        }
    }
}

/// One entry per day, keyed by `yyyy-MM-dd`. Saving again updates the entry.
/// Journal answers never alter any score.
struct JournalEntry: Codable, Equatable {
    var dateKey: String
    var answers: [String: Bool] = [:]
    var mood: Mood? = nil
    var soreness: Soreness = .none
    var notes: String = ""

    func answer(_ question: JournalQuestion) -> Bool {
        answers[question.rawValue] ?? false
    }

    mutating func setAnswer(_ question: JournalQuestion, _ value: Bool) {
        answers[question.rawValue] = value
    }

    var yesCount: Int {
        JournalQuestion.allCases.filter { answer($0) }.count
    }
}