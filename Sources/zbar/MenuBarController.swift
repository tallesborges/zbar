import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let zdx = ZdxClient()
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

        askHotKeyRegistered = HotKeyCenter.shared.register(.quickAsk) { [weak self] in
            self?.quickAsk.toggle()
        }
        selectionHotKeyRegistered = HotKeyCenter.shared.register(.selectionAction) { [weak self] in
            self?.selectionAction.trigger()
        }

        Task { await zdx.resolve() }
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
        menu.addItem(ask)
        addDisabled("    \(HotKeyCenter.Shortcut.quickAsk.display)", to: menu)

        let selection = NSMenuItem(
            title: "Selection Actions",
            action: #selector(openSelectionActions),
            keyEquivalent: ""
        )
        selection.target = self
        selection.isEnabled = zdx.binary != nil
        menu.addItem(selection)
        addDisabled("    \(HotKeyCenter.Shortcut.selectionAction.display)", to: menu)

        menu.addItem(.separator())

        let session = NSMenuItem(
            title: "New zdx Session",
            action: #selector(openSession),
            keyEquivalent: ""
        )
        session.target = self
        session.isEnabled = zdx.binary != nil
        menu.addItem(session)
        addDisabled("    fresh temp folder · ⌘⏎ from Quick Ask", to: menu)

        menu.addItem(.separator())

        let log = NSMenuItem(title: "Open log", action: #selector(openLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)

        let quit = NSMenuItem(title: "Quit zbar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func addDisabled(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func statusTitle() -> String {
        guard zdx.binary != nil else { return "⚠ zdx not found" }
        return zdx.version.map { "zdx \($0)" } ?? "zdx ready"
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

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.fileURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
