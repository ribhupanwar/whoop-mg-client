import SwiftUI

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
    var body: some View {
        Form {
            Text("Import accessible heart rate, resting heart rate, SDNN HRV, respiration, oxygen, steps, active energy, sleep and workout source records. These do not replace band measurements or supply RMSSD Recovery inputs.")
            DatePicker("From", selection: $from)
            DatePicker("Through", selection: $through)
            Button("Authorize & import Apple Health") {
                running = true
                Task {
                    defer { running = false }
                    do {
                        let count = try await AppleHealthImport.run(from: from, through: through)
                        status = "Imported \(count) new source records. Empty results can mean no accessible samples or no read permission."
                    } catch { status = error.localizedDescription }
                }
            }.disabled(running || from >= through)
            Text(status)
        }.navigationTitle("Import Apple Health")
    }
}
