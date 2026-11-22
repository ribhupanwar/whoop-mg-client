import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Experimental, opt-in on-device coach. No external API keys or automatic
/// health-data upload. Integration with read-only measured metrics is separate.
@available(iOS 26.0, *)
struct StrapAICoachView: View {
    @State private var question = ""
    @State private var messages: [CoachMessage] = []
    @State private var busy = false
    @State private var notice: String?
    @State private var elapsedSeconds: Double?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { item in
                            Text(item.text)
                                .frame(maxWidth: .infinity, alignment: item.fromUser ? .trailing : .leading)
                                .padding(12)
                                .background(item.fromUser ? Color.appRaised : Color.appLine.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        if let notice {
                            Text(notice).font(.footnote).foregroundStyle(.secondary)
                        }
                        if let elapsedSeconds {
                            Text(String(format: "Last response: %.1f s (on-device)", elapsedSeconds))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
                HStack {
                    TextField("Ask about training or recovery…", text: $question, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("coach.question")
                    Button("Send") {
                        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty, !busy else { return }
                        question = ""
                        messages.append(CoachMessage(text: text, fromUser: true))
                        Task { await respond(to: text) }
                    }
                    .disabled(busy || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("coach.send")
                }
                .padding()
            }
            .navigationTitle("STRAP Coach · Beta")
        }
    }

    @MainActor
    private func respond(to prompt: String) async {
        busy = true
        defer { busy = false }
        notice = nil
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            notice = "On-device AI is unavailable or still downloading on this iPhone."
            return
        }
        guard model.supportsLocale(Locale(identifier: "en_IN")) else {
            notice = "The installed model does not support this locale."
            return
        }
        let started = ContinuousClock.now
        do {
            let session = LanguageModelSession(instructions: """
            You are STRAP Coach, a concise and careful fitness information assistant.
            Answer in the user's supported language; English and Romanized Hindi are welcome
            only when the installed model supports the language.
            You have NO access to STRAP health measurements yet. Never invent HRV, RHR,
            sleep, recovery, training sessions, internet sources or medical diagnoses.
            Ask for measurements when needed. Do not claim to browse the web.
            """)
            let response = try await session.respond(to: prompt)
            elapsedSeconds = Double(started.duration(to: .now).components.seconds)
            messages.append(CoachMessage(text: response.content, fromUser: false))
        } catch {
            notice = "The local model could not answer this request. Try English or a shorter question."
        }
        #else
        notice = "This build does not include Apple's Foundation Models framework."
        #endif
    }
}

private struct CoachMessage: Identifiable {
    let id = UUID()
    let text: String
    let fromUser: Bool
}
