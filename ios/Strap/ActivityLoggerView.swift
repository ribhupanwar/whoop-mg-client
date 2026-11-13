import SwiftUI

/// Manual activity entry. Lifting is logged as sets × reps × load; everything
/// else by minutes. Nothing here feeds a score — it is the user's own log.
struct ActivityLoggerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: ActivityKind = .lift
    @State private var name = ""
    @State private var minutes = 45
    @State private var sets: [WorkSet] = [WorkSet(reps: 8, loadKG: 60.0)]
    @State private var notes = ""
    @State private var activitySearch = ""

    private let today = JournalStore.dayKey(for: Date())

    var body: some View {
        NavigationStack {
            Screen {
                VStack(alignment: .leading, spacing: 0) {
                    kindPanel
                    detailsPanel
                    if kind.usesSets {
                        setsPanel
                    }
                    Hint("Manual entries stay self-reported. The band measures heart rate and movement; it never sees load, so nothing from this sheet becomes strain or recovery.")
                }
            }
            .navigationTitle("Add activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.appMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
    }

    // MARK: Panels

    private var kindPanel: some View {
        Panel {
            SectionTitle("Type")
            HStack(spacing: 10) {
                Image(systemName: kind.icon)
                    .foregroundStyle(Color.appAccent)
                Text(kind.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appFG)
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundStyle(Color.appMuted)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.appRaised))
            TextField("Search 60+ activities", text: $activitySearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 13))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.appRaised))
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(ActivityKind.allCases.filter {
                        activitySearch.isEmpty || $0.label.localizedCaseInsensitiveContains(activitySearch)
                    }) { option in
                        Button {
                            kind = option
                            activitySearch = ""
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.icon)
                                    .frame(width: 22)
                                Text(option.label)
                                Spacer()
                                if kind == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .font(.system(size: 13))
                            .foregroundStyle(kind == option ? Color.appAccent : Color.appFG)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 225)
        }
    }

    private var detailsPanel: some View {
        Panel {
            SectionTitle("Details")
            row(label: "Name") {
                TextField(kind.label, text: $name)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appFG)
                    .frame(maxWidth: 180)
            }
            Stepper(value: $minutes, in: 1...600, step: 5) {
                HStack {
                    Text("Duration")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appMuted)
                    Spacer()
                    Text("\(minutes) min")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.appFG)
                }
            }
            .tint(.appAccent)
            .padding(.vertical, 4)
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .lineLimit(2...5)
                .font(.system(size: 13))
                .foregroundStyle(Color.appFG)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.appRaised))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
                .padding(.top, 6)
        }
    }

    private var setsPanel: some View {
        Panel {
            HStack {
                SectionTitle("Sets")
                Spacer()
                Button {
                    sets.append(WorkSet(reps: sets.last?.reps ?? 8, loadKG: sets.last?.loadKG ?? 60.0))
                } label: {
                    Text("+ ADD SET")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(Color.appAccent)
                }
                .buttonStyle(.plain)
            }
            ForEach($sets) { $set in
                HStack(spacing: 10) {
                    Text("SET")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(Color.appMuted)
                    Stepper(value: $set.reps, in: 1...100, step: 1) {
                        Text("\(set.reps) reps")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.appFG)
                    }
                    .tint(.appAccent)
                    Spacer()
                    TextField("kg", value: $set.loadKG, format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.appFG)
                        .frame(width: 54)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.appRaised))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
                    Text("kg")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.appMuted)
                    if sets.count > 1 {
                        Button {
                            sets.removeAll { $0.id == set.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.appMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 5)
            }
            if !sets.isEmpty {
                Hint(volumeText)
            }
        }
    }

    private var volumeText: String {
        let reps = sets.reduce(0) { $0 + $1.reps }
        let volume = Int(sets.reduce(0.0) { $0 + $1.volumeKG }.rounded())
        return "\(sets.count) sets · \(reps) reps · \(volume) kg total volume"
    }

    private func row<Control: View>(label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
            Spacer()
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appRaised))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
        .padding(.bottom, 10)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let activity = ManualActivity(
            dateKey: today,
            kind: kind,
            name: trimmed.isEmpty ? kind.label : trimmed,
            minutes: minutes,
            sets: kind.usesSets ? sets.filter { $0.reps > 0 } : [],
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        store.addActivity(activity)
        dismiss()
    }
}
