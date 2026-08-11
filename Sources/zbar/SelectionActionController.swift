import AppKit

/// Selection actions: grab the selected text, pick a preset, preview the result,
/// press Return to replace the original.
@MainActor
final class SelectionActionController: PanelController, NSTextFieldDelegate {
    private var actions: [TextAction] = []
    private var filtered: [TextAction] = []
    private let search = NSTextField()
    /// Unnumbered: digits belong to the filter field, so a leading "1" would be
    /// a shortcut and a search term at once.
    private let list = PickerListView(numbered: false)

    private var selection: String?
    private var pendingAction: TextAction?

    override func makeHeader() -> NSView {
        search.placeholderString = "Filter actions…"
        search.font = .systemFont(ofSize: 18)
        search.isBordered = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.delegate = self

        list.onActivate = { [weak self] in self?.confirm() }
        list.onCancel = { [weak self] in self?.hide() }

        let stack = NSStackView(views: [search, list])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        search.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        list.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// Focus stays in the filter field; the list is driven from there.
    override func focusView() -> NSView? { search }

    override func prepareForShow() {
        pendingAction = nil
        search.stringValue = ""
        actions = TextAction.loadAll()
        applyFilter("")
        setStatus(selectionSummary())
    }

    private func applyFilter(_ query: String) {
        filtered = actions.filter { $0.matches(query) }
        list.setRows(filtered.map(\.row))
    }

    /// Entry point for the hotkey. The selection must be captured *before* the
    /// panel opens, while the user's app is still frontmost and still owns the
    /// focused text.
    func trigger() {
        guard SelectionService.isTrusted else {
            // Show the panel anyway: a silent system prompt with no context is
            // confusing, and the picker makes it obvious what is being unlocked.
            SelectionService.requestTrust()
            selection = nil
            show()
            setStatus(
                "Accessibility permission needed — grant zbar in System Settings, then relaunch",
                isError: true
            )
            Log.error("selection action blocked: Accessibility not granted")
            return
        }

        selection = SelectionService.capture()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        show()
    }

    private func selectionSummary() -> String {
        guard let selection, !selection.isEmpty else {
            return "No text selected — select something first, then press the hotkey"
        }
        let preview = selection.replacingOccurrences(of: "\n", with: " ")
        let clipped = preview.count > 60 ? String(preview.prefix(60)) + "…" : preview
        return "\(selection.count) chars selected · \(clipped)"
    }

    private func confirm() {
        // Second Return, with a result on screen: commit it.
        if let result, let action = pendingAction, action.replaces {
            apply(result)
            return
        }
        guard filtered.indices.contains(list.selectedIndex) else { return }
        run(filtered[list.selectedIndex])
    }

    private func run(_ action: TextAction) {
        guard let selection, !selection.isEmpty else {
            setStatus("Nothing selected", isError: true)
            return
        }
        guard !isBusy else { return }

        pendingAction = action
        runBusy(status: "\(action.name)…") { [zdx] in
            try await zdx.ask(
                prompt: action.prompt(for: selection),
                model: action.model
            )
        }
    }

    override func idleHint() -> String? {
        guard result != nil else { return selectionSummary() }
        let replaces = pendingAction?.replaces ?? false
        return replaces
            ? "⏎ replace selection · ⌘C copy · ⌘S speak · ⎋ discard"
            : "⌘C copy · ⌘S speak · ⎋ close"
    }

    override func didFinish(_ text: String) {
        setStatus(idleHint())
        Log.info("selection action '\(pendingAction?.name ?? "?")' returned \(text.count) chars")
    }

    private func apply(_ text: String) {
        guard !text.isEmpty else {
            setStatus("Refusing to replace with empty text", isError: true)
            return
        }

        let target = targetApp
        panel.orderOut(nil)

        if SelectionService.replace(with: text, in: target) {
            Log.info("replaced selection in \(target?.localizedName ?? "target")")
        } else {
            Log.error("replace failed; keeping the result on screen")
            reopen(
                with: text,
                status: "Could not paste into the original app — ⌘C to copy instead",
                isError: true
            )
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        applyFilter(search.stringValue)
        layoutPanel()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            list.moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            list.moveSelection(by: -1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            confirm()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        default:
            return false
        }
    }
}
