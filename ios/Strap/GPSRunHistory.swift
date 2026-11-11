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

/// Device-local storage, independent of HealthKit and SideStore entitlements.
final class GPSRunHistory {
    private let defaults: UserDefaults
    private let key = "strap.gps.runs.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func all() -> [GPSRunRecord] {
        guard let data = defaults.data(forKey: key),
              let runs = try? JSONDecoder().decode([GPSRunRecord].self, from: data)
        else { return [] }
        return runs.sorted { $0.startedAt > $1.startedAt }
    }

    func save(_ record: GPSRunRecord) {
        var runs = all()
        if let index = runs.firstIndex(where: { $0.id == record.id }) {
            runs[index] = record
        } else { runs.append(record) }
        if let data = try? JSONEncoder().encode(runs) {
            defaults.set(data, forKey: key)
        }
    }

    func delete(id: UUID) {
        if let data = try? JSONEncoder().encode(all().filter { $0.id != id }) {
            defaults.set(data, forKey: key)
        }
    }
}
