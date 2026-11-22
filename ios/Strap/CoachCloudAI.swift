import Foundation
import Security

/// Optional user-configured cloud model. No service key is bundled with STRAP.
/// This service is called only after the user explicitly selects Cloud AI.
@available(iOS 26.0, *)
enum CoachCloudAI {
    static let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    static let models = ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"]

    static func readKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ribhupanwar.strap.coach.groq",
            kSecAttrAccount as String: "user-api-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    static func saveKey(_ key: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ribhupanwar.strap.coach.groq",
            kSecAttrAccount as String: "user-api-key"
        ]
        SecItemDelete(base as CFDictionary)
        guard !key.isEmpty else { return true }
        var query = base
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func answer(question: String, history: String, context: String?, model: String) async throws -> String {
        let lines = history.components(separatedBy: "\n").filter { !$0.isEmpty }
        var turns: [(role: String, text: String)] = []
        for line in lines {
            if line.hasPrefix("User: ") {
                turns.append(("user", String(line.dropFirst(6))))
            } else if line.hasPrefix("Assistant: ") {
                turns.append(("assistant", String(line.dropFirst(11))))
            }
        }
        return try await answer(question: question, turns: turns, context: context, model: model)
    }

    static func answer(question: String, turns: [(role: String, text: String)], context: String?, model: String) async throws -> String {
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
            messagesPayload.append(["role": turn.role, "content": turn.text])
        }
        messagesPayload.append(["role": "user", "content": question])
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.4,
            "max_tokens": 450,
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

@available(iOS 26.0, *)
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
            case 404: return "Groq model or API route not found (HTTP 404). Try Llama 8B; check model availability."
            case 429: return "Groq free-tier rate limit reached (HTTP 429). Try again later or select Gemini."
            case 500...599: return "Groq service temporarily unavailable (HTTP \(status)). Try Gemini fallback."
            default: return "Groq request failed (HTTP \(status))."
            }
        case .emptyResponse: return "Cloud AI returned an empty answer."
        }
    }
}
