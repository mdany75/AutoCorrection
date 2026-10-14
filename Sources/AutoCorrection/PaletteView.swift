import AppKit
import SwiftUI

enum PalettePhase: Equatable {
    case idle
    case listening
    case working(TextAction)
    case copied
    case error(String)
}

@Observable @MainActor
final class PaletteModel {
    var selection = ""
    var fromDictation = false
    var transcript = ""
    var levels = [Float](repeating: 0, count: 14)
    var phase: PalettePhase = .idle
    var onDictate: () -> Void = {}
    var onFinishDictation: () -> Void = {}
    var onCancelDictation: () -> Void = {}
    var onRun: (TextAction) -> Void = { _ in }
    var onClose: () -> Void = {}
    var onSettings: () -> Void = {}
    var onTextChange: () -> Void = {}

    func pushLevel(_ l: Float) { levels.removeFirst(); levels.append(l) }
}

enum PaletteLayout {
    static let width: CGFloat = 560
    static let tile: CGFloat = 98
    static let selectionFont = NSFont.systemFont(ofSize: 13)
    /// Largeur du texte : palette moins marges, icône et bouton de fermeture.
    static let textWidth: CGFloat = width - 28 - 20 - 10 - 25
    static let maxTextHeight: CGFloat = 12 * NSLayoutManager().defaultLineHeight(for: selectionFont)
}

/// Texte sélectionné, modifiable avant l'action : la zone grandit avec le texte jusqu'à 12 lignes, puis défile.
private struct SelectionText: View {
    @Bindable var model: PaletteModel
    var focused: FocusState<Bool>.Binding

    private var height: CGFloat {
        let h = (model.selection as NSString).boundingRect(
            with: CGSize(width: PaletteLayout.textWidth - 40, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: PaletteLayout.selectionFont]).height
        return min(ceil(h) + 2, PaletteLayout.maxTextHeight) + 8
    }

    var body: some View {
        TextEditor(text: $model.selection)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .focused(focused)
            .scrollIndicators(height >= PaletteLayout.maxTextHeight + 8 ? .automatic : .never)
            .frame(height: height)
            .padding(.leading, -5)
            .padding(.vertical, -4)
    }
}

struct PaletteView: View {
    let model: PaletteModel
    @AppStorage(Prefs.styleKey) private var style = "glass"
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(width: PaletteLayout.width)
        .modifier(WindowDrag())
        .onChange(of: model.selection) { model.onTextChange() }
        .modifier(PanelBackground(glass: style != "standard"))
    }

    private var isListening: Bool {
        if case .listening = model.phase { return true }
        return false
    }

    private var isWorking: Bool {
        if case .working = model.phase { return true }
        return false
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.fromDictation || isListening ? "microphone" : "sparkles")
                .font(.system(size: 16))
                .foregroundStyle(.tint)
                .padding(.top, 2)
            if case .listening = model.phase {
                Text("Dictée en cours…")
                    .foregroundStyle(.secondary)
            } else if model.selection.isEmpty {
                Text("Aucun texte sélectionné. Sélectionnez du texte, ou dictez-le.")
                    .foregroundStyle(.secondary)
            } else {
                SelectionText(model: model, focused: $editing)
            }
            Spacer(minLength: 0)
            if !isWorking {
                Button { model.onClose() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Fermer")
                .accessibilityLabel("Fermer")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            let hasText = !model.selection.isEmpty
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    tile(model.fromDictation ? "Redicter" : "Dicter", icon: "microphone", shortcut: "Espace",
                         enabled: !hasText || model.fromDictation, main: !hasText) { model.onDictate() }
                        .keyboardShortcut(editing ? nil : KeyboardShortcut(.space, modifiers: []))
                    tile(.correct, key: .return, mods: [], main: hasText)
                    tile(.polish, key: .return, mods: .command, main: false)
                    tile(.email, key: .return, mods: .option, main: false)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 8)
                footer
            }
        case .listening:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "microphone.fill").foregroundStyle(.red)
                    HStack(spacing: 3) {
                        ForEach(model.levels.indices, id: \.self) { i in
                            Capsule().fill(.tint).frame(width: 3, height: 4 + CGFloat(model.levels[i]) * 28)
                        }
                    }
                    .frame(height: 32)
                    .animation(.easeOut(duration: 0.1), value: model.levels)
                    Spacer()
                }
                Text(model.transcript.isEmpty ? "Parlez…" : model.transcript)
                    .font(.system(size: 14))
                    .foregroundStyle(model.transcript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                HStack {
                    Button { model.onFinishDictation() } label: { Label("Terminer", systemImage: "stop.fill") }
                        .keyboardShortcut(.defaultAction)
                    Button("Annuler") { model.onCancelDictation() }
                    Spacer()
                    Text("Espace ou ⏎ pour terminer").font(.system(size: 11)).foregroundStyle(.tertiary)
                    // Espace arrête aussi la dictée (bouton invisible, même action que « Terminer »).
                    Button("") { model.onFinishDictation() }
                        .keyboardShortcut(.space, modifiers: [])
                        .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
                }
            }
            .padding(14)
        case .working(let action):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(action.workingLabel).foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, minHeight: 90)
        case .copied:
            Label("Copié dans le presse-papiers", systemImage: "checkmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 90)
        case .error(let msg):
            VStack(spacing: 10) {
                Text(msg).font(.system(size: 13)).foregroundStyle(.red).multilineTextAlignment(.center)
                HStack {
                    Button("Réglages") { model.onSettings() }
                    Button("Fermer") { model.onClose() }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 90)
        }
    }

    private var footer: some View {
        HStack {
            Text(editing ? "⇧↵ : saut de ligne  ·  Esc pour fermer" : "Esc pour fermer")
            Spacer()
            Text(Prefs.replaceSelection ? "Le résultat remplace la sélection" : "Le résultat va dans le presse-papiers")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .padding(.top, 2)
    }

    private func tile(_ title: String, icon: String, shortcut: String, enabled: Bool, main: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 24))
                Text(title).font(.system(size: 11, weight: .medium))
                Text(shortcut).font(.system(size: 11)).opacity(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(TileStyle(glass: style != "standard", main: main))
        .frame(width: PaletteLayout.tile, height: PaletteLayout.tile)
        .disabled(!enabled)
    }

    private func tile(_ action: TextAction, key: KeyEquivalent, mods: EventModifiers, main: Bool) -> some View {
        tile(action.shortTitle, icon: action.icon, shortcut: action.shortcutLabel,
             enabled: !model.selection.isEmpty, main: main) { model.onRun(action) }
            .keyboardShortcut(key, modifiers: mods)
    }
}

