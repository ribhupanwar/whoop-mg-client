import Combine
import CoreLocation
import Foundation
import HealthKit

/// Optional Apple Health workout export and user-initiated profile import.
///
/// Currently only sessions the band actually measured are written, as workouts with
/// their real start and end. No estimate (VO2 max,
/// SpO2 candidate, calories) is written, and every workout carries an
/// external UUID built from its start second so a replayed drain cannot
/// duplicate it in Health.
final class HealthKitBridge: ObservableObject {
    enum State: Equatable {
        case off
        case unavailable
        case denied
        case ready
        case failed(String)

        var text: String {
            switch self {
            case .off: return "Off — nothing is written to Health"
            case .unavailable: return "HealthKit is not available on this device"
            case .denied: return "Write access was declined in the Health app"
            case .ready: return "On — workouts export; other health categories authorized separately"
            case .failed(let message): return "Not enabled — \(message)"
            }
        }

        var isOn: Bool { self == .ready }
    }

    @Published private(set) var state: State = .off

    /// Marks the records this app created, so the user can tell them apart.
    static let sourceKey = "com.ribhupanwar.strap.source"

    static let detectedSource = "strap-band"
    var isDetectedActivityDeleted: (ActivitySession) -> Bool = { _ in false }

    private let store = HKHealthStore()

