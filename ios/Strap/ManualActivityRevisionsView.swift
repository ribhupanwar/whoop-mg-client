import SwiftUI

struct ManualActivityRevisionsView: View {
    var body: some View { PreservedActivityFilesView(kind: .manual) }
}

/// Load only the selected revision, rather than decoding every historical
/// collection at once. Original archive files are never rewritten or pruned.
struct PreservedActivityFilesView: View {
    enum Kind {
        case manual, live, gps
        var title: String {
            switch self { case .manual: return "Preserved manual entries"; case .live: return "Preserved live sessions"; case .gps: return "Preserved GPS runs" }
        }
        var folder: URL {
            switch self {
            case .manual: return ActivityStore.revisionArchiveDirectory
            case .live: return ActivityStore.revisionArchiveDirectory.appendingPathComponent("live-sessions", isDirectory: true)
            case .gps: return GPSRunHistory.revisionArchiveDirectory
            }
        }
    }
    let kind: Kind
    @State private var files: [URL] = []
    @State private var status = "Loading preserved revisions…"
    var body: some View {
        List {
            Section {
                Text("Choose an original revision to preview. Recovery adds missing identities only; existing entries and edits always win. Files remain in full backups.")
                Text(status)
            }
            ForEach(files, id: \.lastPathComponent) { file in
                NavigationLink("Revision " + String(file.lastPathComponent.prefix(12))) {
                    PreservedActivityRevisionView(kind: kind, file: file)
                }
            }
        }.navigationTitle(kind.title)
            .task {
                do {
                    let directory = kind.folder
                    files = try await Task.detached(priority: .utility) {
                        let fm = FileManager.default
                        guard fm.fileExists(atPath: directory.path) else { return [URL]() }
                        return try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                            .filter { file in
                                guard file.pathExtension == "json" else { return false }
                                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                                return values.isRegularFile == true && values.isSymbolicLink != true
                            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                    }.value
                    status = "\(files.count) original revision files."
                } catch { status = error.localizedDescription }
            }
    }
}

private struct PreservedActivityRevisionView: View {
    @EnvironmentObject private var store: AppStore
    let kind: PreservedActivityFilesView.Kind
    let file: URL
    private enum Entry {
        case manual(ManualActivity), live(LiveActivityRecord), gps(GPSRunRecord)
        var title: String {
            switch self {
            case .manual(let r): return r.dateKey + " · " + r.name
            case .live(let r): return r.dateKey + " · Live session"
            case .gps(let r): return r.startedAt.formatted(date: .abbreviated, time: .shortened) + " · GPS run"
            }
        }
    }
    @State private var entries: [Entry] = []
    @State private var status = "Reading original revision…"
    var body: some View {
        List {
            Section {
                Text(status)
                ShareLink("Save original revision JSON", item: file)
            }
            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                Section(entry.title) {
                    if case .manual(let record) = entry { Text(record.summary); Text(record.notes) }
                    Button("Restore missing entry") {
                        do {
                            let restored: Bool
                            switch entry {
                            case .manual(let r): restored = try store.restoreMissingManualActivity(r)
                            case .live(let r): restored = try store.restoreMissingLiveActivity(r)
                            case .gps(let r): restored = try GPSRunRecorder.shared.restoreRun(r)
                            }
                            status = restored ? "Missing entry restored; current entries preserved." : "Current entry already exists and was preserved."
                        } catch { status = "Original revision preserved: " + error.localizedDescription }
                    }
                }
            }
        }.navigationTitle("Original revision")
            .task {
                do {
                    entries = try await Task.detached(priority: .utility) {
                        let data = try Data(contentsOf: file, options: .mappedIfSafe)
                        switch kind {
                        case .manual: return try JSONDecoder().decode([ManualActivity].self, from: data).map(Entry.manual)
                        case .live: return try JSONDecoder().decode([LiveActivityRecord].self, from: data).map(Entry.live)
                        case .gps: return try JSONDecoder().decode([GPSRunRecord].self, from: data).map(Entry.gps)
                        }
                    }.value
                    status = "\(entries.count) original entries. Restoring does not automatically export to Apple Health."
                } catch { status = "Cannot decode this revision; original bytes retained. " + error.localizedDescription }
            }
    }
}
