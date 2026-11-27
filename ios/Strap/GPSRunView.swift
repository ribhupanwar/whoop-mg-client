import SwiftUI
import MapKit
import UIKit

struct GPSRunView: View {
    @ObservedObject private var recorder = WorkoutRecorder.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("strap.workout.keepScreenOn") private var keepScreenOn = false
    @State private var previousIdleTimer: Bool?
    @State private var workoutScreenVisible = false
    @EnvironmentObject private var store: AppStore
    @State private var selectedWorkout: WorkoutSession?
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var exporting = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @State private var showPicker = false
    @State private var search = ""
    @State private var activityCategory: ActivityPickerCategory = .all
    @State private var selectedActivity: ActivityKind = .run
    @State private var showStrain = false
    @AppStorage("strap.activityStrainTargetEnabled") private var strainTargetEnabled = false
    @State private var trackRoute = true
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showControls = false
    @State private var showDiscardConfirm = false
    @State private var workoutPage: WorkoutPage = .strain
    @State private var hrHistory: [HeartRateSample] = []

    private var canRecordGPS: Bool {
        switch selectedActivity {
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

    private var dayStrain: Double? {
        let key = JournalStore.dayKey(for: Date())
        let saved = store.band.days.first(where: { $0.dateKey == key })?.strain
        if store.band.liveDayStrainDateKey == key, let live = store.band.liveDayStrain {
            return max(live, saved ?? 0)
        }
        return saved
    }

    private func liveBPM(at date: Date) -> Int? {
        LiveHeartRateState.fresh(store.band.liveHeartRate, receivedAt: store.band.lastLiveHRAt,
                                 connected: store.band.isConnected, now: date)
    }

    private func updateHRHistory() {
        if let hr = liveBPM(at: Date()) {
            hrHistory.append(HeartRateSample(time: Date(), bpm: hr))
            // Keep last 30 minutes of samples
            let cutoff = Date().addingTimeInterval(-30 * 60)
            hrHistory.removeAll { $0.time < cutoff }
        }
    }

    private func export(_ workout: WorkoutSession, format: GPSRunExport.Format) {
        exporting = true; exportURL = nil; exportError = nil
        Task {
            defer { exporting = false }
            do {
                // Convert WorkoutSession to GPSRunRecord for export
                let record = GPSRunRecord(
                    id: workout.id,
                    startedAt: workout.startedAt,
                    endedAt: workout.endedAt ?? Date(),
                    movingSeconds: workout.metrics.elapsedSeconds,
                    distanceMeters: workout.metrics.distanceMeters,
                    splitSeconds: workout.metrics.splits.map { $0.elapsedSeconds },
                    route: workout.route.map {
                        GPSRunPoint(latitude: $0.latitude, longitude: $0.longitude,
                                   unix: $0.unix, accuracyMeters: $0.accuracyMeters)
                    }
                )
                exportURL = try await Task.detached { try GPSRunExport.write(record, format: format) }.value
            } catch { exportError = error.localizedDescription }
        }
    }

    var body: some View {
        Group {
            if recorder.phase == .idle || recorder.phase == .saved || recorder.phase == .discarded {
                prestartView
            } else {
                liveWorkoutView
            }
        }
        .navigationTitle((recorder.phase == .idle || recorder.phase == .saved || recorder.phase == .discarded) ? "Start Activity" : (recorder.currentSession?.activityLabel ?? selectedActivity.label))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { workoutScreenVisible = true; updateIdleTimer() }
        .onDisappear { workoutScreenVisible = false; restoreIdleTimer() }
        .onChange(of: scenePhase) { _, _ in updateIdleTimer() }
        .onChange(of: keepScreenOn) { _, _ in updateIdleTimer() }
        .onChange(of: recorder.phase) { _, _ in updateIdleTimer() }
        .onReceive(ticker) { _ in
            recorder.tick()
            updateHRHistory()
        }
    }

    private func updateIdleTimer() {
        if workoutScreenVisible && keepScreenOn && scenePhase == .active && recorder.phase == .recording {
            if previousIdleTimer == nil { previousIdleTimer = UIApplication.shared.isIdleTimerDisabled }
            UIApplication.shared.isIdleTimerDisabled = true
        } else {
            restoreIdleTimer()
        }
    }

    private func restoreIdleTimer() {
        guard let previousIdleTimer else { return }
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimer
        self.previousIdleTimer = nil
    }

    private var prestartView: some View {
        VStack(spacing: 0) {
            // Activity header with picker
            HStack(spacing: 16) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showPicker.toggle() }
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: selectedActivity.icon).font(.system(size: 28))
                        Text(selectedActivity.label.uppercased())
                            .font(.system(size: 19, weight: .bold)).tracking(2)
                        Spacer()
                        Image(systemName: showPicker ? "chevron.up" : "chevron.down")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("running.activityPicker")
            }
            .foregroundStyle(.white)
            .padding(24)
            .background(.black)

            if showPicker {
                ZStack {
                    Map(position: $mapPosition) { UserAnnotation() }
                        .allowsHitTesting(false)
                    Color.black.opacity(0.88)
                    VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 19))
                        TextField("Search", text: $search)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("running.activityPicker.search")
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(Color(white: 0.67), in: Capsule())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    HStack(spacing: 0) {
                        ForEach(ActivityPickerCategory.allCases) { category in
                            Button {
                                activityCategory = category
                            } label: {
                                VStack(spacing: 8) {
                                    Text(category.rawValue)
                                        .font(.system(size: 11, weight: .bold))
                                        .tracking(1.2)
                                    Rectangle()
                                        .fill(activityCategory == category ? Color.white : Color.clear)
                                        .frame(height: 2)
                                }
                                .foregroundStyle(activityCategory == category ? Color.white : Color.gray)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("running.activityPicker.category." + category.rawValue)
                            .accessibilityAddTraits(activityCategory == category ? .isSelected : [])
                        }
                    }
                    .padding(.top, 6)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            let matching = ActivityKind.allCases.filter { activity in
                                (search.isEmpty || activity.label.localizedCaseInsensitiveContains(search))
                                && activityCategory.includes(activity)
                            }
                            if matching.isEmpty {
                                Text("No matching activities")
                                    .foregroundStyle(.gray)
                                    .padding(20)
                                    .accessibilityIdentifier("running.activityPicker.empty")
                            }
                            if activityCategory == .all && search.isEmpty,
                               matching.contains(where: { $0 == selectedActivity }) {
                                Text("MOST RECENT")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundStyle(.gray)
                                    .padding(.horizontal, 24)
                                    .padding(.top, 18)
                                activityPickerRow(selectedActivity)
                                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                                    .padding(.horizontal, 12)
                                Text("ALL A–Z")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundStyle(.gray)
                                    .padding(.horizontal, 24)
                                    .padding(.top, 18)
                            }
                            if activityCategory == .recovery && search.isEmpty {
                                Text("ACTIVITIES TO SUPPORT RECOVERY")
                                    .font(StrapTypography.body(12))
                                    .foregroundStyle(.gray)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 18)
                                Text("OTHER ACTIVITIES")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundStyle(.gray)
                                    .padding(.horizontal, 24)
                                    .padding(.top, 10)
                            }
                            ForEach(matching.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }) { activity in
                                activityPickerRow(activity)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxHeight: .infinity)
                .background(Color.black)
                .foregroundStyle(.white)
                .accessibilityIdentifier("running.activityPicker.overlay")
            } else {
                ZStack {
                    Map(position: $mapPosition) {
                        UserAnnotation()
                    }
                    .mapControls { MapCompass() }
                    VStack {
                        HStack {
                            Spacer()
                            Toggle("TRACK ROUTE", isOn: $trackRoute)
                                .font(.system(size: 12, weight: .semibold))
                                .fixedSize()
                                .padding(12)
                                .background(.regularMaterial, in: Capsule())
                                .disabled(!canRecordGPS)
                                .accessibilityIdentifier("running.trackRouteToggle")
                        }
                        .padding(12)
                        Spacer()
                        Button {
                            mapPosition = .userLocation(fallback: .automatic)
                        } label: {
                            Image(systemName: "location.fill")
                                .padding(12)
                                .background(.regularMaterial, in: Circle())
                        }
                        .accessibilityIdentifier("running.recenterMap")
                        Circle()
                            .fill(Color(red: 0.07, green: 0.58, blue: 0.92).opacity(0.84))
                            .frame(width: 192, height: 192)
                            .overlay {
                                VStack(spacing: 10) {
                                    Image(systemName: "heart.fill").font(.system(size: 30))
                                    Text("READY").font(.system(size: 38, weight: .bold))
                                    Text(liveBPM(at: Date()).map { "\($0) BPM" } ?? "HR WAITING")
                                        .font(.system(size: 15, weight: .semibold))
                                    if let battery = store.band.batteryPercent {
                                        Label("\(Int(battery))%", systemImage: "battery.100percent")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.82))
                                    }
                                }
                                .foregroundStyle(.white)
                            }
                        Spacer()
                    }
                }
                .frame(maxHeight: .infinity)

                // Day Strain button
                Button { showStrain = true } label: {
                    HStack {
                        Text("DAY STRAIN").font(.system(size: 15, weight: .bold)).tracking(1)
                        Spacer()
                        Text(dayStrain.map { String(format: "%.1f", $0) } ?? "—")
                        Image(systemName: "chevron.right")
                    }
                    .padding(20)
                }
                .sheet(isPresented: $showStrain) {
                    strainTargetSheet
                }
                Toggle("STRAIN TARGET", isOn: $strainTargetEnabled)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1)
                    .tint(Color(red: 0.04, green: 0.60, blue: 0.94))
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("running.strainTargetToggle")

                // Activity-specific guidance
                if !canRecordGPS {
                    Text("GPS recording supports running, cycling, hiking, and outdoor activities. Other activities record heart rate and time only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                } else if !trackRoute {
                    Text("Enable Track Route to record GPS route for this outdoor activity.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                }

                // Start Activity button
                Button {
                    hrHistory.removeAll()
                    // Pass profile data for accurate calorie/HR/strain calculations
                    recorder.updateProfile(
                        weightKg: store.settings.weightKG,
                        maxHR: store.maxHeartRate,
                        restingHR: store.measuredRestingHR,
                        sex: store.settings.sex,
                        heightCm: store.settings.heightCM,
                        age: store.settings.profileAge().map { Int($0) }
                    )
                    recorder.start(activity: selectedActivity, trackRoute: trackRoute && canRecordGPS)
                } label: {
                    Text("START ACTIVITY")
                        .font(.system(size: 17, weight: .bold))
                        .tracking(2)
                        .frame(maxWidth: .infinity)
                        .padding(18)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.04, green: 0.60, blue: 0.94))
                .clipShape(Capsule())
                .padding(18)
                Text(recorder.status).font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
            }
        }
        .background(Color(.systemBackground))
    }

    private func activityPickerRow(_ activity: ActivityKind) -> some View {
        Button {
            selectedActivity = activity
            if !canRecordGPS { trackRoute = false }
            withAnimation(.easeInOut(duration: 0.2)) { showPicker = false }
        } label: {
            HStack(spacing: 18) {
                Image(systemName: activity.icon)
                    .font(.system(size: 24))
                    .frame(width: 42, height: 42)
                Text(activity.label.uppercased())
                    .font(.system(size: 14, weight: .bold))
                    .tracking(1.1)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 64)
            .padding(.horizontal, 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("running.activityPicker.item." + activity.rawValue)
    }

    private var strainTargetSheet: some View {
        VStack(spacing: 24) {
            // Drag handle
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            VStack(spacing: 16) {
                Text("STRAIN TARGET")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Large target ring — empty until validated formula exists
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 16)
                        .frame(width: 200, height: 200)
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("UNAVAILABLE")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Target requires validated formula")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }

                // Current metrics (day strain only — activity strain unknown pre-workout)
                VStack(spacing: 12) {
                    MetricCard(label: "DAY STRAIN", value: dayStrain.map { String(format: "%.1f", $0) } ?? "—")
                    MetricCard(label: "RECOVERY", value: "—")
                }

                Text("Recovery-based activity strain target is unavailable. No validated formula connects recovery to activity strain.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Button("Done") { showStrain = false }
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.04, green: 0.60, blue: 0.94))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(.horizontal, 40)
            }
            .padding(.horizontal, 20)
        }
        .presentationDetents([.medium, .large])
    }

    private var liveWorkoutView: some View {
        let currentHR = liveBPM(at: Date())

        return ZStack(alignment: .top) {
            // Three-page TabView
            TabView(selection: $workoutPage) {
                // PAGE 1: Activity Strain
                ActivityStrainPage(
                    elapsedSeconds: recorder.elapsedSeconds,
                    distanceMeters: recorder.distanceMeters,
                    currentHR: currentHR,
                    avgHR: recorder.currentSession?.metrics.averageHeartRate,
                    maxHR: recorder.currentSession?.metrics.maximumHeartRate,
                    calories: recorder.liveCalories,
                    activityStrain: recorder.currentSession?.metrics.activityStrain,
                    activityKind: selectedActivity,
                    isConnected: store.band.isConnected,
                    isPaused: recorder.phase == .paused,
                    bandBattery: store.band.batteryPercent
                )
                .tag(WorkoutPage.strain)

                // PAGE 2: Heart Rate
                HeartRatePage(
                    elapsedSeconds: recorder.elapsedSeconds,
                    currentHR: currentHR,
                    avgHR: recorder.currentSession?.metrics.averageHeartRate,
                    activityStrain: recorder.currentSession?.metrics.activityStrain,
                    calories: recorder.liveCalories,
                    hrHistory: hrHistory,
                    isConnected: store.band.isConnected,
                    isPaused: recorder.phase == .paused,
                    maxHR: store.maxHeartRate,
                    restingHR: store.measuredRestingHR
                )
                .tag(WorkoutPage.heartRate)

                // PAGE 3: Map
                MapPage(
                    elapsedSeconds: recorder.elapsedSeconds,
                    distanceMeters: recorder.distanceMeters,
                    pace: currentPace,
                    route: recorder.route,
                    mapPosition: $mapPosition,
                    hasGPS: recorder.currentSession?.hasGPS ?? false,
                    isPaused: recorder.phase == .paused
                )
                .tag(WorkoutPage.map)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Only the actual header overlays the pages. Keep its button
            // tappable; the rest of the TabView remains available for swipes.
            TimerHeader(
                elapsedSeconds: recorder.elapsedSeconds,
                currentHR: currentHR,
                activityLabel: selectedActivity.label,
                activityIcon: selectedActivity.icon,
                isPaused: recorder.phase == .paused,
                onTap: { showControls = true }
            )
            .padding(.top, 8)
            .padding(.horizontal, 16)
        }
        .confirmationDialog("Workout Controls", isPresented: $showControls, titleVisibility: .visible) {
            if recorder.phase == .recording {
                Button("Pause", role: .none) { recorder.pause() }
            } else if recorder.phase == .paused {
                Button("Resume", role: .none) { recorder.resume() }
            }
            Button("End & Save", role: .none) { recorder.stop(save: true) }
            Button("Discard", role: .destructive) { showDiscardConfirm = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(recorder.phase == .paused ? "Workout paused" : "Workout in progress")
        }
        .confirmationDialog("Discard Workout?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { recorder.discard() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete the current workout. This action cannot be undone.")
        }
        .onAppear {
            // WorkoutRecorder handles phase transitions; UI observes only.
            // If we reach a terminal state, the recorder will stay there until start() is called.
        }
    }

    private var currentPace: String? {
        guard recorder.distanceMeters >= 100, recorder.elapsedSeconds > 0 else { return nil }
        let pace = Double(recorder.elapsedSeconds) / (recorder.distanceMeters / 1000)
        return String(format: "%d:%02d /km", Int(pace) / 60, Int(pace) % 60)
    }
}

