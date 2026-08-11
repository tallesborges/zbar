import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let zdx = ZdxClient()
    private let settings = Settings.load()
    private lazy var quickAsk = QuickAskController(zdx: zdx)
    private lazy var selectionAction = SelectionActionController(zdx: zdx)

    private var askHotKeyRegistered = false
    private var selectionHotKeyRegistered = false

    override init() {
        super.init()
        configureButton()
        menu.delegate = self
        statusItem.menu = menu
        Log.info("zbar launched (accessibility trusted: \(SelectionService.isTrusted))")

        // Seeds the action files on first run, so the folder exists to be edited
        // without having to open the picker first.
        Log.info("\(TextAction.loadAll().count) actions in \(TextAction.directory.path)")
        Log.info("shortcuts: quick ask \(settings.quickAsk.display), selection \(settings.selectionActions.display)")
        Log.info(
            "quick ask defaults: model \(settings.model ?? "zdx default")"
                + ", thinking \(settings.thinking ?? "model default")"
                + ", tools \(settings.tools ? "on" : "off")"
                + ", skills \(settings.skills ? "on" : "off")"
        )

        askHotKeyRegistered = HotKeyCenter.shared.register(settings.quickAsk) { [weak self] in
            self?.quickAsk.toggle()
        }
        selectionHotKeyRegistered = HotKeyCenter.shared.register(settings.selectionActions) { [weak self] in
            self?.selectionAction.trigger()
        }

        Task { await zdx.resolve() }

        // Build both panels now rather than on the first hotkey: each one loads
        // its Markdown web view's document shell, and that is the only slow part
        // of showing a panel.
        _ = quickAsk
        _ = selectionAction
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "bolt.horizontal.circle",
            accessibilityDescription: "zbar"
        )
        button.image?.isTemplate = true
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        addDisabled(statusTitle(), to: menu)
        if !askHotKeyRegistered || !selectionHotKeyRegistered {
            addDisabled("⚠ a hotkey is already taken by another app", to: menu)
        }
        if !SelectionService.isTrusted {
            let grant = NSMenuItem(
                title: "⚠ Grant Accessibility for selection actions…",
                action: #selector(requestAccessibility),
                keyEquivalent: ""
            )
            grant.target = self
            menu.addItem(grant)
        }

        menu.addItem(.separator())

        let ask = NSMenuItem(title: "Quick Ask", action: #selector(openQuickAsk), keyEquivalent: "")
        ask.target = self
        ask.isEnabled = zdx.binary != nil
        apply(settings.quickAsk, to: ask)
        menu.addItem(ask)

        let selection = NSMenuItem(
            title: "Selection Actions",
            action: #selector(openSelectionActions),
            keyEquivalent: ""
        )
        selection.target = self
        selection.isEnabled = zdx.binary != nil
        apply(settings.selectionActions, to: selection)
        menu.addItem(selection)

        menu.addItem(.separator())

        let session = NSMenuItem(
            title: "New zdx Session",
            action: #selector(openSession),
            keyEquivalent: ""
        )
        session.target = self
        session.isEnabled = zdx.binary != nil
        menu.addItem(session)

        menu.addItem(.separator())

        let actions = NSMenuItem(
            title: "Edit Actions…",
            action: #selector(openActionsFolder),
            keyEquivalent: ""
        )
        actions.target = self
        menu.addItem(actions)

        let config = NSMenuItem(
            title: "Edit Settings…",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        config.target = self
        menu.addItem(config)

        let log = NSMenuItem(title: "Open log", action: #selector(openLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)

        let quit = NSMenuItem(title: "Quit zbar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// Shows the shortcut right-aligned, the way macOS renders menu shortcuts.
    ///
    /// Status-item menus are not searched for key equivalents while closed, so
    /// this is display only and cannot double-fire against the Carbon hotkey.
    private func apply(_ shortcut: HotKeyCenter.Shortcut, to item: NSMenuItem) {
        item.keyEquivalent = shortcut.menuKeyEquivalent
        item.keyEquivalentModifierMask = shortcut.modifiers
    }

    private func addDisabled(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func statusTitle() -> String {
        guard zdx.binary != nil else { return "⚠ zdx not found" }
        guard let version = zdx.version else { return "zdx ready" }

        // `zdx --version` prints "zdx 0.8.0+build.1785934696.g4f92…"; the build
        // metadata is noise in a menu, and the name is already in the title.
        let number = version
            .split(separator: " ").last
            .map { $0.split(separator: "+").first.map(String.init) ?? String($0) }
        return number.map { "zdx \($0)" } ?? "zdx ready"
    }

    // MARK: - Actions

    func showQuickAsk() {
        quickAsk.show()
    }

    @objc private func openQuickAsk() {
        quickAsk.show()
    }

    @objc private func openSelectionActions() {
        selectionAction.trigger()
    }

    @objc private func openSession() {
        guard let binary = zdx.binary else { return }
        do {
            _ = try SessionLauncher.launch(zdx: binary, seed: nil)
        } catch {
            Log.error("could not open session: \(error.localizedDescription)")
        }
    }

    @objc private func requestAccessibility() {
        SelectionService.requestTrust()
    }

    @objc private func openActionsFolder() {
        // Re-seeds the folder if it was deleted, so the menu item always lands
        // somewhere useful rather than opening nothing.
        _ = TextAction.loadAll()
        NSWorkspace.shared.open(TextAction.directory)
    }

    @objc private func openSettings() {
        // Re-seeds the file if it was deleted, so the item always opens
        // something editable.
        _ = Settings.load()
        NSWorkspace.shared.open(Settings.file)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.fileURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
