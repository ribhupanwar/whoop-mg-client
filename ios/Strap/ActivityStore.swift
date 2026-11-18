import Foundation

// MARK: - Manual activities

enum ActivityKind: String, Codable, CaseIterable, Identifiable {
    case lift
    case run
    case walk
    case cardio
    case other
    case cycling, swimming, yoga, pilates, dance, hiking, rowing, elliptical
    case treadmill, stairClimber, hiit, functionalFitness, crossTraining
    case basketball, football, cricket, badminton, tennis, tableTennis
    case boxing, martialArts, climbing, skiing, skating, golf
    case meditation, stretching, mobility, spin, indoorWalk
    case outdoorRun, trailRun, intervalRun, strengthTraining, weightlifting
    case jumpRope, pickleball, volleyball, rugby, soccer, surfing
    case paddleboarding, kayaking, canoeing, aerobics, barre, gymnastics
    case wrestling, fencing, squash, racquetball, handball, baseball
    case softball, hockey, lacrosse, horsebackRiding, gardening

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lift: return "Lift"
        case .run: return "Run"
        case .walk: return "Walk"
        case .cardio: return "Cardio"
        case .other: return "Other"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .dance: return "Dance"
        case .hiking: return "Hiking"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .treadmill: return "Treadmill Running"
        case .stairClimber: return "Stair Climber"
        case .hiit: return "HIIT"
        case .functionalFitness: return "Functional Fitness"
        case .crossTraining: return "Cross Training"
        case .basketball: return "Basketball"
        case .football: return "American Football"
        case .cricket: return "Cricket"
        case .badminton: return "Badminton"
        case .tennis: return "Tennis"
        case .tableTennis: return "Table Tennis"
        case .boxing: return "Boxing"
        case .martialArts: return "Martial Arts"
        case .climbing: return "Climbing"
        case .skiing: return "Skiing"
        case .skating: return "Skating"
        case .golf: return "Golf"
        case .meditation: return "Meditation"
        case .stretching: return "Stretching"
        case .mobility: return "Mobility"
        case .spin: return "Spin"
        case .indoorWalk: return "Indoor Walking"
        case .outdoorRun: return "Outdoor Running"
        case .trailRun: return "Trail Running"
        case .intervalRun: return "Interval Running"
        case .strengthTraining: return "Strength Training"
        case .weightlifting: return "Weightlifting"
        case .jumpRope: return "Jump Rope"
        case .pickleball: return "Pickleball"
        case .volleyball: return "Volleyball"
        case .rugby: return "Rugby"
        case .soccer: return "Soccer"
        case .surfing: return "Surfing"
        case .paddleboarding: return "Paddleboarding"
        case .kayaking: return "Kayaking"
        case .canoeing: return "Canoeing"
        case .aerobics: return "Aerobics"
        case .barre: return "Barre"
        case .gymnastics: return "Gymnastics"
        case .wrestling: return "Wrestling"
        case .fencing: return "Fencing"
        case .squash: return "Squash"
        case .racquetball: return "Racquetball"
        case .handball: return "Handball"
        case .baseball: return "Baseball"
        case .softball: return "Softball"
        case .hockey: return "Hockey"
        case .lacrosse: return "Lacrosse"
        case .horsebackRiding: return "Horseback Riding"
        case .gardening: return "Gardening"
        }
    }

    var icon: String {
        switch self {
        case .lift: return "dumbbell.fill"
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .cardio: return "heart.fill"
        case .other: return "figure.mixed.cardio"
        case .cycling, .spin: return "bicycle"
        case .swimming, .surfing, .paddleboarding, .kayaking, .canoeing: return "figure.pool.swim"
        case .yoga, .pilates, .stretching, .mobility, .meditation, .barre: return "figure.cooldown"
        case .dance, .aerobics, .gymnastics: return "figure.dance"
        case .hiking, .climbing: return "figure.hiking"
        case .rowing: return "figure.rower"
        case .elliptical, .stairClimber, .hiit, .functionalFitness, .crossTraining, .jumpRope: return "figure.highintensity.intervaltraining"
        case .treadmill, .outdoorRun, .trailRun, .intervalRun: return "figure.run"
        case .indoorWalk, .golf, .gardening: return "figure.walk"
        case .strengthTraining, .weightlifting: return "dumbbell.fill"
        case .boxing, .martialArts, .wrestling, .fencing: return "figure.boxing"
        case .tennis, .badminton, .tableTennis, .pickleball, .squash, .racquetball: return "figure.tennis"
        case .basketball, .football, .cricket, .volleyball, .rugby, .soccer, .handball, .baseball, .softball, .hockey, .lacrosse: return "sportscourt"
        case .skiing, .skating: return "figure.skiing.downhill"
        case .horsebackRiding: return "figure.equestrian.sports"
        }
    }

    /// Lifting is entered as sets; everything else by minutes.
    var usesSets: Bool { self == .lift || self == .strengthTraining || self == .weightlifting }
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
    let mergedFrom: [ManualActivity]?

    init(
        id: UUID = UUID(),
        dateKey: String,
        kind: ActivityKind,
        name: String,
        minutes: Int,
        sets: [WorkSet] = [],
        notes: String = "",
        mergedFrom: [ManualActivity]? = nil
    ) {
        self.id = id
        self.dateKey = dateKey
        self.kind = kind
        self.name = name
        self.minutes = minutes
        self.sets = sets
        self.notes = notes
        self.mergedFrom = mergedFrom
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
        let valid = samples.filter { (25...230).contains($0.heartRate) }
        let ordered = Dictionary(valid.map { ($0.unix, $0) }, uniquingKeysWith: { _, last in last })
            .values.sorted { $0.unix < $1.unix }
        for (index, sample) in ordered.enumerated() {
            let next = index + 1 < ordered.count ? ordered[index + 1].unix : sample.unix + 1
            let gap = next - sample.unix
            let span = gap > 30 ? 1 : max(1, min(5, gap))
            let hr = Double(sample.heartRate)
            if let index = Karvonen.zoneIndex(heartRate: hr, zones: zones),
               let zoneIndex = zones.firstIndex(where: { $0.index == index }) {
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
private struct DeletedDetectedActivity: Codable, Equatable {
    let startUnix: Int
    let endUnix: Int
    let deletedAtUnix: Int
}

final class ActivityStore {
    private let detectedLock = NSRecursiveLock()
    private let defaults: UserDefaults
    private let manualRevisionDirectory: URL
    private(set) var lastManualWriteError: String?
    static var revisionArchiveDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("captures/activity-revisions", isDirectory: true)
    }
    private let manualKey = "strap.activities.v1"
    private let liveKey = "strap.live.sessions.v1"
    private let detectedKey = "strap.detected.activities.v1"
    private let deletedDetectedKey = "strap.detected.activities.deleted.v1"
    private let whoopKey = "strap.whoop.official.workouts.v1"

    init(defaults: UserDefaults = .standard, revisionDirectory: URL? = nil) {
        self.defaults = defaults
        self.manualRevisionDirectory = revisionDirectory ?? (defaults === UserDefaults.standard
            ? Self.revisionArchiveDirectory
            : FileManager.default.temporaryDirectory.appendingPathComponent("STRAP-activity-revisions-" + UUID().uuidString))
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

    private func strictManualActivities() throws -> [ManualActivity] {
        guard let original = defaults.object(forKey: manualKey) else { return [] }
        guard let bytes = original as? Data else {
            throw PersistenceDiagnostics.Failure(message: "Original activity history could not be read; it was preserved.")
        }
        return try JSONDecoder().decode([ManualActivity].self, from: bytes)
    }

    private func archiveManualRevision(_ original: Data, directory: URL? = nil) throws {
        let destination = directory ?? manualRevisionDirectory
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let archive = destination.appendingPathComponent(PersistenceDiagnostics.digest(original) + ".json")
        if FileManager.default.fileExists(atPath: archive.path) {
            guard try Data(contentsOf: archive) == original else {
                throw PersistenceDiagnostics.Failure(message: "Activity archive conflict; original history preserved.")
            }
        } else { try original.write(to: archive, options: .atomic) }
    }

    private func persistManual(_ items: [ManualActivity]) throws {
        let bytes = try JSONEncoder().encode(items)
        if let original = defaults.data(forKey: manualKey) { try archiveManualRevision(original) }
        defaults.set(bytes, forKey: manualKey)
    }

    @discardableResult
    func save(_ activity: ManualActivity) -> Bool {
        do {
            var items = try strictManualActivities()
            if let index = items.firstIndex(where: { $0.id == activity.id }) { items[index] = activity }
            else { items.append(activity) }
            try persistManual(items)
            lastManualWriteError = nil
            return true
        } catch { lastManualWriteError = error.localizedDescription; return false }
    }

    @discardableResult
    func restoreMissingManual(_ activity: ManualActivity) throws -> Bool {
        var items = try strictManualActivities()
        guard !items.contains(where: { $0.id == activity.id }) else { return false }
        items.append(activity)
        try persistManual(items)
        return true
    }

    @discardableResult
    func mergeManual(ids: Set<UUID>, name: String) throws -> ManualActivity {
        guard ids.count >= 2, let original = defaults.data(forKey: manualKey) else {
            throw PersistenceDiagnostics.Failure(message: "Select at least two manual entries.")
        }
        let items = try JSONDecoder().decode([ManualActivity].self, from: original)
        let selected = items.filter { ids.contains($0.id) }
        guard selected.count == ids.count, let first = selected.first,
              selected.allSatisfy({ $0.dateKey == first.dateKey && $0.kind == first.kind && $0.minutes >= 0 }) else {
            throw PersistenceDiagnostics.Failure(message: "Merge only existing manual entries of the same type and date.")
        }
        var minutes = 0
        for item in selected {
            let sum = minutes.addingReportingOverflow(item.minutes)
            guard !sum.overflow else { throw PersistenceDiagnostics.Failure(message: "Combined duration is too large.") }
            minutes = sum.partialValue
        }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let merged = ManualActivity(dateKey: first.dateKey, kind: first.kind,
            name: title.isEmpty ? first.kind.label + " (merged)" : title, minutes: minutes,
            sets: selected.flatMap(\.sets), notes: selected.map { $0.name + ": " + $0.notes }.joined(separator: "\n"),
            mergedFrom: selected)
        try archiveManualRevision(original)
        let updated = items.filter { !ids.contains($0.id) } + [merged]
        defaults.set(try JSONEncoder().encode(updated), forKey: manualKey)
        return merged
    }

    func undoManualMerge(id: UUID) throws {
        guard let original = defaults.data(forKey: manualKey) else {
            throw PersistenceDiagnostics.Failure(message: "Manual history is unavailable.")
        }
        let items = try JSONDecoder().decode([ManualActivity].self, from: original)
        guard let merged = items.first(where: { $0.id == id }),
              let retained = merged.mergedFrom, !retained.isEmpty else {
            throw PersistenceDiagnostics.Failure(message: "No retained merge originals found.")
        }
        var updated = items.filter { $0.id != id }
        for row in retained {
            if let existing = updated.first(where: { $0.id == row.id }) {
                guard existing == row else {
                    throw PersistenceDiagnostics.Failure(message: "An original entry was changed separately; undo cancelled to preserve it.")
                }
            } else { updated.append(row) }
        }
        try archiveManualRevision(original)
        defaults.set(try JSONEncoder().encode(updated), forKey: manualKey)
    }

    @discardableResult
    func deleteManual(id: UUID) -> Bool {
        do {
            let items = try strictManualActivities()
            guard items.contains(where: { $0.id == id }) else { lastManualWriteError = nil; return true }
            try persistManual(items.filter { $0.id != id })
            lastManualWriteError = nil
            return true
        } catch { lastManualWriteError = error.localizedDescription; return false }
    }

    func saveLive(_ record: LiveActivityRecord) {
        var items = liveActivities()
        if let index = items.firstIndex(where: { $0.id == record.id }) {
            items[index] = record
        } else {
            items.append(record)
        }
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: liveKey)
        }
    }

    func deleteLive(id: UUID) {
        let items = liveActivities().filter { $0.id != id }
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
        detectedLock.lock()
        defer { detectedLock.unlock() }
        guard let data = defaults.data(forKey: detectedKey),
              let saved = try? JSONDecoder().decode([ActivitySession].self, from: data) else {
            return []
        }
        let deletions = deletedDetectedSessions()
        return saved.filter { session in !deletions.contains { Self.matches(session, deletion: $0) } }
            .sorted { $0.startUnix < $1.startUnix }
    }

    /// Hides a deleted band session across replays whose boundaries shift slightly.
    func isDetectedDeleted(_ session: ActivitySession) -> Bool {
        deletedDetectedSessions().contains { Self.matches(session, deletion: $0) }
    }

    func deleteDetected(_ session: ActivitySession, now: Date = Date()) {
        detectedLock.lock()
        defer { detectedLock.unlock() }
        var deletions = deletedDetectedSessions()
        if !deletions.contains(where: { Self.matches(session, deletion: $0) }) {
            deletions.append(DeletedDetectedActivity(
                startUnix: session.startUnix, endUnix: session.endUnix,
                deletedAtUnix: Int(now.timeIntervalSince1970)
            ))
        }
        if let data = try? JSONEncoder().encode(deletions) {
            defaults.set(data, forKey: deletedDetectedKey)
        }
        let remaining = detectedActivities().filter { !Self.matches($0, deletion: DeletedDetectedActivity(
            startUnix: session.startUnix, endUnix: session.endUnix,
            deletedAtUnix: Int(now.timeIntervalSince1970)
        )) }
        if let data = try? JSONEncoder().encode(remaining) {
            defaults.set(data, forKey: detectedKey)
        }
    }

    private func deletedDetectedSessions() -> [DeletedDetectedActivity] {
        guard let data = defaults.data(forKey: deletedDetectedKey),
              let saved = try? JSONDecoder().decode([DeletedDetectedActivity].self, from: data) else {
            return []
        }
        return saved
    }

    private static func matches(_ session: ActivitySession, deletion: DeletedDetectedActivity) -> Bool {
        let shared = min(session.endUnix, deletion.endUnix) - max(session.startUnix, deletion.startUnix) + 1
        let shorter = min(session.durationS, deletion.endUnix - deletion.startUnix + 1)
        return shared > 0 && shorter > 0 && Double(shared) >= Double(shorter) * 0.5
    }

    /// Keeps one row per real session. The band replays overlapping history,
    /// so a session that overlaps an already-stored one is merged rather than
    /// appended, and the longer measurement wins.
    func mergeDetected(_ sessions: [ActivitySession], now: Date = Date()) {
        detectedLock.lock()
        defer { detectedLock.unlock() }
        guard !sessions.isEmpty else { return }
        // A corrupt existing archive must not be silently replaced by the
        // latest sync batch. Preserve the original bytes for recovery.
        if let existing = defaults.data(forKey: detectedKey),
           (try? JSONDecoder().decode([ActivitySession].self, from: existing)) == nil {
            return
        }
        // Replayed history can contain several overlapping variants of the
        // same workout. Deduplicate across both existing and incoming rows,
        // not just the first match; repeat until transitive overlaps collapse.
        // Historical workouts are user records, not a rolling cache.
        // Never prune older sessions during an unrelated band sync.
        let deletions = deletedDetectedSessions()
        var seen = Set<String>()
        var items = (detectedActivities() + sessions).filter { session in
            guard !deletions.contains(where: { Self.matches(session, deletion: $0) }) else { return false }
            return seen.insert("\(session.startUnix):\(session.endUnix)").inserted
        }
        var changed = true
        while changed {
            changed = false
            outer: for i in items.indices {
                for j in items.indices where j > i {
                    guard Self.overlaps(items[i], items[j]) else { continue }
                    // Keep the more complete record. Stable tie-break makes
                    // repeated imports idempotent regardless of arrival order.
                    let a = items[i], b = items[j]
                    let winner = a.durationS > b.durationS ? a
                        : b.durationS > a.durationS ? b
                        : a.startUnix <= b.startUnix ? a : b
                    items[i] = winner
                    items.remove(at: j)
                    changed = true
                    break outer
                }
            }
        }
        items = items.sorted { $0.startUnix < $1.startUnix }
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