// MARK: - Supporting Views

enum WorkoutPage: Hashable {
    case strain, heartRate, map
}

struct HeartRateSample: Identifiable {
    let id = UUID()
    let time: Date
    let bpm: Int
}

struct MetricCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TimerHeader: View {
    let elapsedSeconds: Int
    let currentHR: Int?
    let activityLabel: String
    let activityIcon: String
    let isPaused: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: activityIcon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(red: 0.04, green: 0.60, blue: 0.94))
                Text(activityLabel.uppercased())
                    .font(.system(size: 14, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.primary)
                Spacer()
                if let hr = currentHR {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 14))
                        Text("\(hr) BPM")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                } else {
                    Text("HR —")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(formatTime(elapsedSeconds))
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(width: 70, alignment: .trailing)
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workout.timerHeader")
    }

    private func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

// PAGE 1: Activity Strain
struct ActivityStrainPage: View {
    let elapsedSeconds: Int
    let distanceMeters: Double
    let currentHR: Int?
    let avgHR: Int?
    let maxHR: Int?
    let calories: Int?
    let activityStrain: Double?
    let activityKind: ActivityKind
    let isConnected: Bool
    let isPaused: Bool
    let bandBattery: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Strain Ring
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 18)
                        .frame(width: 240, height: 240)
                    if let strain = activityStrain {
                        Circle()
                            .trim(from: 0, to: min(strain / 21.0, 1.0))
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.04, green: 0.60, blue: 0.94),
                                        Color(red: 0.07, green: 0.80, blue: 0.92)
                                    ]),
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 18, lineCap: .round)
                            )
                            .frame(width: 240, height: 240)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 1.0), value: strain)
                    }
                    VStack(spacing: 8) {
                        Image(systemName: activityKind.icon)
                            .font(.system(size: 36))
                            .foregroundStyle(Color(red: 0.04, green: 0.60, blue: 0.94))
                        Text(activityStrain.map { String(format: "%.1f", $0) } ?? "—")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("ACTIVITY STRAIN")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 20)

                // Metrics Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    WorkoutMetric(
                        label: "AVG HR",
                        value: avgHR.map { "\($0) BPM" } ?? "—",
                        icon: "heart.fill",
                        color: .red
                    )
                    WorkoutMetric(
                        label: "MAX HR",
                        value: maxHR.map { "\($0) BPM" } ?? "—",
                        icon: "bolt.heart.fill",
                        color: .orange
                    )
                    WorkoutMetric(
                        label: "CALORIES",
                        value: calories.map { "\($0) kcal" } ?? "—",
                        icon: "flame.fill",
                        color: .orange
                    )
                    WorkoutMetric(
                        label: "DISTANCE",
                        value: distanceMeters >= 100 ? String(format: "%.2f km", distanceMeters / 1000) : "—",
                        icon: "location.fill",
                        color: .blue
                    )
                }
                .padding(.horizontal, 20)

                // Band status
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(isConnected ? "WHOOP CONNECTED" : "BAND DISCONNECTED")
                            .font(.system(size: 11, weight: .medium))
                    }
                    if let battery = bandBattery {
                        HStack(spacing: 4) {
                            Image(systemName: "battery.100")
                            Text("\(battery)%")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    Spacer()
                    if isPaused {
                        Text("PAUSED")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

                Spacer(minLength: 100)
            }
        }
        .background(Color(.systemBackground))
    }
}

