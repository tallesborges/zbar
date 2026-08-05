import AppKit

/// Keyboard-driven action picker. Arrow keys and 1–9 move the selection, Return
/// activates it. Deliberately not an `NSTableView`: this is a handful of static
/// rows, and cell reuse would only add machinery.
final class ActionListView: NSView {
    var onActivate: (() -> Void)?
    var onCancel: (() -> Void)?

    private(set) var selectedIndex = 0
    private var rows: [RowView] = []

    init(actions: [TextAction]) {
        super.init(frame: .zero)

        let stack = NSStackView()
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

        for (index, action) in actions.enumerated() {
            let row = RowView(index: index, action: action)
            row.onClick = { [weak self] in
                self?.select(index)
                self?.onActivate?()
            }
            rows.append(row)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        select(0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var acceptsFirstResponder: Bool { true }

    func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        selectedIndex = index
        for (i, row) in rows.enumerated() { row.isSelected = (i == index) }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: select(min(selectedIndex + 1, rows.count - 1))
        case 126: select(max(selectedIndex - 1, 0))
        case 36, 76: onActivate?()
        case 53: onCancel?()
        default:
            if let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) }), digit >= 1 {
                select(digit - 1)
            } else {
                super.keyDown(with: event)
            }
        }
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

    init(index: Int, action: TextAction) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6

        title.stringValue = "\(index + 1)  \(action.title)"
        title.font = .systemFont(ofSize: 14, weight: .medium)
        subtitle.stringValue = action.subtitle
        subtitle.font = .systemFont(ofSize: 11)

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
