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


struct WhoopWorkout: Codable, Equatable, Identifiable {
    let id: String
    let sportName: String
    let startUnix: Int
    let endUnix: Int
    let strain: Double?
    let averageHeartRate: Int?
}

enum WhoopWorkoutImport {
    private struct Page: Decodable {
        let records: [Record]
        let next_token: String?
    }
    private struct Record: Decodable {
        let id: String
        let sport_name: String
        let start: Date
        let end: Date
        let score: Score?
    }
    private struct Score: Decodable {
        let strain: Double?
        let average_heart_rate: Int?
    }

    /// One authorized WHOOP API v2 workout page; paginate using next_token.
    static func decodePage(_ data: Data) throws -> (workouts: [WhoopWorkout], nextToken: String?) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            guard let date = fractional.date(from: value) ?? plain.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 workout timestamp")
            }
            return date
        }
        let page = try decoder.decode(Page.self, from: data)
        let workouts = page.records.compactMap { item -> WhoopWorkout? in
            guard item.end > item.start, !item.id.isEmpty else { return nil }
            return WhoopWorkout(
                id: item.id, sportName: item.sport_name,
                startUnix: Int(item.start.timeIntervalSince1970),
                endUnix: Int(item.end.timeIntervalSince1970),
                strain: item.score?.strain,
                averageHeartRate: item.score?.average_heart_rate
            )
        }
        return (workouts, page.next_token)
    }
}

// MARK: - Persistence

/// UserDefaults-backed activity log. Manual entries, measured live sessions
/// and band-detected sessions are stored separately so none can be mistaken
/// for another.
final class ActivityStore {
    private let defaults: UserDefaults
    private let manualKey = "strap.activities.v1"
    private let liveKey = "strap.live.sessions.v1"
    private let detectedKey = "strap.detected.activities.v1"
    private let whoopKey = "strap.whoop.official.workouts.v1"

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

    func whoopWorkouts() -> [WhoopWorkout] {
        guard let data = defaults.data(forKey: whoopKey),
              let saved = try? JSONDecoder().decode([WhoopWorkout].self, from: data) else {
            return []
        }
        return saved.sorted { $0.startUnix < $1.startUnix }
    }

    func mergeWhoopWorkouts(_ incoming: [WhoopWorkout]) {
        var byID = Dictionary(uniqueKeysWithValues: whoopWorkouts().map { ($0.id, $0) })
        for item in incoming { byID[item.id] = item }
        if let data = try? JSONEncoder().encode(Array(byID.values)) {
            defaults.set(data, forKey: whoopKey)
        }
    }

    // MARK: - Band-detected sessions

    func detectedActivities() -> [ActivitySession] {
        guard let data = defaults.data(forKey: detectedKey),
              let saved = try? JSONDecoder().decode([ActivitySession].self, from: data) else {
            return []
        }
        return saved.sorted { $0.startUnix < $1.startUnix }
    }

    /// Keeps one row per real session. The band replays overlapping history,
    /// so a session that overlaps an already-stored one is merged rather than
    /// appended, and the longer measurement wins.
    func mergeDetected(_ sessions: [ActivitySession], now: Date = Date()) {
        guard !sessions.isEmpty else { return }
        var items = detectedActivities()
        for session in sessions {
            if let index = items.firstIndex(where: { Self.overlaps($0, session) }) {
                if session.durationS > items[index].durationS {
                    items[index] = session
                }
            } else {
                items.append(session)
            }
        }
        let cutoff = Int(now.timeIntervalSince1970) - 60 * 86_400
        items = items.filter { $0.endUnix >= cutoff }.sorted { $0.startUnix < $1.startUnix }
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: detectedKey)
        }
    }

    static func overlaps(_ a: ActivitySession, _ b: ActivitySession) -> Bool {
        let shared = min(a.endUnix, b.endUnix) - max(a.startUnix, b.startUnix) + 1
        guard shared > 0 else { return false }
        let shorter = min(a.durationS, b.durationS)
        return Double(shared) >= Double(shorter) * 0.5
    }
}
