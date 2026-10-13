import SwiftUI

@MainActor
final class SettingsState: ObservableObject {
    @Published var apiKey = ""
    @Published var saved = Keychain.read()?.isEmpty == false
    @Published var trusted = Clipboard.isTrusted
    @Published var ghToken = ""
    @Published var ghSaved = Keychain.read(.github)?.isEmpty == false
}

struct SettingsView: View {
    @AppStorage(Prefs.modelKey) private var model = ""
    @AppStorage(Prefs.replaceKey) private var replace = true
    @AppStorage(Prefs.signatureKey) private var signature = "Dany"
    @AppStorage(Prefs.autoUpdateKey) private var autoUpdate = true
    @StateObject private var state = SettingsState()
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Form {
            Section("Connexion à Claude") {
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
                TextField("Modèle", text: $model, prompt: Text(Prefs.defaultModel))
            }
            Section("Comportement") {
                ShortcutRecorder()
                Toggle("Remplacer le texte sélectionné par le résultat", isOn: $replace)
                TextField("Signature des courriels", text: $signature)
            }
            Section("Mises à jour") {
                SecureField("Jeton GitHub (lecture seule)", text: $state.ghToken,
                            prompt: Text(state.ghSaved ? "Jeton enregistré dans le Trousseau" : "github_pat_…"))
                HStack {
                    Button("Enregistrer le jeton") {
                        let t = state.ghToken.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { Keychain.write(t, to: .github); state.ghSaved = true; state.ghToken = "" }
                    }
                    .disabled(state.ghToken.trimmingCharacters(in: .whitespaces).isEmpty)
                    if state.ghSaved {
                        Button("Supprimer") { Keychain.write("", to: .github); state.ghSaved = false }
                    }
                }
                Toggle("Vérifier automatiquement chaque jour", isOn: $autoUpdate)
                HStack {
                    Text(updateStatus).foregroundStyle(updateStatusIsError ? .red : .secondary)
                    Spacer()
                    if case .available(let r) = updater.state {
                        Button("Installer \(r.version)") { Task { await updater.install() } }
                    } else {
                        Button("Vérifier maintenant") { Task { await updater.check() } }
                            .disabled(updater.isBusy || !state.ghSaved)
                    }
                }
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

    private var updateStatusIsError: Bool {
        if case .error = updater.state { return true }
        return false
    }

    private var updateStatus: String {
        switch updater.state {
        case .idle: "Version \(Updater.currentVersion)"
        case .checking: "Vérification en cours…"
        case .upToDate: "Version \(Updater.currentVersion) : à jour"
        case .available(let r): "La version \(r.version) est disponible"
        case .downloading: "Téléchargement…"
        case .installing: "Installation… l'app va se relancer"
        case .error(let m): m
        }
    }
}
