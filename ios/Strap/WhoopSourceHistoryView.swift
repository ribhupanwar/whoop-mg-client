import SwiftUI

struct WhoopWorkoutHistoryView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        List {
            Section {
                Text("Original WHOOP workouts. Source scores and energy stay separate from local band activities and daily totals. Matching times do not prove two providers describe the same activity.")
                if let error = store.whoopImportReadError { Text(error) }
                if store.whoopImportedWorkouts.isEmpty { Text("No dated WHOOP workouts imported.") }
            }
            ForEach(store.whoopImportedWorkouts) { workout in
                Section("\(workout.dateKey) · \(workout.name) · WHOOP") {
                    if let strain = workout.strain { LabeledContent("Original activity strain", value: String(format: "%.1f", strain)) }
                    if let energy = workout.energyKcal { LabeledContent("Original energy (kcal)", value: String(format: "%.0f", energy)) }
                    OriginalWhoopFields(record: workout.original)
                }
            }
        }.navigationTitle("WHOOP workouts")
    }
}

/// A separate browser leaves the local journal editor and its unsaved draft
/// untouched. Exported questions are never guessed into STRAP yes/no fields.
struct WhoopJournalHistoryView: View {
    @State private var date = Date()
    @State private var sources: [String: [WhoopCSVImport.SupplementalRecord]] = [:]
    @State private var error: String?
    private var records: [WhoopCSVImport.SupplementalRecord] {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
        let key = formatter.string(from: date)
        return WhoopSourceExport.select(sources, from: key, through: key).records.filter { $0.source == "journal_entries" }
    }
    var body: some View {
        List {
            Section {
                DatePicker("Source day", selection: $date, displayedComponents: .date)
                Text("Original WHOOP questions, answers and notes. Uses the matching cycle's wake date when available, otherwise the original cycle date. Local journal entries and scores stay unchanged.")
                if let error { Text(error) }
                if records.isEmpty { Text("No dated source journal rows for this day.") }
            }
            ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                Section("WHOOP journal · \(index + 1)") { OriginalWhoopFields(record: record) }
            }
        }.navigationTitle("WHOOP journal history")
            .task {
                do { sources = try WhoopCSVImport.loadSources() }
                catch { self.error = "Cannot read original import: " + error.localizedDescription }
            }
    }
}

private struct OriginalWhoopFields: View {
    let record: WhoopCSVImport.SupplementalRecord
    var body: some View {
        DisclosureGroup("Original source fields") {
            ForEach(record.fields.keys.sorted(), id: \.self) { key in
                LabeledContent(key, value: record.fields[key] ?? "").textSelection(.enabled)
            }
        }
    }
}
