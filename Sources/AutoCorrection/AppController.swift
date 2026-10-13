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
        if Keychain.read()?.isEmpty != false { openSettings() }

        Updater.shared.onState = { [weak self] _ in self?.refreshUpdateUI() }
        Updater.shared.startAutoChecks()
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
        updateItem = menu.addItem(withTitle: "Rechercher les mises à jour…", action: #selector(menuUpdate), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter AutoCorrection", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func setupPanel() {
        model.onRun = { [weak self] in self?.run($0) }
        model.onClose = { [weak self] in self?.hidePanel() }
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
    }

    private func hidePanel() {
        panel.orderOut(nil)
        model.phase = .idle
    }

    @objc private func menuOpenPalette() { Task { await togglePalette() } }
    @objc private func menuSettings() { openSettings() }

    // MARK: - Mises à jour

    @objc private func menuUpdate() {
        Task { @MainActor in
            let updater = Updater.shared
            if case .available(let release) = updater.state {
                await promptInstall(release)
                return
            }
            await updater.check()
            switch updater.state {
            case .available(let release): await promptInstall(release)
            case .upToDate: alert("AutoCorrection est à jour", "Version \(Updater.currentVersion).")
            case .error(let msg): alert("Vérification impossible", msg, settings: true)
            default: break
            }
        }
    }

    private func promptInstall(_ release: ReleaseInfo) async {
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = NSAlert()
        a.messageText = "La version \(release.version) est disponible"
        a.informativeText = "Vous utilisez la version \(Updater.currentVersion). L'app se fermera et se relancera après l'installation."
            + (notes.isEmpty ? "" : "\n\n" + String(notes.prefix(600)))
        a.addButton(withTitle: "Installer")
        a.addButton(withTitle: "Plus tard")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        await Updater.shared.install()
        if case .error(let msg) = Updater.shared.state { alert("Mise à jour impossible", msg) }
    }

    private func alert(_ title: String, _ text: String, settings: Bool = false) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "OK")
        if settings { a.addButton(withTitle: "Réglages") }
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertSecondButtonReturn { openSettings() }
    }

    private func refreshUpdateUI() {
        let symbol = "wand.and.stars"
        switch Updater.shared.state {
        case .available(let r):
            updateItem.title = "Installer la version \(r.version)…"
            updateItem.isEnabled = true
            statusItem.button?.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Mise à jour disponible")
        case .checking:
            updateItem.title = "Vérification en cours…"; updateItem.isEnabled = false
        case .downloading:
            updateItem.title = "Téléchargement de la mise à jour…"; updateItem.isEnabled = false
        case .installing:
            updateItem.title = "Installation en cours…"; updateItem.isEnabled = false
        default:
            updateItem.title = "Rechercher les mises à jour…"
            updateItem.isEnabled = true
            statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "AutoCorrection")
        }
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
        model.selection = await Clipboard.captureSelection() ?? ""
        busy = false
        showPanel()
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
