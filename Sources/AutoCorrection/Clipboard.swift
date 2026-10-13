import AppKit
import ApplicationServices

struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pb: NSPasteboard = .general) {
        items = (pb.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let data = item.data(forType: t) { d[t] = data } }
            return d
        }
    }

    func restore(to pb: NSPasteboard = .general) {
        pb.clearContents()
        let objs = items.map { d -> NSPasteboardItem in
            let i = NSPasteboardItem()
            for (t, data) in d { i.setData(data, forType: t) }
            return i
        }
        if !objs.isEmpty { pb.writeObjects(objs) }
    }
}

@MainActor
enum Clipboard {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForAccess() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private static func sendCommand(key: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Copie la sélection de l'app au premier plan, puis rétablit le presse-papiers d'origine.
    static func captureSelection() async -> String? {
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pb)
        let before = pb.changeCount

        try? await Task.sleep(for: .milliseconds(120))
        sendCommand(key: 8) // C

        var text: String?
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(25))
            if pb.changeCount != before {
                text = pb.string(forType: .string)
                break
            }
        }
        snapshot.restore(to: pb)
        guard let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return t
    }

    /// Colle le texte à la place de la sélection, puis rétablit le presse-papiers d'origine.
    static func paste(_ text: String) async {
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pb)
        pb.clearContents()
        pb.setString(text, forType: .string)
        try? await Task.sleep(for: .milliseconds(60))
        sendCommand(key: 9) // V
        try? await Task.sleep(for: .milliseconds(500))
        snapshot.restore(to: pb)
    }

    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
