import SwiftUI

struct ManualActivityRevisionsView: View {
    @State private var files: [URL] = []
    @State private var status = "Loading preserved revisions…"

    var body: some View {
        List {
            Section {
                Text("Original manual activity collections are retained before edits, merges and deletes. Restoring adds missing entries only; current edits always take precedence.")
                Text(status)
            }
            ForEach(files, id: \.lastPathComponent) { file in
                NavigationLink("Revision " + String(file.lastPathComponent.prefix(12))) {
                    ManualActivityRevisionDetailView(file: file)
                }
            }
        }
        .navigationTitle("Preserved manual entries")
        .task {
            do {
                let directory = ActivityStore.revisionArchiveDirectory
                files = try await Task.detached(priority: .utility) {
                    let fm = FileManager.default
                    guard fm.fileExists(atPath: directory.path) else { return [URL]() }
                    return try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        .filter { url in
                            guard url.pathExtension == "json" else { return false }
                            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                            return values.isRegularFile == true && values.isSymbolicLink != true
                        }
                        .sorted { $0.lastPathComponent < $1.lastPathComponent }
                }.value
                status = "\(files.count) preserved revision files."
            } catch { status = error.localizedDescription }
        }
    }
}

private struct ManualActivityRevisionDetailView: View {
    @EnvironmentObject private var store: AppStore
    let file: URL
    @State private var entries: [ManualActivity] = []
    @State private var status = "Reading original revision…"

    var body: some View {
        List {
            Section {
                Text(status)
                ShareLink("Save original revision JSON", item: file)
            }
            ForEach(entries) { record in
                Section(record.dateKey + " · " + record.name) {
                    Text(record.summary)
                    if !record.notes.isEmpty { Text(record.notes) }
                    Button("Restore missing entry") {
                        do {
                            let restored = try store.restoreMissingManualActivity(record)
                            status = restored
                                ? "Entry restored. Existing records and edits were preserved."
                                : "An entry with this identity already exists; current version was preserved."
                        } catch { status = "Original revision retained: " + error.localizedDescription }
                    }
                }
            }
        }
        .navigationTitle("Original revision")
        .task {
            do {
                entries = try await Task.detached(priority: .utility) {
                    try JSONDecoder().decode([ManualActivity].self, from: Data(contentsOf: file, options: .mappedIfSafe))
                }.value
                status = "\(entries.count) original manual entries."
            } catch { status = "Cannot decode this revision; original bytes retained. " + error.localizedDescription }
        }
    }
}
