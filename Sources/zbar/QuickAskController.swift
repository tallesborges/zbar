import AppKit

/// Quick-ask: type a question, get an answer, without leaving the current app.
@MainActor
final class QuickAskController: PanelController, NSTextFieldDelegate {
    private let input = NSTextField()

    override func makeHeader() -> NSView {
        input.placeholderString = "Ask zdx…"
        input.font = .systemFont(ofSize: 20)
        input.isBordered = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.delegate = self
        return input
    }

    override func focusView() -> NSView? { input }

    override func prepareForShow() {
        input.stringValue = ""
        setStatus(idleHint())
    }

    override func idleHint() -> String? {
        result == nil
            ? "⏎ ask · ⌘⏎ full session · ⎋ close"
            : "⏎ ask again · ⌘C copy · ⌘S speak · ⎋ close"
    }

    override func sessionSeed() -> String? {
        let typed = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? nil : typed
    }

    override func didFinish(_ text: String) {
        setStatus(idleHint())
        Log.info("quick-ask answered (\(text.count) chars)")
    }

    private func submit() {
        let prompt = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isBusy else { return }

        runBusy(status: "Asking zdx…") { [zdx] in
            try await zdx.ask(prompt: prompt)
        }
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            submit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        default:
            return false
        }
    }
}
