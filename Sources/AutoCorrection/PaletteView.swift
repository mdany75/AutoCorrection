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
            Divider()
            content
        }
        .frame(width: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
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
                    .foregroundStyle(.secondary)
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
            VStack(spacing: 2) {
                if model.selection.isEmpty { dictateRow("Dicter un texte", highlighted: true) }
                VStack(spacing: 2) {
                    row(.correct, key: .return, mods: [])
                    row(.polish, key: .return, mods: .command)
                    row(.email, key: .return, mods: .option)
                }
                .disabled(model.selection.isEmpty)
                if model.fromDictation { dictateRow("Redicter", highlighted: false) }
            }
            .padding(6)
            footer
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

    private func dictateRow(_ title: String, highlighted: Bool) -> some View {
        Button { model.onDictate() } label: {
            HStack(spacing: 10) {
                Image(systemName: "microphone").frame(width: 18)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13))
            .foregroundStyle(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle())
    }

    private func row(_ action: TextAction, key: KeyEquivalent, mods: EventModifiers) -> some View {
        Button { model.onRun(action) } label: {
            HStack(spacing: 10) {
                Image(systemName: action.icon).frame(width: 18)
                Text(action.title)
                Spacer()
                Text(action.shortcutLabel).foregroundStyle(.tertiary)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle())
        .keyboardShortcut(key, modifiers: mods)
    }
}

private struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
    }
}
