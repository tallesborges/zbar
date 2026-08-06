import AppKit

/// One selectable line in a picker.
struct PickerRow {
    let title: String
    let subtitle: String
}

/// Keyboard-driven list. Arrow keys move the selection, Return activates it, and
/// 1–9 jump directly when the list is short enough to number.
///
/// Deliberately not an `NSTableView`: these lists are short and fully visible,
/// so cell reuse would only add machinery.
final class PickerListView: NSView {
    var onActivate: (() -> Void)?
    var onCancel: (() -> Void)?

    private(set) var selectedIndex = 0
    private var rowViews: [RowView] = []
    private let stack = NSStackView()
    /// Numbered rows only make sense when every row has a distinct digit.
    private var numbered = true

    init(numbered: Bool = true) {
        self.numbered = numbered
        super.init(frame: .zero)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var acceptsFirstResponder: Bool { true }

    var count: Int { rowViews.count }

    /// Rebuilt on every change, so edits to the underlying source show up
    /// immediately.
    func setRows(_ rows: [PickerRow]) {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()

        for (index, row) in rows.enumerated() {
            let view = RowView(index: numbered ? index : nil, row: row)
            view.onClick = { [weak self] in
                self?.select(index)
                self?.onActivate?()
            }
            rowViews.append(view)
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        select(0)
    }

    func select(_ index: Int) {
        guard rowViews.indices.contains(index) else { return }
        selectedIndex = index
        for (i, view) in rowViews.enumerated() { view.isSelected = (i == index) }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: select(min(selectedIndex + 1, rowViews.count - 1))
        case 126: select(max(selectedIndex - 1, 0))
        case 36, 76: onActivate?()
        case 53: onCancel?()
        default:
            if numbered, let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) }), digit >= 1 {
                select(digit - 1)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    /// Moves the selection without stealing first responder, for lists driven
    /// from a search field.
    func moveSelection(by offset: Int) {
        select(min(max(selectedIndex + offset, 0), rowViews.count - 1))
    }
}

private final class RowView: NSView {
    var onClick: (() -> Void)?

    var isSelected = false {
        didSet {
            layer?.backgroundColor = isSelected
                ? NSColor.selectedContentBackgroundColor.cgColor
                : NSColor.clear.cgColor
            title.textColor = isSelected ? .white : .labelColor
            subtitle.textColor = isSelected ? .white.withAlphaComponent(0.8) : .secondaryLabelColor
        }
    }

    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")

    init(index: Int?, row: PickerRow) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6

        let prefix = index.map { $0 < 9 ? "\($0 + 1)  " : "   " } ?? ""
        title.stringValue = prefix + row.title
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        subtitle.stringValue = row.subtitle
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
