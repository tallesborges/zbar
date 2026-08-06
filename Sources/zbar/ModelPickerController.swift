import AppKit

/// Searchable model picker. Type to filter, arrows to move, Return to choose.
@MainActor
final class ModelPickerController: PanelController, NSTextFieldDelegate {
    /// Called with the chosen model id, or nil when the default is restored.
    var onSelect: ((String?) -> Void)?

    private let search = NSTextField()
    private let list = PickerListView(numbered: false)
    private var all: [ModelInfo] = []
    private var filtered: [ModelInfo] = []

    /// Sentinel row so the zdx default can be chosen back.
    private static let defaultRow = PickerRow(
        title: "Default",
        subtitle: "use the model from your zdx config"
    )

    override func makeHeader() -> NSView {
        search.placeholderString = "Filter models…"
        search.font = .systemFont(ofSize: 18)
        search.isBordered = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.delegate = self

        list.onActivate = { [weak self] in self?.choose() }
        list.onCancel = { [weak self] in self?.hide() }

        let stack = NSStackView(views: [search, list])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        search.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        list.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// Focus stays in the search field; the list is driven from there.
    override func focusView() -> NSView? { search }

    override func prepareForShow() {
        search.stringValue = ""
        setStatus("↑↓ move · ⏎ choose · ⎋ cancel")
        applyFilter("")

        Task { @MainActor in
            all = await zdx.models()
            applyFilter(search.stringValue)
            layoutPanel()
        }
    }

    private func applyFilter(_ query: String) {
        filtered = all.filter { $0.matches(query) }
        // Cap the list: the panel is a quick chooser, not a browser. Narrowing
        // the query is the way to reach anything further down.
        let capped = Array(filtered.prefix(8))
        list.setRows([Self.defaultRow] + capped.map(\.row))
    }

    private func choose() {
        let index = list.selectedIndex
        // Row 0 is the "Default" sentinel; everything after maps to `filtered`.
        let selected = index == 0 ? nil : filtered[safe: index - 1]?.id
        hide()
        onSelect?(selected)
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
            choose()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        default:
            return false
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
