import AppKit

/// Borderless floating panel that can take keyboard focus.
///
/// `NSPanel` refuses key status when borderless, so `canBecomeKey` is overridden;
/// without it the text field would never accept typing.
final class KeyablePanel: NSPanel {
    var onCancel: (() -> Void)?
    var onCopy: (() -> Bool)?
    var onSpeak: (() -> Bool)?
    var onSession: (() -> Bool)?
    var onPickModel: (() -> Bool)?
    var onToggleTools: (() -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "m" where event.modifierFlags.contains(.shift) && onPickModel?() == true: return true
        case "t" where event.modifierFlags.contains(.shift) && onToggleTools?() == true: return true
        case "c" where onCopy?() == true: return true
        case "s" where onSpeak?() == true: return true
        case "\r" where onSession?() == true: return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}
