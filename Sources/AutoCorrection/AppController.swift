import AppKit
import Carbon.HIToolbox
import SwiftUI

final class PalettePanel: NSPanel {
    var onCancel: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel() }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var updateItem: NSMenuItem!
    private var panel: PalettePanel!
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?
    private let model = PaletteModel()
    private var busy = false
    private let dictation = Dictation()
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPanel()

        HotKeyCenter.apply = { [weak self] code, mods in self?.registerHotKey(code: code, mods: mods) ?? false }
        let saved = Prefs.hotKey
        if !registerHotKey(code: saved.code, mods: saved.mods) {
            NSLog("AutoCorrection : impossible d'enregistrer %@", saved.label)
        }

        if !Clipboard.isTrusted { Clipboard.promptForAccess() }
        if !Prefs.usesClaudeCode, Keychain.read()?.isEmpty != false { openSettings() }
    }

    /// Remplace le raccourci actif. En cas d'échec, l'ancien reste en place.
    private func registerHotKey(code: Int, mods: Int) -> Bool {
        let previous = hotKey
        hotKey = nil // libère l'ancien avant d'enregistrer le nouveau
        let new = HotKey(keyCode: code, modifiers: mods) { [weak self] in
            Task { @MainActor in await self?.togglePalette() }
        }
        if let new {
            hotKey = new
            return true
        }
        hotKey = previous.flatMap { _ in
            let o = Prefs.hotKey
            return HotKey(keyCode: o.code, modifiers: o.mods) { [weak self] in
                Task { @MainActor in await self?.togglePalette() }
            }
        }
        return false
    }

    // MARK: - Interface

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "AutoCorrection")
        let menu = NSMenu()
        menu.addItem(withTitle: "Ouvrir la palette", action: #selector(menuOpenPalette), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Réglages…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        let version = menu.addItem(withTitle: "Version \(Updater.currentVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        updateItem = menu.addItem(withTitle: "Rechercher les mises à jour…", action: #selector(menuUpdate), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter AutoCorrection", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func setupPanel() {
        model.onRun = { [weak self] in self?.run($0) }
        model.onClose = { [weak self] in self?.hidePanel() }
        model.onDictate = { [weak self] in self?.startDictation() }
        model.onFinishDictation = { [weak self] in Task { @MainActor in await self?.finishDictation() } }
        model.onCancelDictation = { [weak self] in self?.cancelDictation() }
        model.onSettings = { [weak self] in self?.hidePanel(); self?.openSettings() }

        panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 200),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCancel = { [weak self] in self?.hidePanel() }
        panel.contentView = NSHostingView(rootView: PaletteView(model: model))
    }

    private func showPanel() {
        guard let hosting = panel.contentView as? NSHostingView<PaletteView> else { return }
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let f = screen?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.midY + f.height * 0.12 - size.height,
                              width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)

        // Un clic en dehors de la palette (ouverte par erreur) la ferme, sauf pendant le traitement.
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.panel.isVisible else { return }
                    if case .working = self.model.phase { return }
                    self.hidePanel()
                }
            }
        }
    }

    /// Redimensionne la palette à son contenu en gardant son bord supérieur en place.
    private func fitPanel() {
        guard let hosting = panel.contentView as? NSHostingView<PaletteView> else { return }
        DispatchQueue.main.async { [self] in
            let size = hosting.fittingSize
            var f = panel.frame
            f.origin.y = f.maxY - size.height
            f.size = size
            panel.setFrame(f, display: true, animate: false)
        }
    }

    private func hidePanel() {
        dictation.cancel()
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        panel.orderOut(nil)
        model.phase = .idle
    }

    @objc private func menuOpenPalette() { Task { await togglePalette() } }
    @objc private func menuSettings() { openSettings() }

    // MARK: - Mises à jour

    @objc private func menuUpdate() {
        Task { @MainActor in
            updateItem.isEnabled = false
            defer { updateItem.title = "Rechercher les mises à jour…"; updateItem.isEnabled = true }
            updateItem.title = "Vérification en cours…"
            do {
                guard let release = try await Updater.checkForUpdate() else {
                    alert("AutoCorrection est à jour", "Vous utilisez la dernière version (\(Updater.currentVersion)).")
                    return
                }
                let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                let a = NSAlert()
                a.messageText = "La version \(release.version) est disponible"
                a.informativeText = "Vous utilisez la version \(Updater.currentVersion). L'app se fermera et se relancera après l'installation."
                    + (notes.isEmpty ? "" : "\n\n" + String(notes.prefix(600)))
                a.addButton(withTitle: "Installer")
                a.addButton(withTitle: "Plus tard")
                NSApp.activate(ignoringOtherApps: true)
                guard a.runModal() == .alertFirstButtonReturn else { return }
                try await Updater.install(release) { [weak self] in self?.updateItem.title = $0 }
            } catch {
                alert("Mise à jour impossible", error.localizedDescription)
            }
        }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    private func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Réglages d'AutoCorrection"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        settingsWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Flux principal

    private func togglePalette() async {
        if panel.isVisible { hidePanel(); return }
        guard !busy else { return }
        guard Clipboard.isTrusted else {
            Clipboard.promptForAccess()
            openSettings()
            return
        }
        busy = true
        model.phase = .idle
        model.fromDictation = false
        model.selection = await Clipboard.captureSelection() ?? ""
        busy = false
        showPanel()
    }

    // MARK: - Dictée

    private func startDictation() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let err = await Dictation.authorize() { model.phase = .error(err); fitPanel(); return }
            model.transcript = ""
            model.levels = [Float](repeating: 0, count: model.levels.count)
            do {
                try dictation.start(
                    onText: { [weak self] in self?.model.transcript = $0 },
                    onLevel: { [weak self] in self?.model.pushLevel($0) },
                    onError: { [weak self] msg in
                        self?.dictation.cancel()
                        self?.model.phase = .error(msg)
                        self?.fitPanel()
                    })
                model.phase = .listening
            } catch {
                model.phase = .error(error.localizedDescription)
            }
            fitPanel()
        }
    }

    private func finishDictation() async {
        let text = await dictation.finish()
        if text.isEmpty {
            model.phase = .error("Aucune parole détectée. Vérifiez le microphone et réessayez.")
        } else {
            model.selection = text
            model.fromDictation = true
            model.phase = .idle
        }
        fitPanel()
    }

    private func cancelDictation() {
        dictation.cancel()
        model.phase = .idle
        fitPanel()
    }

    private func run(_ action: TextAction) {
        let source = model.selection
        guard !source.isEmpty, model.phase == .idle else { return }
        model.phase = .working(action)
        Task { @MainActor in
            do {
                let result = try await ClaudeClient.run(action, on: source)
                if Prefs.replaceSelection {
                    hidePanel()
                    try? await Task.sleep(for: .milliseconds(150))
                    await Clipboard.paste(result)
                } else {
                    Clipboard.copy(result)
                    model.phase = .copied
                    try? await Task.sleep(for: .milliseconds(900))
                    hidePanel()
                }
            } catch {
                model.phase = .error(error.localizedDescription)
            }
        }
    }
}
