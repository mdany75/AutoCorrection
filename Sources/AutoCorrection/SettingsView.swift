import SwiftUI

@MainActor
final class SettingsState: ObservableObject {
    @Published var apiKey = ""
    @Published var saved = Keychain.read()?.isEmpty == false
    @Published var trusted = Clipboard.isTrusted
}

struct SettingsView: View {
    @AppStorage(Prefs.backendKey) private var backend = "api"
    @AppStorage(Prefs.modelKey) private var model = ""
    @AppStorage(Prefs.effortKey) private var effort = "low"
    @AppStorage(Prefs.replaceKey) private var replace = true
    @StateObject private var state = SettingsState()

    var body: some View {
        Form {
            Section("Connexion à Claude") {
                Picker("Moteur", selection: $backend) {
                    Text("Clé API Anthropic").tag("api")
                    Text("Claude Code (forfait du compte)").tag("claudeCode")
                }
                if backend == "api" {
                    SecureField("Clé API Anthropic", text: $state.apiKey, prompt: Text(state.saved ? "Clé enregistrée dans le Trousseau" : "sk-ant-…"))
                    HStack {
                        Button("Enregistrer la clé") {
                            let k = state.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !k.isEmpty { Keychain.write(k); state.saved = true; state.apiKey = "" }
                        }
                        .disabled(state.apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        if state.saved {
                            Button("Supprimer") { Keychain.write(""); state.saved = false }
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: ClaudeCodeClient.locate() != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(ClaudeCodeClient.locate() != nil ? .green : .orange)
                        Text(ClaudeCodeClient.locate() != nil
                             ? "Claude Code trouvé. S'il n'est pas connecté : claude auth login (Terminal)."
                             : "Claude Code est introuvable sur ce Mac.")
                    }
                }
                Picker("Modèle", selection: modelChoice) {
                    ForEach(Prefs.models, id: \.0) { Text($0.1).tag($0.0) }
                    if !Prefs.models.contains(where: { $0.0 == modelChoice.wrappedValue }) {
                        Text(modelChoice.wrappedValue).tag(modelChoice.wrappedValue)
                    }
                }
                Picker("Réflexion", selection: $effort) {
                    ForEach(Prefs.efforts, id: \.0) { Text($0.1).tag($0.0) }
                }
                Text("Faible : rapide et économique, suffisant pour corriger. Élevé : plus lent et plus cher, pour les textes délicats.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Comportement") {
                ShortcutRecorder()
                Toggle("Remplacer le texte sélectionné par le résultat", isOn: $replace)
            }
            Section("Autorisation macOS") {
                HStack {
                    Image(systemName: state.trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(state.trusted ? .green : .orange)
                    Text(state.trusted ? "Accessibilité accordée" : "Accessibilité requise pour lire et remplacer le texte")
                    Spacer()
                    if !state.trusted {
                        Button("Autoriser") {
                            Clipboard.promptForAccess()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            state.trusted = Clipboard.isTrusted
        }
    }

    private var modelChoice: Binding<String> {
        Binding(get: { model.isEmpty ? Prefs.defaultModel : model }, set: { model = $0 })
    }
}
