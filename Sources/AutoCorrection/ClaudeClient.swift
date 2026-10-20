import Foundation

enum ClaudeError: LocalizedError {
    case noKey
    case api(Int, String)
    case empty
    case noClaudeCode
    case claudeCode(String)

    var errorDescription: String? {
        switch self {
        case .noKey: "Ajoutez votre clé API dans les réglages."
        case .api(let code, let msg): "Erreur \(code) : \(msg)"
        case .empty: "Claude n'a renvoyé aucun texte."
        case .noClaudeCode: "Claude Code est introuvable. Installez-le, ou choisissez la clé API dans les réglages."
        case .claudeCode(let msg): msg
        }
    }
}

enum ClaudeClient {
    /// Enveloppe le texte de l'utilisateur entre balises <texte>, pour les deux moteurs. Une balise <texte> ou </texte>
    /// déjà présente dans le texte (toute casse, espaces compris) voit son « < » remplacé par « ‹ » : elle ne peut plus
    /// fermer l'enveloppe pour y glisser une fausse consigne. Le reste du texte ne change pas.
    static func envelope(_ text: String) -> String {
        let safe = text.replacingOccurrences(of: #"<(?=\s*/?\s*texte\b)"#, with: "‹",
                                             options: [.regularExpression, .caseInsensitive])
        return "<texte>\n\(safe)\n</texte>"
    }

    static func run(_ action: TextAction, on text: String) async throws -> String {
        try await run(system: action.systemPrompt(), on: text)
    }

    static func run(system: String, on text: String) async throws -> String {
        if Prefs.usesClaudeCode { return try await ClaudeCodeClient.run(system: system, on: text) }
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
            "output_config": ["effort": Prefs.effort],
            "system": system,
            "messages": [["role": "user", "content": envelope(text)]]
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

/// Passe par la commande `claude` de Claude Code : le texte est traité avec le forfait du compte connecté,
/// sans clé API. Aucun outil, aucune extension, aucun réglage de projet n'est chargé.
enum ClaudeCodeClient {
    static func locate() -> String? {
        let home = NSHomeDirectory()
        return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude", "\(home)/.npm-global/bin/claude", "\(home)/.bun/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func run(system: String, on text: String) async throws -> String {
        guard let exe = locate() else { throw ClaudeError.noClaudeCode }
        let args = ["-p", "--model", Prefs.model, "--effort", Prefs.effort, "--tools", "",
                    "--system-prompt", system,
                    "--no-session-persistence", "--disable-slash-commands",
                    "--setting-sources", "", "--strict-mcp-config"]
        let input = ClaudeClient.envelope(text)
        let (status, out, err) = try await execute(exe, args, input: input, timeout: 90)

        let result = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == 0, !result.isEmpty else {
            let detail = (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.lowercased().contains("authenticate") || detail.lowercased().contains("login") {
                throw ClaudeError.claudeCode("Claude Code n'est pas connecté. Dans le Terminal, lancez : claude auth login")
            }
            throw status == 0 ? ClaudeError.empty : ClaudeError.claudeCode("Claude Code a échoué : \(detail.prefix(200))")
        }
        return result
    }

    /// Lance `claude` avec ces arguments (dossier temporaire comme répertoire de travail), renvoie code, sortie et erreurs.
    private static func execute(_ exe: String, _ args: [String], input: String?, timeout: TimeInterval) async throws -> (Int32, String, String) {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Int32, String, String), Error>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            p.currentDirectoryURL = FileManager.default.temporaryDirectory
            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            p.standardInput = input == nil ? FileHandle.nullDevice : stdin
            p.standardOutput = stdout
            p.standardError = stderr
            p.terminationHandler = { proc in
                let o = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: (proc.terminationStatus, o, e))
            }
            do {
                try p.run()
                if let input {
                    stdin.fileHandleForWriting.write(Data(input.utf8))
                    try? stdin.fileHandleForWriting.close()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    /// nil si l'état est indéterminé (Claude Code introuvable ou réponse illisible).
    static func isLoggedIn() async -> Bool? {
        guard let exe = locate(),
              let (_, out, _) = try? await execute(exe, ["auth", "status"], input: nil, timeout: 20),
              let json = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any]
        else { return nil }
        return json["loggedIn"] as? Bool
    }

    /// Ouvre le navigateur pour connecter Claude Code au compte (équivaut à `claude auth login`).
    static func login() async throws {
        guard let exe = locate() else { throw ClaudeError.noClaudeCode }
        let (status, out, err) = try await execute(exe, ["auth", "login"], input: nil, timeout: 300)
        guard status == 0 else {
            let detail = (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ClaudeError.claudeCode("Connexion impossible : \(detail.prefix(200))")
        }
    }
}