struct WorkoutMetric: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

// PAGE 2: Heart Rate
struct HeartRatePage: View {
    let elapsedSeconds: Int
    let currentHR: Int?
    let avgHR: Int?
    let activityStrain: Double?
    let calories: Int?
    let hrHistory: [HeartRateSample]
    let isConnected: Bool
    let isPaused: Bool
    let maxHR: Double?
    let restingHR: Double?

    private var hrZone: HeartRateZone? {
        guard let hr = currentHR,
              let maxHR = maxHR,
              let restingHR = restingHR else { return nil }
        return HeartRateZone.zone(for: hr, maxHR: maxHR, restingHR: restingHR)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Large HR display
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 12)
                        .frame(width: 200, height: 200)
                    if let zone = hrZone {
                        Circle()
                            .trim(from: 0, to: 0.75)
                            .stroke(zone.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .frame(width: 200, height: 200)
                            .rotationEffect(.degrees(-135))
                    }
                    VStack(spacing: 4) {
                        Text(currentHR.map { "\($0)" } ?? "—")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("BPM")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        if let zone = hrZone {
                            Text(zone.rawValue)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(zone.color)
                        }
                    }
                }
                .padding(.top, 20)

                // HR Zone strip
                HRZoneStrip(currentZone: hrZone)
                    .padding(.horizontal, 20)

