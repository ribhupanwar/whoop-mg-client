import SwiftUI
import MapKit

struct GPSRunView: View {
    @ObservedObject private var gps = GPSRunRecorder.shared
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

    var body: some View {
        Group {
        if !workoutStarted && !gps.recording {
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
                    Text(gps.status)
                        .font(StrapTypography.body(12))
                        .foregroundStyle(Color.appMuted)
                    HStack(spacing: 14) {
                        if !gps.recording {
                            Button("Start GPS") { gps.start() }
                        } else {
                            Button(gps.paused ? "Resume" : "Pause") {
                                if gps.paused { gps.resume() } else { gps.pause() }
                            }
                            Button("Finish") { gps.stop() }
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
                Image(systemName: "figure.run").font(.system(size: 28))
                Text("RUNNING").font(.system(size: 19, weight: .bold)).tracking(2)
                Spacer()
                Image(systemName: "chevron.down")
            }
            .foregroundStyle(.white)
            .padding(24)
            .background(.black)

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
                                Text("GPS RUN").font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                        }
                    Spacer()
                }
            }
            .frame(maxHeight: .infinity)
            HStack {
                Text("STRAIN TARGET").font(.system(size: 15, weight: .bold)).tracking(1)
                Spacer()
                Text("Not configured").font(.system(size: 12))
            }
            .padding(20)
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
            Text(gps.status).font(.caption).padding(.bottom, 10)
        }
        .background(Color(.systemBackground))
    }
}
