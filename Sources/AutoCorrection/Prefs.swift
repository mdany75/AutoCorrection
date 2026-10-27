import Foundation
import Security

enum Prefs {
    static let modelKey = "model"
    static let replaceKey = "replaceSelection"
    static let hideIconKey = "hideMenuBarIcon"
    static let styleKey = "paletteStyle"
    /// Rayon des coins de la palette selon le style (« standard » ou « glass »).
    static func paletteRadius(_ style: String) -> CGFloat { style == "standard" ? 14 : 30 }

    /// Raccourci de la palette (code, modificateurs, libellé).
    private static let hotKeyKeys = ["hotKeyCode", "hotKeyMods", "hotKeyLabel"]
    static let defaultHotKey = (code: 49, mods: 2048, label: "⌥Espace") // kVK_Space, optionKey

    static func hotKey() -> (code: Int, mods: Int, label: String) {
        let d = UserDefaults.standard, k = hotKeyKeys
        guard d.object(forKey: k[0]) != nil else { return defaultHotKey }
        return (d.integer(forKey: k[0]), d.integer(forKey: k[1]), d.string(forKey: k[2]) ?? "")
    }
    static func saveHotKey(code: Int, mods: Int, label: String) {
        let d = UserDefaults.standard, k = hotKeyKeys
        d.set(code, forKey: k[0]); d.set(mods, forKey: k[1]); d.set(label, forKey: k[2])
    }
    static func resetHotKey() {
        let d = UserDefaults.standard
        hotKeyKeys.forEach { d.removeObject(forKey: $0) }
    }

    /// Jusqu'à la 1.14, « dictationPresets » : des presets d'une autre forme, ignorés depuis.
    static let presetsKey = "presets"

    /// Presets de la palette, modifiables dans les réglages ; ceux d'origine tant que rien n'est enregistré.
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
