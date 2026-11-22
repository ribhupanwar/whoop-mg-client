/// Keep private on-device replies and opted-in health context out of other
/// provider requests, including after the sharing switch is turned off.
struct CoachConversationContext {
    struct Scope: Hashable {
        let engine: String
        let sharesHealth: Bool
    }

    private var exchanges: [Scope: [(question: String, answer: String)]] = [:]

    mutating func record(question: String, answer: String, for scope: Scope) {
        exchanges[scope] = Array(((exchanges[scope] ?? []) + [(question, answer)]).suffix(3))
    }

    func history(for scope: Scope) -> String {
        (exchanges[scope] ?? []).map { "User: \($0.question)\nAssistant: \($0.answer)" }.joined(separator: "\n")
    }
}
