import Foundation
import Security

enum Prefs {
    static let modelKey = "model"
    static let replaceKey = "replaceSelection"
    static let hideIconKey = "hideMenuBarIcon"

    static let hotKeyCodeKey = "hotKeyCode"
    static let hotKeyModsKey = "hotKeyMods"
    static let hotKeyLabelKey = "hotKeyLabel"
    static let defaultHotKey = (code: 49, mods: 2048, label: "⌥Espace") // kVK_Space, optionKey

    static var hotKey: (code: Int, mods: Int, label: String) {
        let d = UserDefaults.standard
        guard d.object(forKey: hotKeyCodeKey) != nil else { return defaultHotKey }
        return (d.integer(forKey: hotKeyCodeKey), d.integer(forKey: hotKeyModsKey),
                d.string(forKey: hotKeyLabelKey) ?? "")
    }
    static func saveHotKey(code: Int, mods: Int, label: String) {
        let d = UserDefaults.standard
        d.set(code, forKey: hotKeyCodeKey); d.set(mods, forKey: hotKeyModsKey); d.set(label, forKey: hotKeyLabelKey)
    }
    static func resetHotKey() {
        let d = UserDefaults.standard
        [hotKeyCodeKey, hotKeyModsKey, hotKeyLabelKey].forEach { d.removeObject(forKey: $0) }
    }

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
