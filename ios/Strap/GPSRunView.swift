import SwiftUI
import MapKit

struct GPSRunView: View {
    @ObservedObject private var gps = GPSRunRecorder.shared
    @EnvironmentObject private var store: AppStore
    @State private var selectedRun: GPSRunRecord?
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var exporting = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private func export(_ run: GPSRunRecord, format: GPSRunExport.Format) {
        exporting = true; exportURL = nil; exportError = nil
        Task {
            defer { exporting = false }
            do { exportURL = try await Task.detached { try GPSRunExport.write(run, format: format) }.value }
            catch { exportError = error.localizedDescription }
        }
    }

    @State private var workoutStarted = false
    @State private var showPicker = false
    @State private var search = ""
    @State private var selectedActivity: ActivityKind = ActivityKind.allCases.first!
    @State private var showStrain = false
    private var dayStrain: Double? {
        let key = JournalStore.dayKey(for: Date())
        let saved = store.band.days.first(where: { $0.dateKey == key })?.strain
        if let live = store.band.liveDayStrain { return max(live, saved ?? 0) }
        return saved
    }

    private func liveBPM(at date: Date) -> Int? {
        LiveHeartRateState.fresh(store.band.liveHeartRate, receivedAt: store.band.lastLiveHRAt,
                                 connected: store.band.isConnected, now: date)
    }

    var body: some View {
        Group {
        if !gps.recording && !workoutStarted {
            runningPrestart
        } else {
        Screen {
            VStack(alignment: .leading, spacing: 12) {
                Panel {
                    SectionTitle("Outdoor GPS run")
                    Text(String(format: "%.2f km", gps.distanceMeters / 1000))
                        .font(StrapTypography.body(40, weight: .bold))
                        .foregroundStyle(Color.appFG)
                    Text("Elapsed: \(gps.elapsedSeconds / 60)m \(gps.elapsedSeconds % 60)s")
                        .foregroundStyle(Color.appMuted)
                    if gps.distanceMeters >= 100 && gps.elapsedSeconds > 0 {
                        let pace = Double(gps.elapsedSeconds) / (gps.distanceMeters / 1000)
                        Text(String(format: "Average pace %d:%02d /km", Int(pace) / 60, Int(pace) % 60))
                            .foregroundStyle(Color.appFG)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill").foregroundStyle(.red)
                        Text(liveBPM(at: Date()).map { "\($0) BPM" } ?? "HR —")
                            .font(StrapTypography.metric(25, weight: .bold))
                        Spacer()
                        Text(store.band.isConnected ? "WHOOP BAND" : "BAND DISCONNECTED")
                            .font(StrapTypography.body(10, weight: .medium))
                    }
                    Text("LIVE STRAIN · unavailable until measured activity strain is connected")
                        .font(StrapTypography.body(11)).foregroundStyle(Color.appMuted)
                    Text(gps.status)
                        .font(StrapTypography.body(12))
                        .foregroundStyle(Color.appMuted)
                    HStack(spacing: 14) {
                        if !gps.recording {
                            Button("Start GPS") { gps.start(); workoutStarted = gps.recording }
                        } else {
                            Button(gps.paused ? "Resume" : "Pause") {
                                if gps.paused { gps.resume() } else { gps.pause() }
                            }
                            Button("Finish") { gps.stop(); workoutStarted = false }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                    Hint("Uses iPhone GPS while this screen is active. Accurate fixes only; location permissions required. Background recording uses iOS location updates; verify on your iPhone. Completed routes are stored locally.")
                }
                Panel {
                    SectionTitle("Kilometre splits")
                    if gps.splitSeconds.isEmpty {
                        Hint("Splits appear after each completed kilometre.")
                    } else {
                        ForEach(Array(gps.splitSeconds.enumerated()), id: \.offset) { index, seconds in
                            HStack {
                                Text("KM \(index + 1)")
                                Spacer()
                                Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                            }
                            .font(StrapTypography.body(13))
                            .foregroundStyle(Color.appFG)
                        }
                    }
                }
                Panel {
                    SectionTitle("Saved GPS runs")
                    if let exportURL { ShareLink("Share recorded route", item: exportURL) }
                    if let exportError { Hint(exportError) }
                    Hint("GPX and FIT exports contain recorded route points and timestamps. Missing heart rate, altitude and calories stay absent.")
                    if gps.savedRuns.isEmpty {
                        Hint("Finish a run of at least 100 metres to save it locally.")
                    } else {
                        ForEach(gps.savedRuns.prefix(20)) { run in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(run.startedAt, style: .date)
                                    Text(String(format: "%.2f km · %d min · %d splits",
                                                run.distanceMeters / 1000,
                                                run.movingSeconds / 60,
                                                run.splitSeconds.count))
                                        .font(StrapTypography.body(11))
                                        .foregroundStyle(Color.appMuted)
                                }
                                Spacer()
                                if run.route.count >= 2 {
                                    Button("Map") { selectedRun = run }
                                        .font(StrapTypography.body(12))
                                }
                                Menu("Export") {
                                    Button("GPX") { export(run, format: .gpx) }
                                    Button("FIT") { export(run, format: .fit) }
                                }.disabled(exporting || run.route.count < 2)
                                Button(role: .destructive) {
                                    gps.deleteRun(id: run.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                            .font(StrapTypography.body(13))
                            .foregroundStyle(Color.appFG)
                            .padding(.vertical, 5)
                        }
                    }
                }
            }
        }
        .navigationTitle("GPS Run")
        .sheet(item: $selectedRun) { run in
            NavigationStack {
                Map {
                    MapPolyline(coordinates: run.route.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    })
                    .stroke(.cyan, lineWidth: 4)
                }
                .navigationTitle("Recorded route")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { selectedRun = nil }
                    }
                }
            }
        }
        .onReceive(ticker) { _ in gps.refreshElapsed() }
        }
        }
    }

