import CoreLocation
import Foundation

/// Independent iPhone GPS workout recorder. Only accepted GPS fixes contribute
/// to distance; it does not infer GPS coordinates from WHOOP motion records.
final class GPSRunRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = GPSRunRecorder()
    @Published private(set) var recording = false
    @Published private(set) var paused = false
    @Published private(set) var distanceMeters = 0.0
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var splitSeconds: [Int] = []
    @Published private(set) var status = "Ready · iPhone GPS"
    @Published private(set) var route: [CLLocation] = []

    @Published private(set) var savedRuns: [GPSRunRecord] = []
    private let history = GPSRunHistory()
    private let manager = CLLocationManager()
    private var startTime: Date?
    private var activeSince: Date?
    private var accumulated = 0.0
    private var lastFix: CLLocation?
    private var nextSplitMeters = 1000.0
    private var lastSplitElapsed = 0

    override init() {
        super.init()
        savedRuns = history.all()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func start() {
        guard !recording else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            status = "Enable Location Services in iPhone Settings"
            return
        }
        manager.requestWhenInUseAuthorization()
        guard manager.authorizationStatus == .authorizedWhenInUse ||
              manager.authorizationStatus == .authorizedAlways else {
            status = "Allow location access, then tap Start again"
            return
        }
        distanceMeters = 0
        elapsedSeconds = 0
        splitSeconds = []
        route = []
        lastFix = nil
        accumulated = 0
        nextSplitMeters = 1000
        lastSplitElapsed = 0
        startTime = Date()
        activeSince = Date()
        recording = true
        paused = false
        status = "Recording · GPS accuracy filtered"
        manager.startUpdatingLocation()
    }

    func pause() {
        guard recording && !paused else { return }
        refreshElapsed()
        accumulated += Date().timeIntervalSince(activeSince ?? Date())
        activeSince = nil
        paused = true
        lastFix = nil
        manager.stopUpdatingLocation()
        status = "Paused"
    }

    func resume() {
        guard recording && paused else { return }
        paused = false
        activeSince = Date()
        lastFix = nil
        manager.startUpdatingLocation()
        status = "Recording"
    }

    func stop() {
        guard recording else { return }
        refreshElapsed()
        if !paused { accumulated += Date().timeIntervalSince(activeSince ?? Date()) }
        recording = false
        paused = false
        activeSince = nil
        lastFix = nil
        manager.stopUpdatingLocation()
        if let startedAt = startTime, distanceMeters >= 100, elapsedSeconds > 0 {
            let record = GPSRunRecord(
                id: UUID(), startedAt: startedAt, endedAt: Date(),
                movingSeconds: elapsedSeconds, distanceMeters: distanceMeters,
                splitSeconds: splitSeconds,
                route: route.map {
                    GPSRunPoint(latitude: $0.coordinate.latitude,
                                longitude: $0.coordinate.longitude,
                                unix: $0.timestamp.timeIntervalSince1970,
                                accuracyMeters: $0.horizontalAccuracy)
                }
            )
            guard history.save(record) else {
                status = "Run finished, but saving failed. Keep the app open and check device storage."
                return
            }
            savedRuns = history.all()
        }
        status = String(format: "Finished · %.2f km · %d seconds", distanceMeters / 1000, elapsedSeconds)
    }

    func deleteRun(id: UUID) {
        guard history.delete(id: id) else {
            status = "Could not delete saved run. Please try again."
            return
        }
        savedRuns = history.all()
    }

    func refreshElapsed() {
        guard recording else { return }
        let active = paused ? 0 : Date().timeIntervalSince(activeSince ?? Date())
        elapsedSeconds = Int((accumulated + active).rounded(.down))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            status = "Location permission denied"
            if recording { pause() }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard recording && !paused else { return }
        for fix in locations {
            guard fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= 30,
                  abs(fix.timestamp.timeIntervalSinceNow) <= 10,
                  fix.coordinate.latitude.isFinite, fix.coordinate.longitude.isFinite else { continue }
            if let previous = lastFix {
                let delta = fix.distance(from: previous)
                let seconds = fix.timestamp.timeIntervalSince(previous.timestamp)
                guard seconds > 0 else { continue }
                // Ignore GPS teleportation, rather than inflating pace or distance.
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
            lastFix = fix
            route.append(fix)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "GPS: \(error.localizedDescription)"
    }
}
