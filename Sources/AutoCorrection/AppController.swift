import AppKit
import Carbon.HIToolbox
import SwiftUI

final class PalettePanel: NSPanel {
    var onCancel: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel() }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var updateItem: NSMenuItem!
    private var presetMenu: NSMenu!
    private var panel: PalettePanel!
    private var hotKey: HotKey?
    private var dictationHotKey: HotKey?
    private var settingsWindow: NSWindow?
    private let model = PaletteModel()
    private var busy = false
    private var outsideClickMonitor: Any?

    // Dictée sans palette
    private enum QuickState { case idle, starting, listening, processing }
    private var quickState = QuickState.idle
    private let quickDictation = Dictation()
    private var quickText = ""
    private var quickStarted = Date()
    private var lastSpeech = Date()
    private var quickTimer: Timer?
    private var quickTask: Task<Void, Never>?
    private var escMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPanel()
        applyIconVisibility()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyIconVisibility() }
        }

        HotKeyCenter.apply = { [weak self] kind, code, mods in self?.registerHotKey(kind, code: code, mods: mods) ?? false }
        for kind in [HotKeyKind.palette, .dictation] {
            let saved = Prefs.hotKey(kind)
            if !registerHotKey(kind, code: saved.code, mods: saved.mods) {
                NSLog("AutoCorrection : impossible d'enregistrer %@", saved.label)
            }
        }

        if !Clipboard.isTrusted { Clipboard.promptForAccess() }
        if !Prefs.usesClaudeCode, Keychain.read()?.isEmpty != false { openSettings() }
    }

    /// Pendant une dictée sans palette, l'icône reste visible même si elle est cachée : c'est le seul témoin de l'écoute.
    private func applyIconVisibility() {
        let visible = !UserDefaults.standard.bool(forKey: Prefs.hideIconKey) || quickState != .idle
        if statusItem.isVisible != visible { statusItem.isVisible = visible }
    }

    /// Icône cachée : rouvrir l'app (Finder, Spotlight) ouvre les réglages, d'où on peut la remontrer.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    /// Remplace le raccourci actif. En cas d'échec, l'ancien reste en place.
    private func registerHotKey(_ kind: HotKeyKind, code: Int, mods: Int) -> Bool {
        let action: () -> Void = { [weak self] in
            Task { @MainActor in
                switch kind {
                case .palette: await self?.togglePalette()
                case .dictation: self?.toggleQuickDictation()
                }
            }
        }
        let hadPrevious = (kind == .palette ? hotKey : dictationHotKey) != nil
        setHotKey(kind, nil) // libère l'ancien avant d'enregistrer le nouveau
        if let new = HotKey(keyCode: code, modifiers: mods, action: action) {
            setHotKey(kind, new)
            return true
        }
        if hadPrevious {
            let o = Prefs.hotKey(kind)
            setHotKey(kind, HotKey(keyCode: o.code, modifiers: o.mods, action: action))
        }
        return false
    }

    private func setHotKey(_ kind: HotKeyKind, _ new: HotKey?) {
        switch kind {
        case .palette: hotKey = new
        case .dictation: dictationHotKey = new
        }
    }

    // MARK: - Interface

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "AutoCorrection")
        let menu = NSMenu()
        menu.addItem(withTitle: "Ouvrir la palette", action: #selector(menuOpenPalette), keyEquivalent: "").target = self
        presetMenu = NSMenu()
        presetMenu.delegate = self
        menu.addItem(withTitle: "Style de la dictée", action: nil, keyEquivalent: "").submenu = presetMenu
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
        model.onTextChange = { [weak self] in self?.fitPanel() }
        model.onSettings = { [weak self] in self?.hidePanel(); self?.openSettings() }

        panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: PaletteLayout.width, height: 200),
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
        let hosting = NSHostingView(rootView: PaletteView(model: model))
        // Coins arrondis au niveau de la fenêtre : l'ombre système suit alors la forme arrondie, sans coins carrés.
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = Prefs.paletteRadius(UserDefaults.standard.string(forKey: Prefs.styleKey) ?? "glass")
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
    }

    private func showPanel() {
        guard let hosting = panel.contentView as? NSHostingView<PaletteView> else { return }
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let f = screen?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.midY + f.height * 0.12 - size.height,
                              width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        refreshShadow()

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
            refreshShadow()
        }
    }

    /// L'ombre de la fenêtre est calculée une fois : après un changement de taille ou d'affichage, il faut la recalculer.
    private func refreshShadow() {
        DispatchQueue.main.async { [panel] in
            panel?.contentView?.layer?.cornerRadius = Prefs.paletteRadius(UserDefaults.standard.string(forKey: Prefs.styleKey) ?? "glass")
            panel?.invalidateShadow()
        }
    }

    private func hidePanel() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        panel.orderOut(nil)
        model.phase = .idle
    }

    @objc private func menuOpenPalette() { Task { await togglePalette() } }
    @objc private func menuSettings() { openSettings() }

    /// Sous-menu « Style de la dictée » : refait à chaque ouverture, les presets se modifient dans les réglages.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === presetMenu else { return }
        menu.removeAllItems()
        let current = Prefs.dictationPresetID
        let label = menu.addItem(withTitle: "Raccourci : \(Prefs.hotKey(.dictation).label)", action: nil, keyEquivalent: "")
        label.isEnabled = false
        menu.addItem(.separator())
        let choices = [(Preset.rawID, "Tel quel (sans IA)")] + Prefs.dictationPresets.map { ($0.id, $0.name) }
        for (id, name) in choices {
            let item = menu.addItem(withTitle: name, action: #selector(menuChoosePreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = id == current ? .on : .off
        }
    }

    @objc private func menuChoosePreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        UserDefaults.standard.set(id, forKey: Prefs.dictationPresetKey)
    }

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
        guard !busy, quickState == .idle else { return }
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

    // MARK: - Dictée sans palette

    /// Raccourci de la dictée : un premier appui lance l'écoute, le suivant l'arrête et écrit le texte au curseur.
    /// Logi Options+ envoie une frappe instantanée, pas un maintien : d'où la bascule plutôt que « tenir pour parler ».
    private func toggleQuickDictation() {
        switch quickState {
        case .idle: startQuickDictation()
        case .listening: finishQuickDictation()
        case .starting, .processing: break
        }
    }

    private func startQuickDictation() {
        guard Clipboard.isTrusted else {
            Clipboard.promptForAccess()
            openSettings()
            return
        }
        if panel.isVisible { hidePanel() }
        quickState = .starting
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let err = await Dictation.authorize() { quickFailed(err); return }
            quickText = ""
            do {
                try await quickDictation.start(
                    onText: { [weak self] text in
                        guard let self, text != quickText else { return }
                        quickText = text
                        lastSpeech = Date()
                    },
                    onLevel: { _ in },
                    onError: { [weak self] in self?.quickFailed($0) })
            } catch {
                quickFailed(error.localizedDescription)
                return
            }
            quickState = .listening
            quickStarted = Date()
            lastSpeech = Date()
            setQuickIcon("mic.fill")
            play("Tink")
            installEscMonitor()
            quickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkQuickLimits() }
            }
        }
    }

    /// Arrêt automatique : durée maximale atteinte, ou silence prolongé (si le réglage est actif).
    /// Avant le premier mot, le silence toléré est d'au moins 8 secondes, le temps de commencer à parler.
    private func checkQuickLimits() {
        guard quickState == .listening else { return }
        let silence = Double(Prefs.dictationSilence)
        let allowed = quickText.isEmpty ? max(silence, 8) : silence
        if Date().timeIntervalSince(quickStarted) >= Double(Prefs.dictationMaxMinutes * 60)
            || (silence > 0 && Date().timeIntervalSince(lastSpeech) >= allowed) {
            finishQuickDictation()
        }
    }

    private func finishQuickDictation() {
        guard quickState == .listening else { return }
        quickState = .processing
        quickTimer?.invalidate()
        quickTimer = nil
        setQuickIcon("hourglass")
        play("Pop")
        quickTask = Task { @MainActor in
            let text = await quickDictation.finish()
            guard !Task.isCancelled else { return }
            guard !text.isEmpty else { endQuickDictation(); return } // rien entendu : rien à écrire

            var result = text
            var failure: String?
            let id = Prefs.dictationPresetID
            if id != Preset.rawID, let preset = Prefs.dictationPresets.first(where: { $0.id == id }) {
                do { result = try await ClaudeClient.run(system: preset.prompt(dictation: true), on: text) }
                catch { failure = error.localizedDescription }
            }
            guard !Task.isCancelled else { return }
            endQuickDictation()
            // En cas d'échec de Claude, le texte reconnu est écrit tel quel : la dictée n'est jamais perdue.
            await Clipboard.paste(result)
            if let failure {
                play("Basso")
                alert("Texte écrit sans traitement", "Claude n'a pas pu traiter la dictée : \(failure)")
            }
        }
    }

    /// Esc pendant l'écoute ou le traitement : rien n'est écrit.
    private func cancelQuickDictation() {
        guard quickState != .idle else { return }
        quickTask?.cancel()
        quickDictation.cancel()
        endQuickDictation()
        play("Bottle")
    }

    private func quickFailed(_ message: String) {
        guard quickState == .starting || quickState == .listening else { return }
        quickDictation.cancel()
        endQuickDictation()
        play("Basso")
        alert("Dictée impossible", message)
    }

    private func endQuickDictation() {
        quickState = .idle
        quickTask = nil
        quickTimer?.invalidate()
        quickTimer = nil
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        setQuickIcon(nil)
    }

    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            Task { @MainActor in self?.cancelQuickDictation() }
        }
    }

    /// Micro pendant l'écoute, sablier pendant le traitement, baguette au repos.
    private func setQuickIcon(_ symbol: String?) {
        statusItem.button?.image = NSImage(systemSymbolName: symbol ?? "wand.and.stars", accessibilityDescription: "AutoCorrection")
        applyIconVisibility()
    }

    private func play(_ sound: String) {
        guard Prefs.dictationSounds else { return }
        NSSound(named: NSSound.Name(sound))?.play()
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