/// Fond de la palette. Standard : matériau flou classique. Liquid Glass : vrai verre sur macOS 26, flou teinté avant.
/// Sombre en mode sombre, son négatif en mode clair.
private struct PanelBackground: ViewModifier {
    let glass: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Prefs.paletteRadius(glass ? "glass" : "standard"), style: .continuous)
        let dark = scheme == .dark
        if !glass {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.separator))
        } else if #available(macOS 26, *) {
            let tint = dark ? Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.45) : Color.white.opacity(0.55)
            content.glassEffect(.regular.tint(tint), in: shape)
        } else {
            let tint = dark ? Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.45) : Color.white.opacity(0.55)
            content
                .background(tint, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.5 : 0.95), .white.opacity(0.1)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
        }
    }
}

/// Gros carré. Standard : blanc. Liquid Glass : verre bombé, le carré principal plus lumineux.
/// Dans les deux styles, il ne devient bleu (plus foncé) qu'au survol de la souris.
private struct TileStyle: ButtonStyle {
    let glass: Bool
    let main: Bool

    func makeBody(configuration: Configuration) -> some View {
        TileBody(configuration: configuration, glass: glass, main: main)
    }

    private struct TileBody: View {
        let configuration: Configuration
        let glass: Bool
        let main: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.colorScheme) private var scheme
        @State private var hovering = false

        private static let blue = Color(red: 0.08, green: 0.36, blue: 0.86)
        private static let ink = Color(red: 0.08, green: 0.09, blue: 0.12)

        var body: some View {
            let hot = hovering && enabled
            Group {
                if glass { glassBody(hot: hot) } else { standardBody(hot: hot) }
            }
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: hot)
            .onHover { hovering = $0 }
        }

        private func standardBody(hot: Bool) -> some View {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            return configuration.label
                .foregroundStyle(hot ? Color.white : Self.ink)
                .background(hot ? Self.blue : Color.white.opacity(0.92), in: shape)
                .overlay(shape.strokeBorder(hot ? Color(red: 0.47, green: 0.69, blue: 1).opacity(0.75) : Color.black.opacity(0.1)))
        }

        @ViewBuilder
        private func glassBody(hot: Bool) -> some View {
            let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
            let dark = scheme == .dark
            let label = configuration.label.foregroundStyle(hot ? Color.white : Color.primary)
            if #available(macOS 26, *) {
                label.glassEffect(.regular.tint(hot ? Self.blue.opacity(0.9) : main ? Color.white.opacity(dark ? 0.35 : 0.6) : nil),
                                  in: shape)
            } else {
                let fill: Color = hot ? Self.blue : main ? .white.opacity(dark ? 0.3 : 0.7) : .white.opacity(dark ? 0.08 : 0.25)
                label
                    .background(fill, in: shape)
                    .background(.ultraThinMaterial, in: shape)
                    .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.6 : 0.95), .white.opacity(0.12)],
                                                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2))
            }
        }
    }
}

/// Déplace la fenêtre quand on glisse sur une zone sans bouton. `isMovableByWindowBackground` ne suffit pas :
/// la vue SwiftUI garde les clics pour elle.
private struct WindowDrag: ViewModifier {
    @State private var start: (mouse: NSPoint, origin: NSPoint)?

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { _ in
                    guard let w = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else { return }
                    let m = NSEvent.mouseLocation
                    if start == nil { start = (m, w.frame.origin) }
                    guard let s = start else { return }
                    w.setFrameOrigin(NSPoint(x: s.origin.x + m.x - s.mouse.x, y: s.origin.y + m.y - s.mouse.y))
                }
                .onEnded { _ in start = nil })
    }
}
