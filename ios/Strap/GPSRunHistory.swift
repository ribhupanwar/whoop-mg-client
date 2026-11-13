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

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Custom test suites must never share the production file.
        let suffix = directory == nil && defaults !== UserDefaults.standard
            ? "gps-runs-\(UUID().uuidString).json" : "gps-runs-v2.json"
        self.fileURL = root.appendingPathComponent("Strap", isDirectory: true)
            .appendingPathComponent(suffix)
    }

    func all() -> [GPSRunRecord] {
        if let data = try? Data(contentsOf: fileURL),
           let runs = try? JSONDecoder().decode([GPSRunRecord].self, from: data) {
            return runs.sorted { $0.startedAt > $1.startedAt }
        }
        guard let legacy = defaults.data(forKey: key),
              let runs = try? JSONDecoder().decode([GPSRunRecord].self, from: legacy) else { return [] }
        if persist(runs) { defaults.removeObject(forKey: key) }
        return runs.sorted { $0.startedAt > $1.startedAt }
    }

    @discardableResult
    private func persist(_ runs: [GPSRunRecord]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(runs)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            return true
        } catch {
            return false
        }
    }

    func save(_ record: GPSRunRecord) {
        var runs = all()
        if let index = runs.firstIndex(where: { $0.id == record.id }) {
            runs[index] = record
        } else { runs.append(record) }
        _ = persist(runs)
    }

    func delete(id: UUID) {
        _ = persist(all().filter { $0.id != id })
    }
}
