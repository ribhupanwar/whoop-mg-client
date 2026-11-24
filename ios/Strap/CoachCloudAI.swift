import Foundation

/// Optional user-configured cloud model. No service key is bundled with STRAP.
/// This service is called only after the user explicitly selects Cloud AI.
enum CoachCloudAI {
    static let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    static let models = ["openai/gpt-oss-120b", "openai/gpt-oss-20b"]

    static func readKey() -> String {
        CoachServiceKey.read("groq")
    }

    @discardableResult
    static func saveKey(_ key: String) -> Bool {
        CoachServiceKey.save(key, service: "groq")
    }

    static func answer(
        question: String, turns: [CoachConversationContext.Turn], context: String?, model: String
    ) async throws -> String {
        guard models.contains(model) else { throw CoachCloudError.invalidModel }
        let key = readKey()
        guard !key.isEmpty else { throw CoachCloudError.missingKey }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let instructions = """
        You are STRAP Coach, a concise, practical running and recovery assistant.
        Answer the user's actual question directly in their language, including Hinglish.
        For improvement questions, suggest concrete, cautious actions rather than repeating metrics.
        Do not invent measurements, medical diagnoses, sources or browsing capabilities.
        If measurements are not supplied, state that you cannot see private STRAP data.
        """
        var messagesPayload: [[String: String]] = [
            ["role": "system", "content": instructions]
        ]
        if let context, !context.isEmpty {
            messagesPayload.append([
                "role": "system",
                "content": "STRAP Local Health Data Snapshot (read-only confidential data):\n\(context)"
            ])
        }
        for turn in turns.suffix(8) {
            messagesPayload.append(["role": turn.role.rawValue, "content": turn.text])
        }
        messagesPayload.append(["role": "user", "content": question])
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.4,
            "max_completion_tokens": 2_048,
            "reasoning_effort": "low",
            "messages": messagesPayload
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            // Provider error codes are not interchangeable: 401=credentials,
            // 404=missing model/route, 429=quota. Never show secret response data.
            throw CoachCloudError.http(status)
        }
        let result = try JSONDecoder().decode(Completion.self, from: data)
        guard let text = result.choices.first?.message.content, !text.isEmpty else {
            throw CoachCloudError.emptyResponse
        }
        return text
    }

    private struct Completion: Decodable {
        let choices: [Choice]
        struct Choice: Decodable {
            let message: Message
        }
        struct Message: Decodable {
            let content: String?
        }
    }
}

enum CoachCloudError: LocalizedError {
    case invalidModel, missingKey, http(Int), emptyResponse
    var errorDescription: String? {
        switch self {
        case .invalidModel: return "Unknown AI model."
        case .missingKey: return "Add your own Groq API key in Coach settings."
        case .http(let status):
            switch status {
            case 400: return "Groq rejected this request (HTTP 400). Check selected model."
            case 401, 403: return "Groq authentication failed (HTTP \(status)). Verify your GroqCloud API key."
            case 404: return "Groq model or API route unavailable (HTTP 404). Check supported models in GroqCloud."
            case 429: return "Groq free-tier rate limit reached (HTTP 429). Try again later or select Gemini."
            case 500...599: return "Groq service temporarily unavailable (HTTP \(status)). Try Gemini fallback."
            default: return "Groq request failed (HTTP \(status))."
            }
        case .emptyResponse: return "Cloud AI returned an empty answer."
        }
    }
}
