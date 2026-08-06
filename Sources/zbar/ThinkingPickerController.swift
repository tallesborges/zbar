import AppKit

/// The reasoning levels `zdx exec -t` accepts.
enum ThinkingLevel {
    static let all = ["off", "low", "medium", "high", "xhigh", "max"]

    static let hints: [String: String] = [
        "off": "no reasoning, fastest",
        "low": "a little thought",
        "medium": "balanced",
        "high": "works the problem",
        "xhigh": "slow and thorough",
        "max": "everything it has",
    ]
}

/// Reasoning-level picker: a short, fixed list, so no filtering.
@MainActor
final class ThinkingPickerController: PanelController {
    /// Called with the chosen level, or nil to fall back to the model default.
    var onSelect: ((String?) -> Void)?

    private let list = PickerListView()

    override func makeHeader() -> NSView {
        list.onActivate = { [weak self] in self?.choose() }
        list.onCancel = { [weak self] in self?.hide() }
        return list
    }

    override func focusView() -> NSView? { list }

    override func prepareForShow() {
        setStatus("↑↓ move · ⏎ choose · ⎋ cancel")
        let rows = [PickerRow(title: "Default", subtitle: "whatever the model uses")]
            + ThinkingLevel.all.map { PickerRow(title: $0, subtitle: ThinkingLevel.hints[$0] ?? "") }
        list.setRows(rows)
    }

    private func choose() {
        let index = list.selectedIndex
        // Row 0 is the "Default" sentinel; the rest map to `levels`.
        let selected = index == 0 ? nil : ThinkingLevel.all[safe: index - 1]
        hide()
        onSelect?(selected)
    }
}
