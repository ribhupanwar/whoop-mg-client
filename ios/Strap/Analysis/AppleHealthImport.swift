import Foundation
import HealthKit

/// Imported HealthKit source records stay separate from band-derived RMSSD and
/// Recovery. HealthKit HRV is SDNN and must never be relabelled RMSSD.
enum AppleHealthImport {
    static let key = "strap.appleHealth.import.samples.v1"
    struct Record: Codable, Identifiable {
        let id: UUID
        let type: String
        let sourceBundle: String
        let startUnix: Double
        let endUnix: Double
        let timezone: String?
        let values: [String: Double]
        let unit: String?
    }
    static func load(defaults: UserDefaults = .standard) throws -> [Record] {
        try defaults.data(forKey: key).map { try JSONDecoder().decode([Record].self, from: $0) } ?? []
    }
    static func run(from start: Date, through end: Date, defaults: UserDefaults = .standard) async throws -> Int {
        guard HKHealthStore.isHealthDataAvailable(), start < end else {
            throw PersistenceDiagnostics.Failure(message: "Apple Health is unavailable or the date range is invalid.")
        }
        let health = HKHealthStore()
        let quantities: [(HKQuantityTypeIdentifier, HKUnit, String)] = [
            (.heartRate, HKUnit.count().unitDivided(by: .minute()), "bpm"),
            (.restingHeartRate, HKUnit.count().unitDivided(by: .minute()), "bpm"),
            (.heartRateVariabilitySDNN, .secondUnit(with: .milli), "ms SDNN"),
            (.respiratoryRate, HKUnit.count().unitDivided(by: .minute()), "breaths/min"),
            (.oxygenSaturation, .percent(), "%"), (.stepCount, .count(), "count"),
            (.activeEnergyBurned, .kilocalorie(), "kcal")]
        let quantityTypes = quantities.compactMap { HKObjectType.quantityType(forIdentifier: $0.0) }
        let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let workout = HKObjectType.workoutType()
        let types: [HKSampleType] = quantityTypes + [sleep, workout]
        try await health.requestAuthorization(toShare: [], read: Set(types.map { $0 as HKObjectType }))
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate])
        var imported: [Record] = []
        for type in types {
            let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
                health.execute(HKSampleQuery(sampleType: type, predicate: predicate,
                    limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, rows, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: rows ?? []) }
                })
            }
            for sample in samples {
                var values: [String: Double] = [:]
                var unit: String?
                if let quantity = sample as? HKQuantitySample,
                   let mapping = quantities.first(where: { $0.0.rawValue == type.identifier }) {
                    let value = quantity.quantity.doubleValue(for: mapping.1)
                    guard value.isFinite else { continue }
                    values["value"] = value
                    unit = mapping.2
                } else if let category = sample as? HKCategorySample {
                    values["categoryValue"] = Double(category.value)
                } else if let workout = sample as? HKWorkout {
                    values["activityType"] = Double(workout.workoutActivityType.rawValue)
                    values["durationSeconds"] = workout.duration
                    if let distance = workout.totalDistance { values["distanceMeters"] = distance.doubleValue(for: .meter()) }
                }
                imported.append(Record(id: sample.uuid, type: type.identifier,
                    sourceBundle: sample.sourceRevision.source.bundleIdentifier,
                    startUnix: sample.startDate.timeIntervalSince1970, endUnix: sample.endDate.timeIntervalSince1970,
                    timezone: sample.metadata?[HKMetadataKeyTimeZone] as? String, values: values, unit: unit))
            }
        }
        return try merge(imported, defaults: defaults)
    }

    /// Stable HealthKit UUID identity; existing original source records win.
    /// Cross-provider lookalikes require explicit shared identity, not time guesses.
    static func merge(_ imported: [Record], defaults: UserDefaults = .standard) throws -> Int {
        var existing = Dictionary(try load(defaults: defaults).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let before = existing.count
        for row in imported where existing[row.id] == nil { existing[row.id] = row }
        guard existing.count > before else { return 0 }
        let data = try JSONEncoder().encode(existing.values.sorted { $0.startUnix < $1.startUnix })
        defaults.set(data, forKey: key)
        return existing.count - before
    }
}
