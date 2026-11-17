import Foundation

struct GPSRunPoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let unix: TimeInterval
    let accuracyMeters: Double
}

struct GPSRunRecord: Codable, Identifiable, Equatable {
    var id: UUID
    let startedAt: Date
    let endedAt: Date
    let movingSeconds: Int
    let distanceMeters: Double
    let splitSeconds: [Int]
    let route: [GPSRunPoint]

    var paceSecondsPerKM: Double? {
        guard distanceMeters >= 100, movingSeconds > 0 else { return nil }
        return Double(movingSeconds) / (distanceMeters / 1000)
    }
}

/// Routes are stored atomically in Application Support, not in the preferences
/// database. Legacy UserDefaults history is migrated on first read.
final class GPSRunHistory {
    private let defaults: UserDefaults
    private let key = "strap.gps.runs.v1"
    private let fileURL: URL
    let revisionDirectory: URL
    private(set) var lastWriteError: String?
    static var revisionArchiveDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("captures/gps-revisions", isDirectory: true)
    }

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Custom test suites must never share the production file.
        let suffix: String
        if directory == nil && defaults !== UserDefaults.standard {
            let idKey = "strap.gps.test.storageID"
            let id = defaults.string(forKey: idKey) ?? UUID().uuidString
            defaults.set(id, forKey: idKey)
            suffix = "gps-runs-\(id).json"
        } else {
            suffix = "gps-runs-v2.json"
        }
        self.fileURL = root.appendingPathComponent("Strap", isDirectory: true)
            .appendingPathComponent(suffix)
        if let directory { revisionDirectory = directory.appendingPathComponent("captures/gps-revisions", isDirectory: true) }
        else if defaults === UserDefaults.standard {
            revisionDirectory = Self.revisionArchiveDirectory
        } else { revisionDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("STRAP-revisions-" + suffix, isDirectory: true) }
    }

    private func strictRuns() throws -> [GPSRunRecord] {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return try JSONDecoder().decode([GPSRunRecord].self, from: Data(contentsOf: fileURL))
        }
        guard let original = defaults.object(forKey: key) else { return [] }
        guard let data = original as? Data else {
            throw PersistenceDiagnostics.Failure(message: "Original GPS history could not be read; it was preserved.")
        }
        return try JSONDecoder().decode([GPSRunRecord].self, from: data)
    }
    func all() -> [GPSRunRecord] {
        do {
            let runs = try strictRuns()
            if !FileManager.default.fileExists(atPath: fileURL.path), defaults.data(forKey: key) != nil {
                _ = persist(runs) // Retain legacy bytes even after successful migration.
            }
            return runs.sorted { $0.startedAt > $1.startedAt }
        } catch { lastWriteError = error.localizedDescription; return [] }
    }
    private func archive(_ data: Data) throws {
        try FileManager.default.createDirectory(at: revisionDirectory, withIntermediateDirectories: true)
        let file = revisionDirectory.appendingPathComponent(PersistenceDiagnostics.digest(data) + ".json")
        if FileManager.default.fileExists(atPath: file.path) {
            guard try Data(contentsOf: file) == data else {
                throw PersistenceDiagnostics.Failure(message: "GPS revision conflict; original history preserved.")
            }
        } else { try data.write(to: file, options: .atomic) }
    }
    @discardableResult
    private func persist(_ runs: [GPSRunRecord]) -> Bool {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(runs)
            if FileManager.default.fileExists(atPath: fileURL.path) { try archive(Data(contentsOf: fileURL)) }
            else if let legacy = defaults.data(forKey: key) { try archive(legacy) }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            lastWriteError = nil; return true
        } catch { lastWriteError = error.localizedDescription; return false }
    }
    @discardableResult
    func save(_ record: GPSRunRecord) -> Bool {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try archive(encoder.encode([record])) // Retain the newly finished route on cache failures.
            var runs = try strictRuns()
            if let index = runs.firstIndex(where: { $0.id == record.id }) { runs[index] = record }
            else { runs.append(record) }
            return persist(runs)
        } catch { lastWriteError = error.localizedDescription; return false }
    }
    @discardableResult
    func delete(id: UUID) -> Bool {
        do {
            let runs = try strictRuns()
            guard runs.contains(where: { $0.id == id }) else { return true }
            return persist(runs.filter { $0.id != id })
        } catch { lastWriteError = error.localizedDescription; return false }
    }
    @discardableResult
    func restoreMissing(_ record: GPSRunRecord) throws -> Bool {
        var runs = try strictRuns()
        guard !runs.contains(where: { $0.id == record.id }) else { return false }
        runs.append(record)
        guard persist(runs) else {
            throw PersistenceDiagnostics.Failure(message: lastWriteError ?? "Cannot restore GPS history; originals preserved.")
        }
        return true
    }
}
