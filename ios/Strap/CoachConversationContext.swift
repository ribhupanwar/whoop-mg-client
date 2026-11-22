/// Keep private on-device replies and opted-in health context out of other
/// provider requests, including after the sharing switch is turned off.
struct CoachConversationContext {
    struct Scope: Hashable {
        let engine: String
        let sharesHealth: Bool
    }

    struct Turn: Equatable {
        enum Role: String { case user, assistant }
        let role: Role
        let text: String
    }

    private var exchanges: [Scope: [(question: String, answer: String)]] = [:]

    mutating func record(question: String, answer: String, for scope: Scope) {
        exchanges[scope] = Array(((exchanges[scope] ?? []) + [(question, answer)]).suffix(3))
    }

    func turns(for scope: Scope) -> [Turn] {
        (exchanges[scope] ?? []).flatMap {
            [Turn(role: .user, text: $0.question), Turn(role: .assistant, text: $0.answer)]
        }
    }
}
