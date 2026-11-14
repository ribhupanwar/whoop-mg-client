import SwiftUI

/// Journal — seven yes/no self-report rows, mood, soreness and notes.
/// One entry per day in UserDefaults; saving again updates it.
/// The journal NEVER alters any score — the band sends no journal data.
struct JournalView: View {
    @EnvironmentObject private var store: AppStore

    @State private var entry = JournalEntry(dateKey: "")
    @State private var saved = false
    @State private var loaded = false

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.headerFormatter.string(from: Date()))
                    .font(StrapTypography.body(12))
                    .foregroundStyle(Color.appMuted)
                    .padding(.bottom, 10)
                questionsPanel
                moodPanel
                saveButton
                Hint("Stays on this phone and never edits recovery, strain or any other score. This is self-report: the band sends no journal data. After about 14 filled days, each behaviour gets a yes-days vs no-days comparison — correlation to inspect, not a cause proven.")
            }
        }
        .navigationTitle("My Journal")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadIfNeeded() }
        .onChange(of: entry) { saved = false }
    }

    // MARK: Questions

    private var questionsPanel: some View {
        Panel {
            SectionTitle("Daily check-in")
            ForEach(Array(JournalQuestion.allCases.enumerated()), id: \.element.id) { index, question in
                YesNoRow(
                    question: question.label,
                    value: answerBinding(question),
                    showTopBorder: index > 0
                )
            }
            Hint("Everything defaults to No — tap Yes only if it actually happened. The list is ours: your own report, not a device reading.")
        }
    }

    private func answerBinding(_ question: JournalQuestion) -> Binding<Bool> {
        Binding(
            get: { entry.answer(question) },
            set: { entry.setAnswer(question, $0) }
        )
    }

    // MARK: Mood / soreness / notes

    private var moodPanel: some View {
        Panel {
            SectionTitle("Mood on waking")
            ChipPicker(options: Mood.allCases, label: { $0.label }, selection: $entry.mood)
                .padding(.bottom, 12)
            SectionTitle("Muscle soreness")
            ChipPicker(options: Soreness.allCases, label: { $0.label }, selection: sorenessBinding)
                .padding(.bottom, 12)
            SectionTitle("Notes")
            TextEditor(text: $entry.notes)
                .font(StrapTypography.body(12))
                .foregroundStyle(Color.appFG)
                .scrollContentBackground(.hidden)
                .frame(height: 90)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.appRaised))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.appLine.opacity(0.35), lineWidth: 1))
        }
    }

    private var sorenessBinding: Binding<Soreness?> {
        Binding(
            get: { Optional(entry.soreness) },
            set: { if let value = $0 { entry.soreness = value } }
        )
    }

    // MARK: Save

    private var saveButton: some View {
        Button {
            store.saveJournal(entry)
            saved = true
        } label: {
            Text(saved ? "Saved ✓" : "SAVE JOURNAL")
                .font(StrapTypography.body(12, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Color.appBG)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.appFG))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 4)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let key = JournalStore.dayKey(for: Date())
        if let existing = store.journal.entry(forDayKey: key) {
            entry = existing
        } else {
            entry = JournalEntry(dateKey: key)
        }
        loaded = true
    }

    private static let headerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()
}