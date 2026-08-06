import AppKit

/// Quick-ask: type a question, get an answer, keep asking follow-ups — all
/// without leaving the current app.
@MainActor
final class QuickAskController: PanelController, NSTextFieldDelegate {
    /// One panel session. The thread is what gives follow-up turns their
    /// context; the directory is scratch space for that thread.
    private struct Conversation {
        let root: URL
        let threadID: String
    }

    private let input = NSTextField()
    private var conversation: Conversation?
    private var transcript: [(question: String, answer: String)] = []

    /// Overrides the configured default for this panel session only.
    private var model: String?
    private var thinking: String?
    private var tools = false
    private var keepConversation = false

    private lazy var thinkingPicker: ThinkingPickerController = {
        let picker = ThinkingPickerController(zdx: zdx)
        picker.onSelect = { [weak self] chosen in
            guard let self else { return }
            thinking = chosen
            show()
        }
        return picker
    }()

    override func pickThinking() -> Bool {
        keepConversation = true
        panel.orderOut(nil)
        thinkingPicker.show()
        return true
    }

    private lazy var modelPicker: ModelPickerController = {
        let picker = ModelPickerController(zdx: zdx)
        picker.onSelect = { [weak self] chosen in
            guard let self else { return }
            model = chosen ?? Settings.load().model
            show()
        }
        return picker
    }()

    override func pickModel() -> Bool {
        // The panel is reopened after choosing, so the conversation has to
        // survive that round trip.
        keepConversation = true
        panel.orderOut(nil)
        modelPicker.show()
        return true
    }

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

        if keepConversation {
            keepConversation = false
            if !transcript.isEmpty { setResult(renderedTranscript()) }
            setStatus(idleHint())
            return
        }

        endConversation()
        let settings = Settings.load()
        model = settings.model
        thinking = settings.thinking
        tools = settings.tools
        setStatus(idleHint())
    }

    override func hide() {
        endConversation()
        super.hide()
    }

    override func idleHint() -> String? {
        let keys = transcript.isEmpty
            ? "⏎ ask · ⌘⏎ session · ⇧⌘M model · ⇧⌘T thinking · ⎋ close"
            : "⏎ follow up · ⌘C copy · ⌘S speak · ⇧⌘M model · ⇧⌘T thinking · ⎋ close"
        return keys + "\n" + configSummary()
    }

    /// What this conversation is actually running with. The model prefers the
    /// value zdx reported using, since leaving it unset is the common case and
    /// only zdx knows what the config resolved to.
    private func configSummary() -> String {
        let effectiveModel = model ?? zdx.lastModel
        var parts = [effectiveModel ?? "default model"]
        parts.append(thinking.map { "thinking \($0)" } ?? "thinking default")
        parts.append(tools ? "tools on" : "tools off")
        return parts.joined(separator: "  ·  ")
    }

    override func sessionSeed() -> String? {
        let typed = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? nil : typed
    }

    override func didFinish(_ text: String) {
        if var last = transcript.popLast() {
            last.answer = text
            transcript.append(last)
        }
        // `result` stays the latest answer, so copy and speak act on that, while
        // the panel shows the whole exchange.
        setResult(renderedTranscript())
        setStatus(idleHint())
        Log.info("quick-ask turn \(transcript.count) answered (\(text.count) chars)")
    }

    private func submit() {
        let question = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isBusy else { return }

        let session = conversation ?? startConversation()
        transcript.append((question: question, answer: ""))
        input.stringValue = ""

        runBusy(status: transcript.count == 1 ? "Asking zdx…" : "Thinking…") { [zdx, model, thinking, tools] in
            try await zdx.ask(
                prompt: question,
                root: session.root,
                thread: session.threadID,
                model: model,
                thinking: thinking,
                tools: tools
            )
        }
    }

    private func renderedTranscript() -> String {
        transcript
            .map { "› \($0.question)\n\n\($0.answer)" }
            .joined(separator: "\n\n\n")
    }

    private func startConversation() -> Conversation {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zbar-chat-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let session = Conversation(root: root, threadID: "zbar-\(UUID().uuidString)")
        conversation = session
        return session
    }

    private func endConversation() {
        if let conversation {
            try? FileManager.default.removeItem(at: conversation.root)
        }
        conversation = nil
        transcript.removeAll()
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
