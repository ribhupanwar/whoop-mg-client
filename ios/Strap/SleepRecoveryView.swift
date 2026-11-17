import SwiftUI

struct SleepRecoveryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var candidates: [SleepRecoveryVault.Candidate] = []
    @State private var status = ""
    @State private var selected: SleepRecoveryVault.Candidate?
    var body: some View {
        List {
            Section {
                Text("Preview saved records before recovery. Timestamps and estimated stages remain as recorded. Older algorithm versions are historical estimates. Export diagnostics before applying. Current manual corrections take precedence.")
                if !status.isEmpty { Text(status) }
            }
            ForEach(candidates) { candidate in
                Button {
                    selected = candidate
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Date(timeIntervalSince1970: Double(candidate.session.startUnix)), style: .date)
                        Text("\(Date(timeIntervalSince1970: Double(candidate.session.startUnix)).formatted()) → \(Date(timeIntervalSince1970: Double(candidate.session.endUnix)).formatted())")
                        Text("Algorithm \(candidate.session.version) · \(candidate.session.isEdited ? "manually edited" : "estimated") · \(candidate.session.isComplete ? "complete stages" : "incomplete evidence")")
                        Text(candidate.provenance).font(.caption).textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("Sleep recovery preview")
        .task {
            do {
                candidates = try await Task.detached { try SleepRecoveryVault.candidates() }.value
                if candidates.isEmpty { status = "No decodable saved sleep sessions found. Retained raw data may still permit analysis; export diagnostics for investigation." }
            } catch { status = error.localizedDescription }
        }
        .confirmationDialog("Restore this recorded sleep window?", isPresented: Binding(
            get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let selected {
                Button("Restore saved session") {
                    do {
                        try store.band.restoreSavedSleep(selected)
                        status = "Saved session restored. Original evidence retained; review the recovery archive to reverse this selection. Missing biometrics were not generated."
                    } catch { status = error.localizedDescription }
                    self.selected = nil
                }
            }
            Button("Cancel", role: .cancel) { selected = nil }
        }
    }
}