                // HR Trend Chart
                if hrHistory.count > 1 {
                    HRTrendChart(samples: hrHistory)
                        .frame(height: 160)
                        .padding(.horizontal, 20)
                }

                // Metrics
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    WorkoutMetric(
                        label: "AVG HR",
                        value: avgHR.map { "\($0) BPM" } ?? "—",
                        icon: "heart.fill",
                        color: .red
                    )
                    WorkoutMetric(
                        label: "ACTIVITY STRAIN",
                        value: activityStrain.map { String(format: "%.1f", $0) } ?? "—",
                        icon: "chart.xyaxis.line",
                        color: .blue
                    )
                    WorkoutMetric(
                        label: "CALORIES",
                        value: calories.map { "\($0) kcal" } ?? "—",
                        icon: "flame.fill",
                        color: .orange
                    )
                    WorkoutMetric(
                        label: "DURATION",
                        value: formatTime(elapsedSeconds),
                        icon: "clock.fill",
                        color: .blue
                    )
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 100)
            }
        }
        .background(Color(.systemBackground))
    }

    private func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

enum HeartRateZone: String, CaseIterable {
    case recovery = "Recovery"
    case aerobic = "Aerobic"
    case tempo = "Tempo"
    case threshold = "Threshold"
    case vo2max = "VO₂ Max"