    /// Permissions for supported Health categories. Authorization does not
    /// itself publish values: each metric needs its own validated export path.
    /// In particular, candidate SpO2 and inferred VO2 max are not auto-written.
    private var shareTypes: Set<HKSampleType> {
        let types: [HKSampleType?] = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .respiratoryRate),
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation),
            HKObjectType.quantityType(forIdentifier: .vo2Max),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        ]
        return Set(types.compactMap { $0 })
    }

    private var readTypes: Set<HKObjectType> {
        Set(shareTypes.map { $0 as HKObjectType })
    }

    @MainActor
    func importProfile() async throws -> AppleHealthProfile {
        guard HKHealthStore.isHealthDataAvailable() else { return AppleHealthProfile() }
        let quantities = [.height, .bodyMass, .leanBodyMass] as [HKQuantityTypeIdentifier]
        let metrics = quantities.compactMap { HKObjectType.quantityType(forIdentifier: $0) }
        let characteristics = [HKCharacteristicTypeIdentifier.dateOfBirth, .biologicalSex]
            .compactMap { HKObjectType.characteristicType(forIdentifier: $0) }
        var read = Set<HKObjectType>()
        metrics.forEach { read.insert($0) }
        characteristics.forEach { read.insert($0) }
        try await store.requestAuthorization(toShare: [], read: read)

        let biological = try? store.biologicalSex().biologicalSex
        let sex: Sex? = biological == .male ? .male : (biological == .female ? .female : nil)
        let birth = (try? store.dateOfBirthComponents()).map { ProfileBirthDate($0) }
        let height = await latestProfileSample(.height)?.quantity.doubleValue(for: .meterUnit(with: .centi))
        let weight = await latestProfileSample(.bodyMass)?.quantity.doubleValue(for: .gramUnit(with: .kilo))
        let lean = await latestProfileSample(.leanBodyMass).flatMap { sample -> ProfileBodyMeasurement? in
            let kilograms = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            guard kilograms.isFinite, kilograms > 0 else { return nil }
            return ProfileBodyMeasurement(kilograms: kilograms, date: sample.endDate,
                                          source: sample.sourceRevision.source.name)
        }
        return AppleHealthProfile(
            birthDate: birth.flatMap { $0.age(on: Date()) == nil ? nil : $0 }, sex: sex,
            heightCM: height.flatMap { (100...250).contains($0) ? $0 : nil },
            weightKG: weight.flatMap { (30...300).contains($0) ? $0 : nil }, leanMass: lean)
    }

    private func latestProfileSample(_ identifier: HKQuantityTypeIdentifier) async -> HKQuantitySample? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let date = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: Date(), options: .strictEndDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [date]) {
                _, samples, _ in
                continuation.resume(returning: samples?.first as? HKQuantitySample)
            }
            store.execute(query)
        }
    }

    /// Stable across drains and relaunches: the session's first second.
    static func externalID(startUnix: Int) -> String {
        "strap-session-\(startUnix)"
    }

    /// Gait labels map to the matching Health workout type; an HR-only
    /// session is "other" because the band did not say what it was.
    static func activityType(for kind: String) -> HKWorkoutActivityType {
        switch kind.lowercased() {
        case "run": return .running
        case "walk": return .walking
        case "lift": return .traditionalStrengthTraining
        default: return .other
        }
    }

    @MainActor
    func activate() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return
        }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            state = store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
                ? .ready
                : .denied
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    @MainActor
    func deactivate() {
        state = .off
    }

    @MainActor
    func export(_ sessions: [ActivitySession]) async {
        guard state == .ready else { return }
        // Multiple sync passes may return the same workout in one batch.
        var seen = Set<Int>()
        for session in sessions.sorted(by: { $0.startUnix < $1.startUnix }) {
            guard seen.insert(session.startUnix).inserted else { continue }
            await export(session)
        }
    }

    @MainActor
    func export(_ session: ActivitySession) async {
        guard state == .ready, session.endUnix > session.startUnix,
              !isDetectedActivityDeleted(session) else { return }
        let id = Self.externalID(startUnix: session.startUnix)
        guard let alreadySaved = await exists(id), !alreadySaved,
              !isDetectedActivityDeleted(session) else { return }
        let start = Date(timeIntervalSince1970: TimeInterval(session.startUnix))
        let end = Date(timeIntervalSince1970: TimeInterval(session.endUnix + 1))
        var metadata: [String: Any] = [
            HKMetadataKeyExternalUUID: id,
            Self.sourceKey: Self.detectedSource
        ]
        if session.steps > 0 {
            metadata["com.ribhupanwar.strap.steps"] = session.steps
        }
        if let meanHR = session.meanHR {
            metadata["com.ribhupanwar.strap.meanHR"] = Int(meanHR.rounded())
        }
        await save(start: start, end: end, type: Self.activityType(for: session.kind), metadata: metadata)
        if isDetectedActivityDeleted(session) {
            await deleteDetectedWorkouts(startTimes: [session.startUnix])
        }
    }

    static func detectedWorkoutDeletionPredicate(startTimes: [Int], sourcePredicate: NSPredicate) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            sourcePredicate,
            HKQuery.predicateForObjects(withMetadataKey: sourceKey, operatorType: .equalTo,
                                        value: detectedSource),
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID,
                                        allowedValues: startTimes.map { externalID(startUnix: $0) })
        ])
    }

    @MainActor
    func deleteDetectedWorkouts(startTimes: [Int]) async {
        guard state == .ready, !startTimes.isEmpty, Bundle.main.bundleIdentifier != nil else { return }
        let sourcePredicate = HKQuery.predicateForObjects(from: HKSource.default())
        let predicate = Self.detectedWorkoutDeletionPredicate(startTimes: startTimes, sourcePredicate: sourcePredicate)
        let error = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            store.deleteObjects(of: HKObjectType.workoutType(), predicate: predicate) { success, _, error in
                continuation.resume(returning: success ? nil : (error?.localizedDescription ?? "Workout could not be removed from Apple Health."))
            }
        }
        if let error, state == .ready { state = .failed(error) }
    }

    @MainActor
    func export(live record: LiveActivityRecord) async {
        guard state == .ready else { return }
        let id = Self.externalID(startUnix: record.startedUnix)
        guard let alreadySaved = await exists(id), !alreadySaved else { return }
        let start = Date(timeIntervalSince1970: TimeInterval(record.startedUnix))
        let end = Date(timeIntervalSince1970: TimeInterval(record.endedUnix))
        guard end > start else { return }
        var metadata: [String: Any] = [
            HKMetadataKeyExternalUUID: id,
            Self.sourceKey: "strap-live"
        ]
        if let meanHR = record.meanHR {
            metadata["com.ribhupanwar.strap.meanHR"] = Int(meanHR.rounded())
        }
        // Live records do not currently preserve a verified sport classification.
        // Export as .other rather than mislabeling them as runs for WHOOP/Strava.
        await save(start: start, end: end, type: .other, metadata: metadata)
    }

    @MainActor
    private func save(
        start: Date,
        end: Date,
        type: HKWorkoutActivityType,
        metadata: [String: Any]
    ) async {
        guard end > start else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = type
        configuration.locationType = .unknown
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.addMetadata(metadata)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Health has no built-in dedupe, so the external UUID is queried first.
    private func exists(_ id: String) async -> Bool? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            let predicate = HKQuery.predicateForObjects(
                withMetadataKey: HKMetadataKeyExternalUUID,
                operatorType: .equalTo,
                value: id
            )
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                continuation.resume(returning: error == nil ? samples?.isEmpty == false : nil)
            }
            store.execute(query)
        }
    }
}


