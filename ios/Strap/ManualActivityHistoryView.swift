import SwiftUI

struct ManualActivityHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selected: Set<UUID> = []
    @State private var name = ""
    @State private var status = ""
    @State private var editing: ManualActivity?
    var body: some View {
        List {
            Section {
                Text("Edit a manual entry, or select entries of the same type and date to merge. Durations are added as self-report; overlap cannot be determined without start times. Measured band/live/WHOOP records and scores are not merged.")
                TextField("Merged activity name", text: $name)
                Button("Merge selected manual entries") {
                    do {
                        try store.mergeManualActivities(ids: selected, name: name)
                        selected = []; status = "Merged. Original entries remain inside the merged record and in the activity revision archive/full backup."
                    } catch { status = error.localizedDescription }
                }.disabled(selected.count < 2)
                Text(status)
            }
            ForEach(store.manualActivities) { record in
                Section("\(record.dateKey) · \(record.name)") {
                    Toggle(record.summary, isOn: Binding(
                        get: { selected.contains(record.id) },
                        set: { if $0 { selected.insert(record.id) } else { selected.remove(record.id) } }))
                    Button("Edit entry") { editing = record }
                    if let originals = record.mergedFrom {
                        Button("Undo merge and restore original entries") {
                            do { try store.undoManualActivityMerge(id: record.id); selected.remove(record.id); status = "Original entries restored; merged revision archived." }
                            catch { status = error.localizedDescription }
                        }
                        DisclosureGroup("\(originals.count) retained original entries") {
                            ForEach(originals) { original in
                                Text(original.name + " · " + original.summary + "\n" + original.notes)
                            }
                        }
                    }
                }
            }
        }.navigationTitle("Manual activity history")
            .sheet(item: $editing) { ActivityLoggerView(editing: $0).environmentObject(store) }
    }
}
