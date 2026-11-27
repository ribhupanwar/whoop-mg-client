import SwiftUI

/// Journal — seven yes/no self-report rows, mood, soreness and notes.
/// One entry per day in UserDefaults; saving again updates it.
/// The journal NEVER alters any score — the band sends no journal data.
struct JournalView: View {
    @EnvironmentObject private var store: AppStore

    @State private var entry = JournalEntry(dateKey: "")
    @State private var saved = false
    @State private var loaded = false
    @State private var comparisonMetric: JournalComparisonMetric = .sleep
    @AppStorage("strap.journal.hiddenQuestions") private var hiddenQuestions = ""
    @State private var customizingQuestions = false

    private var visibleQuestions: [JournalQuestion] {
        JournalQuestionPreferences.visible(excluding: hiddenQuestions)
    }

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
                behaviorPanel
                Hint("Stays on this phone and never edits recovery, strain or any other score. This is self-report: the band sends no journal data. After enough matched days, each behaviour gets a yes-days vs no-days comparison — an association, not a cause proven.")
            }
        }
        .navigationTitle("My Journal")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadIfNeeded() }
        .onChange(of: entry) { saved = false }
        .sheet(isPresented: $customizingQuestions) {
            NavigationStack {
                Form {
                    Section("Show in daily check-in") {
                        ForEach(JournalQuestion.allCases, id: \.id) { question in
                            Toggle(question.label, isOn: Binding(
                                get: { visibleQuestions.contains(question) },
                                set: { show in
                                    hiddenQuestions = JournalQuestionPreferences.setting(question, visible: show, in: hiddenQuestions)
                                }
                            ))
                        }
                        Button("Show all") { hiddenQuestions = "" }
                    }
                    Text("Hidden questions retain their saved answers and historical insights.")
                        .font(.footnote)
                }
                .navigationTitle("Customize journal")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { customizingQuestions = false } } }
            }
        }
    }

    private var behaviorPanel: some View {
        Panel {
            SectionTitle("Behavior insights")
            Picker("Compare with", selection: $comparisonMetric) {
                ForEach(JournalComparisonMetric.allCases, id: \.self) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            let rows = JournalQuestion.allCases.compactMap { question in
                JournalBehaviorComparison.make(question: question,
                    entries: Array(store.journalEntries.values), days: store.band.days, metric: comparisonMetric)
            }
            if rows.isEmpty {
                Hint("Needs 14 matched recorded days, including at least 5 explicitly answered Yes and 5 No days for a behavior. Unanswered questions are excluded.")
            } else {
                ForEach(rows, id: \.question) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.question.label).font(StrapTypography.body(13, weight: .bold))
                        Text("Yes: \(comparisonMetric.format(row.yesMean)) (n=\(row.yesCount)) · No: \(comparisonMetric.format(row.noMean)) (n=\(row.noCount))")
                            .font(StrapTypography.body(12)).foregroundStyle(Color.appMuted)
                    }
                    .padding(.vertical, 5)
                }
                Hint("Compares the next calendar day’s recorded metrics with explicitly logged answers. Observational association only; not a causal effect or score adjustment.")
            }
        }
    }

    // MARK: Questions

    private var questionsPanel: some View {
        Panel {
            HStack {
                SectionTitle("Daily check-in")
                Spacer()
                Button("Customize") { customizingQuestions = true }
                    .font(StrapTypography.body(12, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
            }
            if visibleQuestions.isEmpty {
                Hint("No questions selected. Customize to show them again; existing answers are preserved.")
            }
            ForEach(visibleQuestions, id: \.id) { question in
                HStack {
                    Text(question.label).font(StrapTypography.body(12.5))
                    Spacer()
                    Picker(question.label, selection: Binding<Int>(
                        get: { entry.answers[question.rawValue].map { $0 ? 1 : 0 } ?? -1 },
                        set: { choice in
                            if choice == -1 { entry.answers.removeValue(forKey: question.rawValue) }
                            else { entry.setAnswer(question, choice == 1) }
                        }
                    )) {
                        Text("—").tag(-1)
                        Text("Yes").tag(1)
                        Text("No").tag(0)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 165)
                }
                .padding(.vertical, 7)
            }
            Hint("Choose Yes or No explicitly. A dash is unanswered and will not be used in insights.")
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

enum JournalComparisonMetric: String, CaseIterable {
    case sleep = "Sleep", hrv = "HRV", rhr = "RHR"
    func format(_ value: Double) -> String {
        switch self {
        case .sleep: return String(format: "%.0f%%", value)
        case .hrv: return String(format: "%.1f ms", value)
        case .rhr: return String(format: "%.1f bpm", value)
        }
    }
    func value(_ day: DayMetrics) -> Double? {
        guard day.state == "sleep", day.sleepDurationReliable == true else { return nil }
        switch self {
        case .sleep: return day.sleepPerformancePct.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
        case .hrv:
            guard day.hrvWindowSeconds >= 300, let ln = day.lnRMSSD, ln.isFinite else { return nil }
            let result = exp(ln)
            return result.isFinite && result > 0 ? result : nil
        case .rhr:
            guard (day.restingHRWindowSeconds ?? 0) >= 300 else { return nil }
            return day.restingHR.flatMap { $0.isFinite && (35...220).contains($0) ? $0 : nil }
        }
    }
}

struct JournalBehaviorComparison {
    let question: JournalQuestion
    let yesMean: Double
    let noMean: Double
    let yesCount: Int
    let noCount: Int

    static func make(question: JournalQuestion, entries: [JournalEntry], days: [DayMetrics],
                     metric: JournalComparisonMetric = .sleep, calendar: Calendar = .current) -> Self? {
        let dated = Dictionary(grouping: days, by: \.dateKey)
        let answers = Dictionary(grouping: entries, by: \.dateKey)
        var yes: [Double] = [], no: [Double] = []
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        for (key, group) in answers {
            guard group.count == 1, let answer = group.first?.answers[question.rawValue],
                  let date = formatter.date(from: key), formatter.string(from: date) == key,
                  let next = calendar.date(byAdding: .day, value: 1, to: date),
                  let matches = dated[formatter.string(from: next)], matches.count == 1,
                  let day = matches.first, let value = metric.value(day) else { continue }
            if answer { yes.append(value) } else { no.append(value) }
        }
        guard yes.count >= 5, no.count >= 5, yes.count + no.count >= 14 else { return nil }
        return Self(question: question, yesMean: Stats.mean(yes), noMean: Stats.mean(no),
                    yesCount: yes.count, noCount: no.count)
    }
}

/// Hiding a built-in question changes presentation only, never journal data.
enum JournalQuestionPreferences {
    static func visible(excluding raw: String) -> [JournalQuestion] {
        let hidden = Set(raw.split(separator: ",").map(String.init))
        return JournalQuestion.allCases.filter { !hidden.contains($0.rawValue) }
    }

    static func setting(_ question: JournalQuestion, visible: Bool, in raw: String) -> String {
        var hidden = Set(raw.split(separator: ",").map(String.init))
        if visible { hidden.remove(question.rawValue) } else { hidden.insert(question.rawValue) }
        return hidden.sorted().joined(separator: ",")
    }
}
