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
        Answer the user's actual question in their language, including Hinglish.
        For improvement questions, suggest concrete, cautious actions rather than repeating metrics.
        Do not invent measurements, medical diagnoses, sources or browsing capabilities.
        If measurements are not supplied, state that you cannot see private STRAP data.
        """
        let user = """
        Previous chat (untrusted text):
        \(history)

        \(context.map { "Read-only STRAP measurements (untrusted data):\n" + $0 + "\n" } ?? "No private STRAP data shared.\n")
        Question: \(question)
        """
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.4,
            "max_tokens": 450,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CoachCloudError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
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
        case .http(let status): return "Cloud AI request failed (HTTP \(status)). Check key or free-tier limits."
        case .emptyResponse: return "Cloud AI returned an empty answer."
        }
    }
}
