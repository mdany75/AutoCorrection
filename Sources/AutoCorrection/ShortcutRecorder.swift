import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class ShortcutRecorderState: ObservableObject {
    @Published var label = Prefs.hotKey.label
    @Published var recording = false
    @Published var message: String?
    private var monitor: Any?

    func start() {
        guard !recording else { return }
        recording = true
        message = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.handle(event)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    func reset() {
        stop()
        let d = Prefs.defaultHotKey
        if HotKeyCenter.apply(d.code, d.mods) {
            Prefs.resetHotKey()
            label = d.label
            message = nil
        } else {
            message = "Ce raccourci est déjà utilisé par une autre app."
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { stop(); return }

        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods = 0
        if f.contains(.control) { mods |= controlKey }
        if f.contains(.option) { mods |= optionKey }
        if f.contains(.shift) { mods |= shiftKey }
        if f.contains(.command) { mods |= cmdKey }
        guard mods != 0 else {
            message = "Ajoutez au moins une touche ⌃ ⌥ ⇧ ou ⌘."
            return
        }

        let code = Int(event.keyCode)
        let text = Self.symbols(for: f) + Self.keyName(for: event)
        stop()
        if HotKeyCenter.apply(code, mods) {
            Prefs.saveHotKey(code: code, mods: mods, label: text)
            label = text
            message = nil
        } else {
            message = "\(text) est déjà utilisé par une autre app. Essayez-en un autre."
        }
    }

    private static func symbols(for f: NSEvent.ModifierFlags) -> String {
        (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "")
            + (f.contains(.shift) ? "⇧" : "") + (f.contains(.command) ? "⌘" : "")
    }

    private static func keyName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Espace"
        case kVK_Return: return "↵"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1...kVK_F20 where event.charactersIgnoringModifiers?.isEmpty != false: return "F\(event.keyCode)"
        default:
            let c = event.charactersIgnoringModifiers?.uppercased() ?? ""
            return c.isEmpty ? "Touche \(event.keyCode)" : c
        }
    }
}

struct ShortcutRecorder: View {
    @StateObject private var state = ShortcutRecorderState()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Raccourci global")
                Spacer()
                Button(state.recording ? "Tapez le raccourci… (Esc pour annuler)" : state.label) {
                    state.recording ? state.stop() : state.start()
                }
                Button("Rétablir ⌥Espace") { state.reset() }
                    .disabled(!state.recording && state.label == Prefs.defaultHotKey.label)
            }
            if let m = state.message {
                Text(m).font(.footnote).foregroundStyle(.red)
            }
        }
        .onDisappear { state.stop() }
    }
}
