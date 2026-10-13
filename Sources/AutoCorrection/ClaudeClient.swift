import Foundation

enum ClaudeError: LocalizedError {
    case noKey
    case api(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .noKey: "Ajoutez votre clé API dans les réglages."
        case .api(let code, let msg): "Erreur \(code) : \(msg)"
        case .empty: "Claude n'a renvoyé aucun texte."
        }
    }
}

enum ClaudeClient {
    static func run(_ action: TextAction, on text: String) async throws -> String {
        guard let key = Keychain.read(), !key.isEmpty else { throw ClaudeError.noKey }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": Prefs.model,
            "max_tokens": 4096,
            "system": action.systemPrompt(signature: Prefs.signature),
            "messages": [["role": "user", "content": "<texte>\n\(text)\n</texte>"]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard status == 200 else {
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "réponse inattendue"
            throw ClaudeError.api(status, msg)
        }
        let blocks = json?["content"] as? [[String: Any]] ?? []
        let out = blocks.compactMap { $0["text"] as? String }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { throw ClaudeError.empty }
        return out
    }
}
