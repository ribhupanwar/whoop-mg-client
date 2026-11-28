import SwiftUI
import HealthKit

struct ImportHistoryView: View {
    @State private var sections: [(String, [WhoopCSVImport.SupplementalRecord])] = []
    @State private var exportURL: URL?
    @State private var status = ""
    var body: some View {
        List {
            Section {
                Text("Original WHOOP fields and timestamps are retained as source records. Exported stage totals are not a timestamped hypnogram. Imported records remain distinct from local band estimates.")
                Text(status)
                if let exportURL { ShareLink("Save source records JSON", item: exportURL) }
                Button("Export individual source records JSON") {
                    do {
                        let records = sections.flatMap { $0.1 }
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WHOOP-source-records-\(UUID().uuidString).json")
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        try encoder.encode(records).write(to: url, options: .atomic)
                        exportURL = url
                    } catch { status = error.localizedDescription }
                }
            }
            ForEach(sections.indices, id: \.self) { index in
                Section("\(sections[index].0) · \(sections[index].1.count) records") {
                    ForEach(sections[index].1.indices, id: \.self) { row in
                        let record = sections[index].1[row]
                        DisclosureGroup("Source record \(row + 1)") {
                            ForEach(record.fields.keys.sorted(), id: \.self) { field in
                                LabeledContent(field, value: record.fields[field] ?? "").textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Import history & diagnostics")
        .task {
            do {
                var loaded: [(String, [WhoopCSVImport.SupplementalRecord])] = []
                let sources = try WhoopCSVImport.loadSources()
                for category in WhoopCSVImport.sourceCategories {
                    if let records = sources[category] { loaded.append((category, records)) }
                }
                sections = loaded
                status = "Apple Health: \(try AppleHealthImport.load().count) retained source samples."
            } catch { status = "Original import bytes retained; decoding failed: " + error.localizedDescription }
        }
    }
}

struct AppleHealthImportView: View {
    @State private var from = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
    @State private var through = Date()
    @State private var running = false
    @State private var status = ""
    @State private var healthStoreAvailable = HKHealthStore.isHealthDataAvailable()
    @State private var authorizationStatusText = "Checking HealthKit access…"
    @State private var workoutAuth = "Checking…"
    @State private var hrAuth = "Checking…"
    @State private var sleepAuth = "Checking…"
    @State private var stepsAuth = "Checking…"
    private let healthStore = HKHealthStore()

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 16) {
                Panel {
                    SectionTitle("HEALTHKIT STATUS")
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(healthStoreAvailable ? "Apple Health Supported" : "HealthKit Unavailable")
                                .font(StrapTypography.body(14, weight: .bold))
                                .foregroundStyle(Color.appFG)
                            Text(authorizationStatusText)
                                .font(StrapTypography.body(11))
                                .foregroundStyle(Color.appMuted)
                        }
                        Spacer()
                        Circle()
                            .fill(healthStoreAvailable ? Color.appGood : Color.appWarn)
                            .frame(width: 10, height: 10)
                    }
                    .padding(.vertical, 4)

                    Divider().background(Color.appLine).padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        healthCategoryRow(title: "Workouts & Activities", status: workoutAuth)
                        healthCategoryRow(title: "Heart Rate & Resting HR", status: hrAuth)
                        healthCategoryRow(title: "Sleep Analysis & Stages", status: sleepAuth)
                        healthCategoryRow(title: "Daily Steps & Cadence", status: stepsAuth)
                    }
                }

                Panel {
                    SectionTitle("IMPORT HISTORICAL RECORDS")
                    Text("Import historical Apple Health records. Imported records are stored safely in STRAP's local database and their count is displayed; they do not replace physical band measurements or overwrite raw sensor RMSSD Recovery inputs.")
                        .font(StrapTypography.body(11.5))
                        .foregroundStyle(Color.appMuted)
                        .padding(.bottom, 4)

                    DatePicker("From", selection: $from, displayedComponents: [.date, .hourAndMinute])
                        .font(StrapTypography.body(13, weight: .medium))
                        .foregroundStyle(Color.appFG)

                    Divider().background(Color.appLine).padding(.vertical, 2)

                    DatePicker("Through", selection: $through, displayedComponents: [.date, .hourAndMinute])
                        .font(StrapTypography.body(13, weight: .medium))
                        .foregroundStyle(Color.appFG)

                    Divider().background(Color.appLine).padding(.vertical, 4)

                    Button {
                        running = true
                        Task {
                            defer { running = false }
                            do {
                                let count = try await AppleHealthImport.run(from: from, through: through)
                                status = "Imported \(count) new source records. Empty results can mean no accessible samples or no read permission."
                                updateAuthStatuses()
                            } catch { status = error.localizedDescription }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text(running ? "Importing from Apple Health…" : "Authorize & Import Apple Health")
                                .font(StrapTypography.body(13.5, weight: .semibold))
                            Spacer()
                            if running { ProgressView().controlSize(.small) }
                        }
                        .foregroundStyle(Color.appAccent)
                        .padding(.vertical, 6)
                    }
                    .disabled(running || from >= through)

                    if !status.isEmpty {
                        Text(status)
                            .font(StrapTypography.body(11))
                            .foregroundStyle(Color.appGood)
                            .padding(.top, 2)
                    }
                }

                Panel {
                    SectionTitle("WORKOUT SHARING")
                    NavigationLink {
                        StravaIntegrationView()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Strava")
                                .font(StrapTypography.body(14, weight: .bold))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(Color.appFG)
                        .padding(.vertical, 8)
                    }
                    .accessibilityIdentifier("integrations.strava")
                    Text("Free Apple Health relay or manual TCX file upload.")
                        .font(StrapTypography.body(11))
                        .foregroundStyle(Color.appMuted)
                }

                Panel {
                    SectionTitle("LOCAL-FIRST INTEGRITY")
                    Text("STRAP interacts with Apple Health strictly via native HealthKit APIs on your iPhone. Workouts are exported with unique external UUIDs for deduplication. No third-party servers or unauthorized cloud services are ever contacted.")
                        .font(StrapTypography.body(11.5))
                        .foregroundStyle(Color.appMuted)
                        .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Health Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            updateAuthStatuses()
        }
    }

    private func updateAuthStatuses() {
        guard healthStoreAvailable else {
            authorizationStatusText = "HealthKit not supported on this device"
            workoutAuth = "Unavailable"
            hrAuth = "Unavailable"
            sleepAuth = "Unavailable"
            stepsAuth = "Unavailable"
            return
        }
        authorizationStatusText = "Write permissions · Apple Health manages read access"
        workoutAuth = authLabel(for: HKObjectType.workoutType())
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            hrAuth = authLabel(for: hrType)
        } else {
            hrAuth = "Not Supported"
        }
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            sleepAuth = authLabel(for: sleepType)
        } else {
            sleepAuth = "Not Supported"
        }
        if let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) {
            stepsAuth = authLabel(for: stepType)
        } else {
            stepsAuth = "Not Supported"
        }
    }

    private func authLabel(for objectType: HKObjectType) -> String {
        switch healthStore.authorizationStatus(for: objectType) {
        case .sharingAuthorized: return "Write allowed"
        case .sharingDenied: return "Write denied"
        case .notDetermined: return "Write access undecided"
        @unknown default: return "Unknown"
        }
    }

    private func healthCategoryRow(title: String, status: String) -> some View {
        HStack {
            Text(title)
                .font(StrapTypography.body(12, weight: .medium))
                .foregroundStyle(Color.appFG)
            Spacer()
            Text(status)
                .font(StrapTypography.body(11, weight: .semibold))
                .foregroundStyle(statusColor(status))
        }
        .padding(.vertical, 2)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Write allowed": return Color.appGood
        case "Write denied": return Color.appWarn
        default: return Color.appMuted
        }
    }
}


