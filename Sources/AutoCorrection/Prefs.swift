import Foundation
import Security

enum Prefs {
    static let modelKey = "model"
    static let replaceKey = "replaceSelection"
    static let signatureKey = "signature"

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

    static var model: String {
        let v = UserDefaults.standard.string(forKey: modelKey) ?? ""
        return v.isEmpty ? defaultModel : v
    }
    static var replaceSelection: Bool {
        UserDefaults.standard.object(forKey: replaceKey) as? Bool ?? true
    }
    static var signature: String {
        UserDefaults.standard.string(forKey: signatureKey) ?? "Dany"
    }

    static let autoUpdateKey = "autoCheckUpdates"
    static let lastUpdateCheckKey = "lastUpdateCheck"
    static var autoCheckUpdates: Bool {
        UserDefaults.standard.object(forKey: autoUpdateKey) as? Bool ?? true
    }
}

enum Keychain {
    /// Un secret du Trousseau : la clé API Anthropic (par défaut) ou le jeton GitHub des mises à jour.
    struct Slot {
        let service: String
        let account: String
        static let anthropic = Slot(service: "ca.dany.AutoCorrection.apikey", account: "anthropic")
        static let github = Slot(service: "ca.dany.AutoCorrection.github", account: "github")
    }

    private static func base(_ slot: Slot) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: slot.service,
         kSecAttrAccount as String: slot.account]
    }

    static func read(_ slot: Slot = .anthropic) -> String? {
        var q = base(slot)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, to slot: Slot = .anthropic) -> Bool {
        SecItemDelete(base(slot) as CFDictionary)
        guard !value.isEmpty else { return true }
        var q = base(slot)
        q[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}
