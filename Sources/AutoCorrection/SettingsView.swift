import ServiceManagement
import SwiftUI

@MainActor
final class SettingsState: ObservableObject {
    @Published var apiKey = ""
    @Published var saved = Keychain.read()?.isEmpty == false
    @Published var trusted = Clipboard.isTrusted
    @Published var loggedIn: Bool?
    @Published var loginBusy = false
    @Published var loginError: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var launchError: String?

    func setLaunchAtLogin(_ on: Bool) {
        launchError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { launchError = error.localizedDescription }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if on && SMAppService.mainApp.status == .requiresApproval {
            launchError = "Autorisez AutoCorrection dans Réglages Système > Général > Ouverture."
        }
    }

    func refreshLogin() async { loggedIn = await ClaudeCodeClient.isLoggedIn() }

    func login() async {
        loginBusy = true
        loginError = nil
        do { try await ClaudeCodeClient.login() } catch { loginError = error.localizedDescription }
        await refreshLogin()
        loginBusy = false
    }
}

struct SettingsView: View {
    @AppStorage(Prefs.backendKey) private var backend = "api"
    @AppStorage(Prefs.modelKey) private var model = ""
    @AppStorage(Prefs.effortKey) private var effort = "low"
    @AppStorage(Prefs.replaceKey) private var replace = true
    @AppStorage(Prefs.hideIconKey) private var hideIcon = false
    @AppStorage(Prefs.styleKey) private var style = "glass"
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
                    let found = ClaudeCodeClient.locate() != nil
                    HStack {
                        Image(systemName: found && state.loggedIn == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(found && state.loggedIn == true ? .green : .orange)
                        Text(!found ? "Claude Code est introuvable sur ce Mac."
                             : state.loggedIn == true ? "Claude Code est connecté."
                             : state.loggedIn == false ? "Claude Code n'est pas connecté."
                             : "État de Claude Code inconnu.")
                        Spacer()
                        if found {
                            Button(state.loggedIn == true ? "Se reconnecter" : "Se connecter") { Task { await state.login() } }
                                .disabled(state.loginBusy)
                        }
                    }
                    if state.loginBusy {
                        Text("Terminez la connexion dans votre navigateur…").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let e = state.loginError {
                        Text(e).font(.footnote).foregroundStyle(.red)
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
                Picker("Style de la palette", selection: $style) {
                    Text("Liquid Glass").tag("glass")
                    Text("Standard").tag("standard")
                }
                Toggle("Remplacer le texte sélectionné par le résultat", isOn: $replace)
                Toggle("Ouvrir AutoCorrection au démarrage du Mac",
                       isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
                if let e = state.launchError {
                    Text(e).font(.footnote).foregroundStyle(.red)
                }
                Toggle("Cacher l'icône de la barre des menus", isOn: $hideIcon)
                if hideIcon {
                    Text("Le raccourci reste actif. Pour retrouver ces réglages, rouvrez AutoCorrection depuis Applications ou Spotlight.")
                        .font(.footnote).foregroundStyle(.secondary)
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
        .task(id: backend) { if backend == "claudeCode" { await state.refreshLogin() } }
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
