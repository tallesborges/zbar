import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Reads the current selection from whatever app is frontmost, and pastes a
/// replacement back into it.
///
/// Two strategies, in order: the Accessibility API, which is clean but only
/// works in apps that expose `AXSelectedText`, and a synthetic ⌘C, which works
/// almost everywhere but has to borrow the pasteboard.
enum SelectionService {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt if zbar is not trusted yet.
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Capture

    static func capture() -> String? {
        if let text = captureViaAccessibility(), !text.isEmpty { return text }
        return captureViaCopy()
    }

    private static func captureViaAccessibility() -> String? {
        let system = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let element = focused,
            CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return nil }

        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element as! AXUIElement, kAXSelectedTextAttribute as CFString, &value
            ) == .success
        else { return nil }

        return value as? String
    }

    /// Fallback for apps with no AX selected-text support. Borrows the
    /// pasteboard, so it always restores what was there before.
    private static func captureViaCopy() -> String? {
        let saved = PasteboardSnapshot.take()
        defer { saved.restore() }

        let before = NSPasteboard.general.changeCount
        postCommandKey(CGKeyCode(kVK_ANSI_C))

        guard waitForPasteboardChange(from: before) else { return nil }
        return NSPasteboard.general.string(forType: .string)
    }

    // MARK: - Replace

    /// Pastes `text` over the selection in `app`, restoring the pasteboard after.
    /// Returns false if `app` is no longer frontmost, so a slow request can never
    /// paste into the wrong window.
    @discardableResult
    static func replace(with text: String, in app: NSRunningApplication?) -> Bool {
        guard let app else { return false }

        app.activate()
        guard waitForFrontmost(app) else {
            Log.error("replace aborted: \(app.localizedName ?? "target") did not come forward")
            return false
        }

        let saved = PasteboardSnapshot.take()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        postCommandKey(CGKeyCode(kVK_ANSI_V))

        // The paste is asynchronous in the target app; restoring immediately can
        // swap the contents out from under it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { saved.restore() }
        return true
    }

    // MARK: - Event synthesis

    private static func postCommandKey(_ key: CGKeyCode) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func waitForPasteboardChange(from before: Int, timeout: TimeInterval = 0.6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSPasteboard.general.changeCount != before { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return false
    }

    private static func waitForFrontmost(_ app: NSRunningApplication, timeout: TimeInterval = 1.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication == app { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return false
    }
}

/// Full-fidelity pasteboard backup. Copying only the string would silently
/// destroy images, rich text, and file references the user had on the clipboard.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    static func take() -> PasteboardSnapshot {
        let items = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { store, type in
                store[type] = item.data(forType: type)
            }
        }
        return PasteboardSnapshot(items: items)
    }

    func restore() {
        NSPasteboard.general.clearContents()
        guard !items.isEmpty else { return }

        let restored = items.map { stored -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in stored {
                item.setData(data, forType: type)
            }
            return item
        }
        NSPasteboard.general.writeObjects(restored)
    }
}
