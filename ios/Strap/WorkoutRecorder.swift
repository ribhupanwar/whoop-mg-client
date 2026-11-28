import CoreLocation
import Foundation

/// Workout recorder supporting both GPS and non-GPS activities.
/// Uses iPhone GPS for outdoor activities; records HR and time for all activities.
final class WorkoutRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WorkoutRecorder()

    @Published private(set) var phase: WorkoutPhase = .idle
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var liveCalories: Int?
    @Published private(set) var liveActivityStrain: Double?
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var splitSeconds: [Int] = []
    @Published private(set) var status: String = "Ready"
    @Published private(set) var currentSession: WorkoutSession?
    @Published private(set) var route: [CLLocation] = []
    @Published private(set) var savedWorkouts: [WorkoutSession] = []

    private let history = WorkoutHistory()
    private let manager = CLLocationManager()
    private var startTime: Date?
    private var activeSince: Date?
    private var accumulated: TimeInterval = 0
    private var lastFix: CLLocation?
    private var nextSplitMeters: Double = 1000
    private var lastSplitElapsed: Int = 0
    private var currentActivityKind: ActivityKind = .run
    private var trackRoute: Bool = true
    private var gpsEnabled: Bool = false

    // Profile data for accurate calorie/HR/strain calculations
    private var profileWeightKg: Double?
    private var profileMaxHR: Double?
    private var profileRestingHR: Double?
    private var profileSex: Sex?
    private var profileHeightCm: Double?
    private var profileAge: Int?

    private var heartRateSamples: [Int] = []
    private var exportHeartRate: [WorkoutExportHeartRate] = []
    private var hrSampleCount: Int = 0
    private var energyTotal = 0.0
    private var activityTRIMP = 0.0
    private var lastEnergySample: (at: Date, bpm: Int)?

    override init() {
        super.init()
        savedWorkouts = history.all()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func updateProfile(weightKg: Double?, maxHR: Double?, restingHR: Double?, sex: Sex?, heightCm: Double?, age: Int?) {
        self.profileWeightKg = weightKg
        self.profileMaxHR = maxHR
        self.profileRestingHR = restingHR
        self.profileSex = sex
        self.profileHeightCm = heightCm
        self.profileAge = age
    }

    func start(activity: ActivityKind, trackRoute: Bool) {
        guard phase == .idle || phase == .discarded || phase == .saved else { return }

        currentActivityKind = activity
        self.trackRoute = trackRoute
        gpsEnabled = trackRoute && activitySupportsGPS(activity)

        // Reset state
        phase = .preparing
        elapsedSeconds = 0
        distanceMeters = 0
        splitSeconds = []
        route = []
        lastFix = nil
        accumulated = 0
        nextSplitMeters = 1000
        lastSplitElapsed = 0
        heartRateSamples = []
        exportHeartRate = []
        hrSampleCount = 0
        energyTotal = 0
        activityTRIMP = 0
        liveCalories = nil
        liveActivityStrain = nil
        lastEnergySample = nil

        startTime = Date()
        activeSince = Date()

        let session = WorkoutSession(
            id: UUID(),
            activityKind: activity.rawValue,
            activityLabel: activity.label,
            startedAt: startTime!,
            hasGPS: gpsEnabled
        )
        currentSession = session
        phase = .recording
        status = gpsEnabled ? "Recording · GPS accuracy filtered" : "Recording · No GPS"

        if gpsEnabled {
            guard CLLocationManager.locationServicesEnabled() else {
                status = "Enable Location Services in iPhone Settings"
                phase = .recording // Continue without GPS
                return
            }
            manager.requestWhenInUseAuthorization()
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            } else {
                status = "Location permission needed for GPS"
            }
        }
    }

    private func activitySupportsGPS(_ activity: ActivityKind) -> Bool {
        switch activity {
        case .run, .outdoorRun, .trailRun, .intervalRun,
             .walk, .hiking, .cycling, .mountainBiking,
             .crossCountrySkiing, .skiing, .snowboarding,
             .rowing, .sailing, .kayaking, .canoeing,
             .golf, .horsebackRiding, .mountaineering,
             .obstacleCourseRacing, .parkour:
            return true
        default:
            return false
        }
    }

    func pause() {
        guard phase == .recording else { return }
        refreshElapsed()
        accumulated += Date().timeIntervalSince(activeSince ?? Date())
        activeSince = nil
        phase = .paused
        breakEnergyInterval()
        lastFix = nil
        if gpsEnabled {
            manager.stopUpdatingLocation()
        }
        status = "Paused"
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .recording
        breakEnergyInterval()
        activeSince = Date()
        lastFix = nil
        if gpsEnabled {
            manager.startUpdatingLocation()
        }
        status = gpsEnabled ? "Recording" : "Recording · No GPS"
    }

    func stop(save: Bool = true) {
        guard phase == .recording || phase == .paused else { return }
        refreshElapsed()
        if phase == .recording {
            accumulated += Date().timeIntervalSince(activeSince ?? Date())
        }
        phase = save ? .saving : .discarded
        activeSince = nil
        lastFix = nil
        if gpsEnabled {
            manager.stopUpdatingLocation()
        }

        if save, var session = currentSession {
            session.endedAt = Date()
            session.phase = .saved
            session.metrics = WorkoutMetrics(
                elapsedSeconds: elapsedSeconds,
                distanceMeters: distanceMeters,
                averageHeartRate: averageHeartRate(),
                maximumHeartRate: maxHeartRate(),
                calories: liveCalories,
                activityStrain: liveActivityStrain,
                splits: buildSplits()
            )
            session.route = route.map { loc in
                WorkoutRoutePoint(
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude,
                    unix: loc.timestamp.timeIntervalSince1970,
                    accuracyMeters: loc.horizontalAccuracy,
                    heartRate: nil // HR is sampled separately
                )
            }
            session.exportHeartRate = exportHeartRate
            guard history.save(session) else {
                status = "Workout finished, but saving failed."
                phase = .recording
                return
            }
            savedWorkouts = history.all()
            currentSession = session
            phase = .saved
            status = String(format: "Saved · %.2f km · %d:%02d", distanceMeters / 1000, elapsedSeconds / 60, elapsedSeconds % 60)
        } else {
            currentSession = nil
            phase = .discarded
            status = "Discarded"
        }
    }

    func discard() {
        stop(save: false)
    }

    private func refreshElapsed() {
        guard phase == .recording else { return }
        let active = activeSince.map { Date().timeIntervalSince($0) } ?? 0
        elapsedSeconds = Int((accumulated + active).rounded(.down))
    }

    /// Refresh elapsed time for the workout screen and Live Activity bridge.
    func tick() {
        refreshElapsed()
    }

    /// Test-only helper to simulate elapsed time without waiting.
    func setElapsedForTesting(_ seconds: Int) {
        elapsedSeconds = seconds
        accumulated = TimeInterval(seconds)
        activeSince = Date()
    }

    func addHeartRateSample(_ hr: Int, observedAt: Date = Date()) {
        guard phase == .recording else { return }
        guard (35...220).contains(hr), observedAt.timeIntervalSinceReferenceDate.isFinite else {
            breakEnergyInterval()
            return
        }
        heartRateSamples.append(hr)
        // Keep observed timestamps separately; existing metrics remain unchanged.
        exportHeartRate.append(.init(unix: observedAt.timeIntervalSince1970, bpm: hr))
        hrSampleCount += 1
        // Never charge an interval through a pause, invalid reading or
        // long BLE gap. Use the same established Keytel/BMR/gate as the
        // analysis engine; accumulate only bounded observed intervals.
        if let previous = lastEnergySample {
            let delta = observedAt.timeIntervalSince(previous.at)
            guard delta > 0 else { return }
            // Same independent TRIMP scaling as the former saved-workout
            // estimator, but accumulated only across observed active intervals.
            if delta <= 30,
               let maximum = profileMaxHR, let resting = profileRestingHR,
               maximum.isFinite, resting.isFinite, resting > 0, maximum > resting {
                let reserve = min(1, max(0, (Double(previous.bpm) - resting) / (maximum - resting)))
                activityTRIMP += (delta / 60) * reserve * 0.64 * exp(1.92 * reserve)
                let strain = min(21, activityTRIMP / 10)
                if strain.isFinite, liveActivityStrain != strain { liveActivityStrain = strain }
            }
            if delta <= 30,
               let weight = profileWeightKg, let height = profileHeightCm,
               let age = profileAge, let sex = profileSex,
               let resting = profileRestingHR, let maximum = profileMaxHR,
               let bmr = Calories.bmrKcalPerDay(weightKg: weight, heightCm: height, age: Double(age), sex: sex),
               let gate = Calories.gateHR(restingHR: resting, maxHR: maximum) {
                let rate = Double(previous.bpm) >= gate
                    ? max(0, Calories.keytelKcalPerS(hr: Double(previous.bpm), maxHR: maximum,
                                                    weightKg: weight, age: Double(age), sex: sex) - bmr / 86400)
                    : 0
                energyTotal += rate * delta
                if energyTotal.isFinite, energyTotal < Double(Int32.max) {
                    let rounded = Int(energyTotal.rounded())
                    if liveCalories != rounded { liveCalories = rounded }
                }
            }
        }
        lastEnergySample = (observedAt, hr)
    }

    func breakEnergyInterval() {
        lastEnergySample = nil
    }

    private func averageHeartRate() -> Int? {
        guard !heartRateSamples.isEmpty else { return nil }
        return heartRateSamples.reduce(0, +) / heartRateSamples.count
    }

    private func maxHeartRate() -> Int? {
        guard !heartRateSamples.isEmpty else { return nil }
        return heartRateSamples.max()
    }

    private func buildSplits() -> [WorkoutSplit] {
        var splits: [WorkoutSplit] = []
        var currentSplitHR: [Int] = []
        var splitIndex = 1

        // This is simplified - real implementation would track per-km splits during GPS recording
        for (index, hr) in heartRateSamples.enumerated() {
            currentSplitHR.append(hr)
            // Rough estimate: every ~100 samples at 1Hz = ~1km for running
            if currentSplitHR.count >= 100 && distanceMeters >= Double(splitIndex) * 1000 {
                let avgSplitHR = currentSplitHR.reduce(0, +) / currentSplitHR.count
                splits.append(WorkoutSplit(
                    index: splitIndex,
                    distanceMeters: Double(splitIndex) * 1000,
                    elapsedSeconds: min(elapsedSeconds, index + 1),
                    averageHeartRate: avgSplitHR
                ))
                splitIndex += 1
                currentSplitHR = []
            }
        }
        return splits
    }

    func deleteWorkout(id: UUID) {
        guard history.delete(id: id) else {
            status = "Could not delete workout."
            return
        }
        savedWorkouts = history.all()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            status = "Location permission denied"
            if phase == .recording && gpsEnabled {
                // Don't pause the workout, just disable GPS
                gpsEnabled = false
                manager.stopUpdatingLocation()
            }
        } else if manager.authorizationStatus == .authorizedWhenInUse ||
                  manager.authorizationStatus == .authorizedAlways {
            if phase == .recording && trackRoute && activitySupportsGPS(currentActivityKind) && !gpsEnabled {
                gpsEnabled = true
                manager.startUpdatingLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard phase == .recording && gpsEnabled else { return }
        for fix in locations {
            guard fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= 30,
                  abs(fix.timestamp.timeIntervalSinceNow) <= 10,
                  fix.coordinate.latitude.isFinite, fix.coordinate.longitude.isFinite else { continue }
            if let previous = lastFix {
                let delta = fix.distance(from: previous)
                let seconds = fix.timestamp.timeIntervalSince(previous.timestamp)
                guard seconds > 0 else { continue }
                // Ignore GPS teleportation (8.5 m/s ≈ 30.6 km/h, above human sprint speed)
                guard delta / seconds <= 8.5 else {
                    lastFix = fix
                    continue
                }
                if delta >= 1 {
                    distanceMeters += delta
                    refreshElapsed()
                    while distanceMeters >= nextSplitMeters {
                        splitSeconds.append(max(0, elapsedSeconds - lastSplitElapsed))
                        lastSplitElapsed = elapsedSeconds
                        nextSplitMeters += 1000
                    }
                }
            }
            refreshElapsed()
            lastFix = fix
            route.append(fix)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if phase == .recording {
            status = "GPS: \(error.localizedDescription)"
        }
    }
}