    private var runningPrestart: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button {
                    withAnimation { showPicker.toggle() }
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: selectedActivity.icon).font(.system(size: 28))
                        Text(selectedActivity.label.uppercased()).font(.system(size: 19, weight: .bold)).tracking(2)
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
                VStack(spacing: 12) {
                    TextField("Search Activities", text: $search)
                        .textFieldStyle(.roundedBorder)
                    // Category filters are intentionally omitted until backed by real activity metadata.
                    ScrollView {
                        LazyVStack {
                            if !search.isEmpty && !ActivityKind.allCases.contains(where: {
                                $0.label.localizedCaseInsensitiveContains(search)
                            }) {
                                Text("No matching activities")
                                    .foregroundStyle(.secondary)
                                    .padding(12)
                                    .accessibilityIdentifier("running.activityPicker.empty")
                            }
                            ForEach(ActivityKind.allCases.filter {
                                search.isEmpty || $0.label.localizedCaseInsensitiveContains(search)
                            }) { activity in
                                Button {
                                    selectedActivity = activity
                                    withAnimation { showPicker = false }
                                } label: {
                                    HStack {
                                        Image(systemName: activity.icon).frame(width: 28)
                                        Text(activity.label)
                                        Spacer()
                                    }
                                    .padding(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
                .background(.black)
                .foregroundStyle(.white)
            } else {
            ZStack {
                Map(initialPosition: .userLocation(fallback: .automatic)) {
                    UserAnnotation()
                }
                .mapControls { MapCompass() }
                VStack {
                    HStack {
                        Spacer()
                        Text("TRACK ROUTE")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(12)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .padding(12)
                    Spacer()
                    Circle()
                        .fill(Color(red: 0.07, green: 0.58, blue: 0.92))
                        .frame(width: 220, height: 220)
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: "heart.fill").font(.system(size: 30))
                                Text("READY").font(.system(size: 38, weight: .bold))
                                Text(liveBPM(at: Date()).map { "\($0) BPM" } ?? "HR WAITING")
                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                        }
                    Spacer()
                }
            }
            .frame(maxHeight: .infinity)
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
                VStack(spacing: 24) {
                    Text("CURRENT DAY STRAIN").font(.headline)
                    Text(dayStrain.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 70, weight: .bold))
                    Text("Recovery-based activity target is unavailable until validated.")
                        .multilineTextAlignment(.center)
                    Button("Done") { showStrain = false }
                }
                .padding()
                .presentationDetents([.medium, .large])
            }
            Button {
                gps.start()
                if gps.recording { workoutStarted = true }
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
            Text(gps.status).font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
            }
        }
        .background(Color(.systemBackground))
    }
}