    var color: Color {
        switch self {
        case .recovery: return .blue
        case .aerobic: return .green
        case .tempo: return .yellow
        case .threshold: return .orange
        case .vo2max: return .red
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .recovery: return 0...114    // < 60% max
        case .aerobic: return 115...133   // 60-70%
        case .tempo: return 134...152     // 70-80%
        case .threshold: return 153...171 // 80-90%
        case .vo2max: return 172...220    // 90-100%
        }
    }

    static func zone(for hr: Int, maxHR: Double = 190, restingHR: Double = 60) -> HeartRateZone? {
        let hrr = (Double(hr) - restingHR) / (maxHR - restingHR)
        switch hrr {
        case ..<0.60: return .recovery
        case 0.60..<0.70: return .aerobic
        case 0.70..<0.80: return .tempo
        case 0.80..<0.90: return .threshold
        case 0.90...1.0: return .vo2max
        default: return nil
        }
    }
}

struct HRZoneStrip: View {
    let currentZone: HeartRateZone?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HeartRateZone.allCases, id: \.self) { zone in
                Rectangle()
                    .fill(zone.color.opacity(currentZone == zone ? 1.0 : 0.3))
                    .frame(height: 8)
                    .overlay(
                        Text(zone.rawValue.prefix(3))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(currentZone == zone ? .white : .clear)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct HRTrendChart: View {
    let samples: [HeartRateSample]

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let validSamples = samples.suffix(1800) // Last 30 minutes

            if validSamples.count < 2 {
                Rectangle().fill(Color.clear)
            } else {
                let minHR = validSamples.map(\.bpm).min() ?? 40
                let maxHR = validSamples.map(\.bpm).max() ?? 200
                let hrRange = max(40, maxHR - minHR)

                Path { path in
                    for (index, sample) in validSamples.enumerated() {
                        let x = width * CGFloat(index) / CGFloat(validSamples.count - 1)
                        let y = height * (1 - CGFloat(sample.bpm - minHR) / CGFloat(hrRange))
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [Color(red: 0.04, green: 0.60, blue: 0.94), Color(red: 0.07, green: 0.80, blue: 0.92)],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// PAGE 3: Map
struct MapPage: View {
    let elapsedSeconds: Int
    let distanceMeters: Double
    let pace: String?
    let route: [CLLocation]
    @Binding var mapPosition: MapCameraPosition
    let hasGPS: Bool
    let isPaused: Bool

    var body: some View {
        ZStack {
            if hasGPS && route.count >= 2 {
                Map(position: $mapPosition) {
                    MapPolyline(coordinates: route.map { $0.coordinate })
                        .stroke(Color(red: 0.04, green: 0.60, blue: 0.94), lineWidth: 4)
                    UserAnnotation()
                }
                .mapControls { MapCompass() }
            } else {
                // No GPS or insufficient route points
                VStack(spacing: 16) {
                    Image(systemName: hasGPS ? "location.slash" : "map")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(hasGPS ? "Recording route..." : "GPS Disabled")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Route will appear when GPS fixes are available")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }

            // Stats overlay
            VStack {
                Spacer()
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DISTANCE")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                        Text(distanceMeters >= 100 ? String(format: "%.2f km", distanceMeters / 1000) : "—")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PACE")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                        Text(pace ?? "—")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DURATION")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                        Text(formatTime(elapsedSeconds))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
                .padding(.bottom, 20)

                // Recenter button
                Button {
                    if hasGPS {
                        mapPosition = .userLocation(fallback: .automatic)
                    }
                } label: {
                    Image(systemName: "location.fill")
                        .padding(12)
                        .background(.regularMaterial, in: Circle())
                }
                .disabled(!hasGPS)
                .padding(.bottom, 20)
                .accessibilityIdentifier("running.recenterMap")
            }
        }
        .background(Color(.systemBackground))
    }

    private func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
enum ActivityPickerCategory: String, CaseIterable, Identifiable {
    case all = "ALL"
    case strain = "STRAIN"
    case recovery = "RECOVERY"
    case sleep = "SLEEP"

    var id: String { rawValue }

    private static let recoveryLabels: Set<String> = [
        "acupuncture", "air compression", "air compression (normatec)",
        "breathwork", "bright light therapy", "chiropractor", "cold shower",
        "contrast therapy", "ice bath", "massage", "meditation", "sauna",
        "stretching", "yoga", "breathing", "relaxation", "recovery"
    ]

    func includes(_ activity: ActivityKind) -> Bool {
        let name = activity.label.lowercased()
        switch self {
        case .all: return true
        case .sleep:
            return name == "sleep" || name == "nap"
        case .recovery:
            // Explicit, reviewable labels: do not classify activities by substring.
            return Self.recoveryLabels.contains(name)
        case .strain:
            return !Self.sleep.includes(activity) && !Self.recovery.includes(activity)
        }
    }
}