/// Opt-in runner relay, independent of the existing band summary exporter.
@MainActor
final class RecordedRunHealthRelay: ObservableObject {
    static let shared = RecordedRunHealthRelay()
    static let enabledKey = "strap.strava.recordedRunRelay"
    @Published private(set) var status = "Not connected"
    @Published private(set) var busy = false
    private let health = HKHealthStore()
    private let defaults = UserDefaults.standard
    private let completedKey = "strap.strava.healthRelayCompleted"
    private let partialKey = "strap.strava.healthRelayPartial"

    static func activityType(_ kind: String) -> HKWorkoutActivityType? {
        let value = kind.lowercased()
        if value.contains("run") || value.contains("treadmill") { return .running }
        if value.contains("walk") { return .walking }
        if value.contains("cycl") || value.contains("bik") { return .cycling }
        return nil
    }

    private var types: Set<HKSampleType> {
        var result: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        for id: HKQuantityTypeIdentifier in [.heartRate, .distanceWalkingRunning, .distanceCycling] {
            if let type = HKObjectType.quantityType(forIdentifier: id) { result.insert(type) }
        }
        return result
    }

    func authorize() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(), !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            try await health.requestAuthorization(toShare: types, read: Set(types.map { $0 as HKObjectType }))
            let allowed = types.allSatisfy { health.authorizationStatus(for: $0) == .sharingAuthorized }
            status = allowed ? "Apple Health write access ready · connect WorkoutPort separately" :
                "Allow workouts, routes, heart rate and distance in Apple Health"
            return allowed
        } catch {
            status = error.localizedDescription
            return false
        }
    }

    private func workouts(_ predicate: NSPredicate) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [HKWorkout] ?? []) }
            }
            health.execute(query)
        }
    }

    private func mark(_ id: String, key: String) {
        var ids = Set(defaults.stringArray(forKey: key) ?? [])
        ids.insert(id)
        defaults.set(ids.sorted(), forKey: key)
    }

    func export(_ session: WorkoutSession) async {
        guard defaults.bool(forKey: Self.enabledKey), !busy else { return }
        guard session.phase == .saved, let end = session.endedAt, end > session.startedAt,
              let type = Self.activityType(session.activityKind) else {
            status = "Select a saved running, walking or cycling workout."
            return
        }
        let id = "strap-recorded-\(session.id.uuidString)"
        guard !(defaults.stringArray(forKey: completedKey) ?? []).contains(id) else {
            status = "Already exported to Apple Health. Check WorkoutPort for Strava status."
            return
        }
        guard !(defaults.stringArray(forKey: partialKey) ?? []).contains(id) else {
            status = "Workout may already exist in Health with an incomplete route. Check Health or use TCX; automatic retry blocked to prevent duplicates."
            return
        }
        guard types.allSatisfy({ health.authorizationStatus(for: $0) == .sharingAuthorized }) else {
            status = "Apple Health permissions required."
            return
        }
        busy = true
        defer { busy = false }
        do {
            // Conservative conflict handling: never replace an existing workout.
            // An overlapping STRAP or watch workout may already have synced.
            let predicate = HKQuery.predicateForSamples(withStart: session.startedAt, end: end, options: [])
            let existing = try await workouts(predicate)
            guard !existing.contains(where: { $0.startDate < end && session.startedAt < $0.endDate }) else {
                status = "Overlapping Health workout exists. Skipped to prevent duplicate Strava uploads; use TCX only if not already synced."
                return
            }
            let start = session.startedAt.timeIntervalSince1970
            let finish = end.timeIntervalSince1970
            var seenRoute = Set<Double>()
            let locations = session.route.sorted { $0.unix < $1.unix }.compactMap { p -> CLLocation? in
                guard p.unix.isFinite, (start...finish).contains(p.unix),
                      p.latitude.isFinite, (-90...90).contains(p.latitude),
                      p.longitude.isFinite, (-180...180).contains(p.longitude),
                      p.accuracyMeters.isFinite, p.accuracyMeters >= 0,
                      seenRoute.insert(p.unix).inserted else { return nil }
                return CLLocation(coordinate: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude),
                                  altitude: 0, horizontalAccuracy: p.accuracyMeters, verticalAccuracy: -1,
                                  timestamp: Date(timeIntervalSince1970: p.unix))
            }
            var routeBuilder: HKWorkoutRouteBuilder?
            if locations.count >= 2 {
                let route = HKWorkoutRouteBuilder(healthStore: health, device: .local())
                for offset in stride(from: 0, to: locations.count, by: 500) {
                    try await route.insertRouteData(Array(locations[offset..<min(offset + 500, locations.count)]))
                }
                routeBuilder = route
            }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = type
            configuration.locationType = session.hasGPS ? .outdoor : .unknown
            let builder = HKWorkoutBuilder(healthStore: health, configuration: configuration, device: .local())
            try await builder.beginCollection(at: session.startedAt)
            try await builder.addMetadata([
                HKMetadataKeyExternalUUID: id,
                HKMetadataKeySyncIdentifier: id,
                HKMetadataKeySyncVersion: 1,
                HealthKitBridge.sourceKey: "strap-recorded",
                "com.ribhupanwar.strap.activeSeconds": session.metrics.elapsedSeconds
            ])
            var samples: [HKSample] = []
            if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
                var seenHR = Set<Double>()
                let unit = HKUnit.count().unitDivided(by: .minute())
                for hr in (session.exportHeartRate ?? []).sorted(by: { $0.unix < $1.unix }) where
                    hr.unix.isFinite && (start...finish).contains(hr.unix) &&
                    (35...220).contains(hr.bpm) && seenHR.insert(hr.unix).inserted {
                    let date = Date(timeIntervalSince1970: hr.unix)
                    samples.append(HKQuantitySample(type: hrType, quantity: HKQuantity(unit: unit, doubleValue: Double(hr.bpm)), start: date, end: date))
                }
            }
            let distanceID: HKQuantityTypeIdentifier = type == .cycling ? .distanceCycling : .distanceWalkingRunning
            if session.metrics.distanceMeters.isFinite, session.metrics.distanceMeters > 0,
               let distanceType = HKObjectType.quantityType(forIdentifier: distanceID) {
                samples.append(HKQuantitySample(type: distanceType,
                    quantity: HKQuantity(unit: .meter(), doubleValue: session.metrics.distanceMeters),
                    start: session.startedAt, end: end))
            }
            for offset in stride(from: 0, to: samples.count, by: 500) {
                try await builder.add(Array(samples[offset..<min(offset + 500, samples.count)]))
            }
            let pauses = (session.exportPauses ?? []).filter {
                $0.start >= session.startedAt && $0.end <= end && $0.end > $0.start
            }.sorted { $0.start < $1.start }
            let events = pauses.flatMap { pause in
                [HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: pause.start, duration: 0), metadata: nil),
                 HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: pause.end, duration: 0), metadata: nil)]
            }
            if !events.isEmpty {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    builder.addWorkoutEvents(events) { success, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if success {
                            continuation.resume(returning: ())
                        } else {
                            continuation.resume(throwing: NSError(
                                domain: "Strap.HealthKitBridge", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Could not add workout pause events"]
                            ))
                        }
                    }
                }
            }
            try await builder.endCollection(at: end)
            guard defaults.bool(forKey: Self.enabledKey) else { builder.discardWorkout(); return }
            // Record attempted finalization before committing; a locked device
            // can save successfully yet return no workout. Never blindly retry.
            mark(id, key: partialKey)
            guard let workout = try await builder.finishWorkout() else {
                status = "Workout may be saved while device is locked. Check Apple Health before retrying."
                return
            }
            if let routeBuilder {
                _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
            }
            mark(id, key: completedKey)
            status = "Saved to Apple Health · \(locations.count) GPS points · check WorkoutPort for Strava delivery"
        } catch {
            status = "Health export incomplete: \(error.localizedDescription). Local workout retained; check Health before retry."
        }
    }
}