/// Free export routes; no Strava credentials or third-party network client.
@MainActor
struct StravaIntegrationView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var recorder = WorkoutRecorder.shared
    @ObservedObject private var relay = RecordedRunHealthRelay.shared
    @AppStorage(RecordedRunHealthRelay.enabledKey) private var relayEnabled = false
    @State private var selectedID: UUID?
    @State private var exported: URL?
    @State private var error: String?

    var body: some View {
        Form {
            Section("Method 1 · Apple Health / WorkoutPort") {
                Toggle("Export measured band workouts to Health", isOn: Binding(
                    get: { store.settings.healthKitEnabled },
                    set: { enabled in
                        if enabled { relayEnabled = false }
                        store.setHealthKit(enabled)
                    }
                ))
                Text(store.healthKitStatus)
                    .font(.footnote)
                Link("Install WorkoutPort", destination: URL(string: "https://apps.apple.com/app/id6779691091")!)
                Text("In WorkoutPort, grant Health workout access, connect your own Strava account, and create an auto-sync rule for STRAP as the source. Preview matching workouts before enabling it. Enabling Health export may also export previously saved measured band sessions.")
                    .font(.footnote)
                Toggle("Auto-export recorded runs (GPS + HR)", isOn: Binding(
                    get: { relayEnabled && !store.settings.healthKitEnabled },
                    set: { enabled in
                        if !enabled { relayEnabled = false; return }
                        Task {
                            if await relay.authorize(), !store.settings.healthKitEnabled { relayEnabled = true }
                        }
                    }
                ))
                .disabled(store.settings.healthKitEnabled || relay.busy)
                if store.settings.healthKitEnabled {
                    Text("Turn off band-summary export above before enabling the recorded-run relay. Use one source to avoid duplicate activities.")
                        .font(.footnote)
                }
                Text(relay.status).font(.footnote)
                Button("Export selected saved run to Apple Health") {
                    guard let session = recorder.savedWorkouts.first(where: { $0.id == selectedID }) else { return }
                    Task { await relay.export(session) }
                }
                .disabled(!relayEnabled || store.settings.healthKitEnabled || selectedID == nil || relay.busy)
                Text("Choose a saved workout below for manual retry. Newly saved runs export automatically while STRAP is running. WorkoutPort handles delivery to Strava; its background timing and route availability require device testing. Do not use TCX for an already synced run.")
                    .font(.footnote)
            }
            Section("Method 2 · Manual TCX") {
                if recorder.savedWorkouts.isEmpty {
                    Text("Record and save a workout first.")
                } else {
                    Picker("Saved workout", selection: $selectedID) {
                        Text("Select").tag(UUID?.none)
                        ForEach(recorder.savedWorkouts) { session in
                            Text(session.activityLabel + " · " + session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .tag(Optional(session.id))
                        }
                    }
                    Button("Prepare TCX file") {
                        exported = nil
                        error = nil
                        guard let session = recorder.savedWorkouts.first(where: { $0.id == selectedID }) else { return }
                        do { exported = try StravaTCXExport.write(session) }
                        catch { self.error = error.localizedDescription }
                    }
                    .disabled(selectedID == nil)
                    if let exported {
                        ShareLink("Save or share TCX", item: exported)
                        Link("Open Strava file uploader", destination: URL(string: "https://www.strava.com/upload/select")!)
                        Text("Save the TCX to Files, then select it in Strava. This is manual; STRAP cannot verify the upload.")
                            .font(.footnote)
                    }
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                Text("Exports only recorded route and timestamped heart rate. Older indoor workouts without samples cannot be converted into a valid track. No invented measurements.")
                    .font(.footnote)
            }
            Section("Avoid duplicate uploads") {
                Text("Use one method per workout. STRAP does not have access to your Strava upload history. No Strava API credentials are stored.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Strava")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedID) { _, _ in exported = nil; error = nil }
    }
}
