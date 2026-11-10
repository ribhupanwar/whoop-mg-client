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

/// Persisted user settings. Defaults match the spec: age 30, sleep need 8 h,
/// wake 07:00, design preview OFF (live mode never invents a value).
struct AppSettings: Codable, Equatable {
    var age: Int = 30
    var sex: Sex = .unspecified
    var restingHROverride: Double? = nil
    var maxHROverride: Double? = nil
    var sleepNeedHours: Double = 8.0
    var wakeTimeMinutes: Int = 7 * 60
    var sleepIntent: SleepIntent = .easy
    var designPreview: Bool = false

    enum CodingKeys: String, CodingKey {
        case age, sex, restingHROverride, maxHROverride
        case sleepNeedHours, wakeTimeMinutes, sleepIntent, designPreview
    }

    init() {}

    /// Field-by-field so settings saved before a new key existed still load
    /// instead of falling back to every default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        age = try container.decodeIfPresent(Int.self, forKey: .age) ?? 30
        sex = try container.decodeIfPresent(Sex.self, forKey: .sex) ?? .unspecified
        restingHROverride = try container.decodeIfPresent(Double.self, forKey: .restingHROverride)
        maxHROverride = try container.decodeIfPresent(Double.self, forKey: .maxHROverride)
        sleepNeedHours = try container.decodeIfPresent(Double.self, forKey: .sleepNeedHours) ?? 8.0
        wakeTimeMinutes = try container.decodeIfPresent(Int.self, forKey: .wakeTimeMinutes) ?? 7 * 60
        sleepIntent = try container.decodeIfPresent(SleepIntent.self, forKey: .sleepIntent) ?? .easy
        designPreview = try container.decodeIfPresent(Bool.self, forKey: .designPreview) ?? false
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