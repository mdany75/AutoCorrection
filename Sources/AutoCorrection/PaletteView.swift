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

    func pushLevel(_ l: Float) { levels.removeFirst(); levels.append(l) }
}

struct PaletteView: View {
    let model: PaletteModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(width: 440)
        .modifier(GlassPanel())
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
                Text(model.selection)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
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
                HStack(spacing: 8) {
                    tile(model.fromDictation ? "Redicter" : "Dicter", icon: "microphone", shortcut: "Espace",
                         prominent: !hasText, enabled: !hasText || model.fromDictation) { model.onDictate() }
                        .keyboardShortcut(.space, modifiers: [])
                    tile(.correct, key: .return, mods: [], prominent: hasText)
                    tile(.polish, key: .return, mods: .command, prominent: false)
                    tile(.email, key: .return, mods: .option, prominent: false)
                }
                .padding(.horizontal, 12)
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
            Text("Esc pour fermer")
            Spacer()
            Text(Prefs.replaceSelection ? "Le résultat remplace la sélection" : "Le résultat va dans le presse-papiers")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .padding(.top, 2)
    }

    private func tile(_ title: String, icon: String, shortcut: String, prominent: Bool, enabled: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 24))
                Text(title).font(.system(size: 11, weight: .medium))
                Text(shortcut).font(.system(size: 11)).opacity(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(TileStyle(prominent: prominent))
        .aspectRatio(1, contentMode: .fit)
        .disabled(!enabled)
    }

    private func tile(_ action: TextAction, key: KeyEquivalent, mods: EventModifiers, prominent: Bool) -> some View {
        tile(action.shortTitle, icon: action.icon, shortcut: action.shortcutLabel, prominent: prominent,
             enabled: !model.selection.isEmpty) { model.onRun(action) }
            .keyboardShortcut(key, modifiers: mods)
    }
}

/// Fond « verre » : Liquid Glass sur macOS 26, flou teinté avant. Sombre en mode sombre, son négatif en mode clair.
private struct GlassPanel: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        let dark = scheme == .dark
        let tint = dark ? Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.45) : Color.white.opacity(0.55)
        if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(tint), in: shape)
        } else {
            content
                .background(tint, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(dark ? 0.22 : 0.85)))
        }
    }
}

/// Gros carré : voile clair en mode sombre, voile sombre en mode clair ; le bouton principal reste bleu.
private struct TileStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        TileBody(configuration: configuration, prominent: prominent)
    }

    private struct TileBody: View {
        let configuration: Configuration
        let prominent: Bool
        @Environment(\.colorScheme) private var scheme
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
            let dark = scheme == .dark
            let fill: Color = prominent ? Color(red: 0.24, green: 0.55, blue: 1).opacity(0.5)
                : dark ? .white.opacity(0.1) : Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.07)
            let stroke: Color = prominent ? Color(red: 0.47, green: 0.69, blue: 1).opacity(0.75)
                : dark ? .white.opacity(0.2) : Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.14)
            configuration.label
                .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                .background(fill, in: shape)
                .overlay(shape.strokeBorder(stroke))
                .opacity(enabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
        }
    }
}
