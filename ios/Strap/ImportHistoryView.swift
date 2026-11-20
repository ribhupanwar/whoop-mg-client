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
                        healthCategoryRow(title: "Workouts & Activities", status: "Bi-directional sync enabled")
                        healthCategoryRow(title: "Heart Rate & Resting HR", status: "Export supported")
                        healthCategoryRow(title: "Sleep Analysis & Stages", status: "Verified nights sync")
                        healthCategoryRow(title: "Daily Steps & Cadence", status: "Read & write available")
                    }
                }

                Panel {
                    SectionTitle("IMPORT HISTORICAL RECORDS")
                    Text("Import historical Apple Health records. These populate your local timeline without replacing physical band measurements or overwriting RMSSD Recovery inputs.")
                        .font(StrapTypography.body(11.5))
                        .foregroundStyle(Color.appMuted)
                        .padding(.bottom, 4)

                    DatePicker("From", selection: $from, displayedComponents: [.date])
                        .font(StrapTypography.body(13, weight: .medium))
                        .foregroundStyle(Color.appFG)

                    Divider().background(Color.appLine).padding(.vertical, 2)

                    DatePicker("Through", selection: $through, displayedComponents: [.date])
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
                    SectionTitle("LOCAL-FIRST INTEGRITY")
                    Text("STRAP interacts with Apple Health strictly via native HealthKit APIs on your iPhone. No third-party servers, unauthorized Strava integrations, or cloud services are ever contacted.")
                        .font(StrapTypography.body(11.5))
                        .foregroundStyle(Color.appMuted)
                        .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Health Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            authorizationStatusText = healthStoreAvailable ? "Local HealthKit storage authorized on iPhone" : "Not supported on this device"
        }
    }

    private func healthCategoryRow(title: String, status: String) -> some View {
        HStack {
            Text(title)
                .font(StrapTypography.body(12, weight: .medium))
                .foregroundStyle(Color.appFG)
            Spacer()
            Text(status)
                .font(StrapTypography.body(11))
                .foregroundStyle(Color.appMuted)
        }
        .padding(.vertical, 2)
    }
}
