import SwiftUI

struct OSDiagnosticsView: View {
    @State private var files: [URL] = []
    @State private var status = "Loading retained OS reports…"
    var body: some View {
        List {
            Section {
                Text("iOS delivers MetricKit crash, hang and performance payloads on its own schedule. Reports stay on this phone and are included in persisted-record diagnostics and full backups. They may contain sensitive diagnostic details.")
                Text(status)
                Text("No reports does not mean no crashes. A simulator run cannot establish physical battery use or wrist sensor accuracy.")
            }
            Section("Original OS JSON") {
                ForEach(files, id: \.lastPathComponent) { file in
                    ShareLink(item: file) { Text(file.lastPathComponent).font(.caption).lineLimit(2) }
                }
            }
        }
        .navigationTitle("OS diagnostics")
        .task {
            do {
                let directory = OSDiagnosticArchive.directory
                if FileManager.default.fileExists(atPath: directory.path) {
                    files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                        .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                }
                status = "\(files.count) retained OS payloads. OS delivery and observation intervals vary."
            } catch { status = "Cannot read retained reports: " + error.localizedDescription }
        }
    }
}
