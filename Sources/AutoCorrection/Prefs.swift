import Foundation
import Security

enum Prefs {
    static let modelKey = "model"
    static let replaceKey = "replaceSelection"
    static let hideIconKey = "hideMenuBarIcon"
    static let styleKey = "paletteStyle"
    /// Rayon des coins de la palette selon le style (« standard » ou « glass »).
    static func paletteRadius(_ style: String) -> CGFloat { style == "standard" ? 14 : 30 }

    /// Clés des préférences d'un raccourci (code, modificateurs, libellé).
    private static func hotKeyKeys(_ kind: HotKeyKind) -> [String] {
        switch kind {
        case .palette: ["hotKeyCode", "hotKeyMods", "hotKeyLabel"]
        case .dictation: ["dictationHotKeyCode", "dictationHotKeyMods", "dictationHotKeyLabel"]
        }
    }

    static func defaultHotKey(_ kind: HotKeyKind) -> (code: Int, mods: Int, label: String) {
        switch kind {
        case .palette: (49, 2048, "⌥Espace") // kVK_Space, optionKey
        case .dictation: (2, 6400, "⌃⌥⌘D") // kVK_ANSI_D, controlKey | optionKey | cmdKey
        }
    }

    static func hotKey(_ kind: HotKeyKind) -> (code: Int, mods: Int, label: String) {
        let d = UserDefaults.standard, k = hotKeyKeys(kind)
        guard d.object(forKey: k[0]) != nil else { return defaultHotKey(kind) }
        return (d.integer(forKey: k[0]), d.integer(forKey: k[1]), d.string(forKey: k[2]) ?? "")
    }
    static func saveHotKey(_ kind: HotKeyKind, code: Int, mods: Int, label: String) {
        let d = UserDefaults.standard, k = hotKeyKeys(kind)
        d.set(code, forKey: k[0]); d.set(mods, forKey: k[1]); d.set(label, forKey: k[2])
    }
    static func resetHotKey(_ kind: HotKeyKind) {
        let d = UserDefaults.standard
        hotKeyKeys(kind).forEach { d.removeObject(forKey: $0) }
    }

    // Dictée sans palette
    static let dictationPresetKey = "dictationPreset"
    static let dictationSoundsKey = "dictationSounds"
    static let dictationSilenceKey = "dictationSilence"
    static let dictationMaxKey = "dictationMaxMinutes"
    static let presetsKey = "dictationPresets"

    /// Identifiant du preset appliqué au texte dicté, ou `Preset.rawID` pour l'écrire tel quel.
    static var dictationPresetID: String {
        let v = UserDefaults.standard.string(forKey: dictationPresetKey) ?? ""
        return v == Preset.rawID || presets.contains { $0.id == v } ? v : Preset.defaults[0].id
    }
    static var dictationSounds: Bool {
        UserDefaults.standard.object(forKey: dictationSoundsKey) as? Bool ?? true
    }
    /// Durées de silence proposées pour arrêter l'écoute, en secondes.
    static let dictationSilences = [3, 5, 7, 10]
    /// Secondes de silence avant l'arrêt automatique ; 0 : seulement par un nouvel appui sur le raccourci.
    static var dictationSilence: Int {
        let v = UserDefaults.standard.integer(forKey: dictationSilenceKey)
        return dictationSilences.contains(v) ? v : 0
    }
    static var dictationMaxMinutes: Int {
        let v = UserDefaults.standard.integer(forKey: dictationMaxKey)
        return v > 0 ? v : 2
    }

    /// Presets de la dictée, modifiables dans les réglages ; ceux d'origine tant que rien n'est enregistré.
    static var presets: [Preset] {
        guard let data = UserDefaults.standard.data(forKey: presetsKey),
              let list = try? JSONDecoder().decode([Preset].self, from: data), !list.isEmpty
        else { return Preset.defaults }
        return list
    }
    /// Les presets d'origine ne sont pas enregistrés : ils suivent ainsi les améliorations des versions suivantes.
    static func savePresets(_ list: [Preset]) {
        guard list != Preset.defaults else { return resetPresets() }
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: presetsKey)
    }
    static func resetPresets() { UserDefaults.standard.removeObject(forKey: presetsKey) }

    static let defaultModel = "claude-haiku-5-5"

    /// Modèles proposés dans les réglages (identifiant, libellé). Un identifiant saisi autrement reste utilisable.
    static let models = [("claude-haiku-5-5", "Haiku 5.5 : le plus économique"),
                         ("claude-sonnet-5-5", "Sonnet 5.5 : équilibré"),
                         ("claude-opus-5-5", "Opus 5.5 : le plus puissant")]

    static let effortKey = "effort"
    static let efforts = [("low", "Faible"), ("medium", "Moyen"), ("high", "Élevé")]
    static var effort: String {
        let v = UserDefaults.standard.string(forKey: effortKey) ?? ""
        return efforts.contains { $0.0 == v } ? v : "low"
    }

    static var model: String {
        let v = UserDefaults.standard.string(forKey: modelKey) ?? ""
        return v.isEmpty ? defaultModel : v
    }
    static var replaceSelection: Bool {
        UserDefaults.standard.object(forKey: replaceKey) as? Bool ?? true
    }
    static let backendKey = "backend"
    /// Moteur : « api » (clé API Anthropic) ou « claudeCode » (commande claude, forfait Max).
    static var usesClaudeCode: Bool {
        UserDefaults.standard.string(forKey: backendKey) == "claudeCode"
    }
}

enum Keychain {
    private static let service = "ca.dany.AutoCorrection.apikey"
    private static let account = "anthropic"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String) -> Bool {
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return true }
        var q = base
        q[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}
