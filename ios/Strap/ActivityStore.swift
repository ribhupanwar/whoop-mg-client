import Foundation

// MARK: - Manual activities

enum ActivityKind: String, Codable, CaseIterable, Identifiable {
    case lift
    case run
    case walk
    case cardio
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lift: return "Lift"
        case .run: return "Run"
        case .walk: return "Walk"
        case .cardio: return "Cardio"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .lift: return "dumbbell.fill"
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .cardio: return "heart.fill"
        case .other: return "figure.mixed.cardio"
        }
    }

    /// Lifting is entered as sets; everything else by minutes.
    var usesSets: Bool { self == .lift }
}

/// One set of a lift: reps at a load. The band sends no load, so this is
/// always self-reported.
struct WorkSet: Codable, Equatable, Identifiable {
    var id = UUID()
    var reps: Int
    var loadKG: Double

    var volumeKG: Double { Double(reps) * loadKG }
}

/// A self-entered session. Never mixed into strain or recovery — those stay
/// sensor-derived. Manual entries are the log, not a measurement.
struct ManualActivity: Codable, Equatable, Identifiable {
    var id = UUID()
    var dateKey: String
    var kind: ActivityKind
    var name: String
    var minutes: Int
    var sets: [WorkSet]
    var notes: String

    init(
        id: UUID = UUID(),
        dateKey: String,
        kind: ActivityKind,
        name: String,
        minutes: Int,
        sets: [WorkSet] = [],
        notes: String = ""
    ) {
        self.id = id
        self.dateKey = dateKey
        self.kind = kind
        self.name = name
        self.minutes = minutes
        self.sets = sets
        self.notes = notes
    }

    var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }
    var volumeKG: Double { sets.reduce(0.0) { $0 + $1.volumeKG } }

    var summary: String {
        if kind.usesSets, !sets.isEmpty {
            return "\(sets.count) sets · \(totalReps) reps · \(Int(volumeKG.rounded())) kg"
        }
        return "\(minutes) min"
    }
}

// MARK: - Live sessions

/// One measured live HR session from the standard heart-rate profile.
struct LiveActivityRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var dateKey: String
    let startedUnix: Int
    let endedUnix: Int
    let meanHR: Double?
    let maxHR: Int?
    let beats: Int
    let hrv: HrvResult
    /// Seconds spent in each Karvonen zone (Z1…Z5). Empty when zones were
    /// unavailable, so the UI can say so instead of showing zeros.
    let zoneSeconds: [Int]

    var seconds: Int { max(0, endedUnix - startedUnix) }
    var minutes: Double { Double(seconds) / 60.0 }
}

enum LiveZones {
    /// Each sample stands for the gap until the next one (1–5 s). Heart rates
    /// below Z1 or above max HR count toward no zone.
    static func seconds(samples: [LiveSample], zones: [HRZone]?) -> [Int] {
        guard let zones, !zones.isEmpty else { return [] }
        var buckets = [Int](repeating: 0, count: zones.count)
        for (index, sample) in samples.enumerated() {
            let next = index + 1 < samples.count ? samples[index + 1].unix : sample.unix + 1
            let span = max(1, min(5, next - sample.unix))
            let hr = Double(sample.heartRate)
            if let zoneIndex = zones.firstIndex(
                where: { hr >= $0.lowerBPM && hr < $0.upperBPM }
            ) {
                buckets[zoneIndex] += span
            }
        }
        return buckets
    }
}

// MARK: - Formatting

enum ActivityFormat {
    /// Minutes as h:mm, the same shape the dashboard uses for weekly zone time.
    static func clock(minutes: Double) -> String {
        let seconds = Int((minutes * 60).rounded())
        return String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }

    /// Milliseconds as a whole number with an optional unit.
    static func whole(_ value: Double?, unit: String = "") -> String? {
        guard let value else { return nil }
        return String(format: "%.0f", value) + unit
    }
}

// MARK: - Persistence

/// UserDefaults-backed activity log. Manual entries and measured live
/// sessions are stored separately so neither can be mistaken for the other.
final class ActivityStore {
    private let defaults: UserDefaults
    private let manualKey = "strap.activities.v1"
    private let liveKey = "strap.live.sessions.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func manualActivities() -> [ManualActivity] {
        guard let data = defaults.data(forKey: manualKey),
              let saved = try? JSONDecoder().decode([ManualActivity].self, from: data) else {
            return []
        }
        return saved.sorted { $0.dateKey < $1.dateKey }
    }

    func liveActivities() -> [LiveActivityRecord] {
        guard let data = defaults.data(forKey: liveKey),
              let saved = try? JSONDecoder().decode([LiveActivityRecord].self, from: data) else {
            return []
        }
        return saved.sorted { $0.startedUnix < $1.startedUnix }
    }

    func save(_ activity: ManualActivity) {
        var items = manualActivities()
        if let index = items.firstIndex(where: { $0.id == activity.id }) {
            items[index] = activity
        } else {
            items.append(activity)
        }
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: manualKey)
        }
    }

    func deleteManual(id: UUID) {
        let items = manualActivities().filter { $0.id != id }
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: manualKey)
        }
    }

    func saveLive(_ record: LiveActivityRecord) {
        var items = liveActivities()
        items.append(record)
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: liveKey)
        }
    }
}
