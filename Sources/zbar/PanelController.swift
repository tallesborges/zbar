import AppKit

/// Shared chrome for zbar's floating panels: a subclass-supplied header, an
/// optional result area, and a status row. Quick-ask and selection actions only
/// differ in their header and what submitting means.
@MainActor
class PanelController: NSObject, NSWindowDelegate {
    let panel: KeyablePanel
    let zdx: ZdxClient

    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let resultView = NSTextView()
    private let resultScroll = NSScrollView()
    private let separator = NSBox()
    private let speech = SpeechPlayer()
    private var resultHeight: NSLayoutConstraint!
    private var built = false

    private(set) var isBusy = false
    private(set) var isSpeaking = false
    private(set) var result: String?
    private var previousApp: NSRunningApplication?

    static let width: CGFloat = 640
    static let padding: CGFloat = 18
    static let maxResultHeight: CGFloat = 420

    init(zdx: ZdxClient) {
        self.zdx = zdx
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.level = .floating
        panel.isOpaque = true
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
        panel.onCopy = { [weak self] in self?.copyResult() ?? false }
        panel.onSpeak = { [weak self] in self?.speakResult() ?? false }
        panel.onSession = { [weak self] in self?.openSession() ?? false }
        panel.onPickModel = { [weak self] in self?.pickModel() ?? false }
        panel.onPickThinking = { [weak self] in self?.pickThinking() ?? false }

        speech.onFinish = { [weak self] in
            self?.isSpeaking = false
            self?.setStatus(self?.idleHint())
        }
    }

    // MARK: - Subclass hooks

    /// The panel's top section. Built once, on first show.
    func makeHeader() -> NSView { NSView() }

    /// View that should hold keyboard focus when the panel opens.
    func focusView() -> NSView? { nil }

    /// Called before each show, to reset subclass state.
    func prepareForShow() {}

    // MARK: - Chrome

    private func buildIfNeeded() {
        guard !built else { return }
        built = true

        let container = NSView()
        container.wantsLayer = true
        // Opaque chrome only — no NSVisualEffectView, matching house style.
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 12
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.masksToBounds = true

        let header = makeHeader()
        header.translatesAutoresizingMaskIntoConstraints = false

        separator.boxType = .separator
        separator.isHidden = true
        separator.translatesAutoresizingMaskIntoConstraints = false

        resultView.isEditable = false
        resultView.isSelectable = true
        resultView.drawsBackground = false
        resultView.font = .systemFont(ofSize: 14)
        resultView.textContainerInset = .zero
        resultView.textContainer?.lineFragmentPadding = 0

        resultScroll.documentView = resultView
        resultScroll.drawsBackground = false
        resultScroll.hasVerticalScroller = true
        resultScroll.autohidesScrollers = true
        resultScroll.isHidden = true
        resultScroll.translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(header)
        container.addSubview(separator)
        container.addSubview(resultScroll)
        container.addSubview(spinner)
        container.addSubview(statusLabel)

        let pad = Self.padding
        resultHeight = resultScroll.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: pad),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pad),

            separator.topAnchor.constraint(equalTo: header.bottomAnchor, constant: pad),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            resultScroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: pad),
            resultScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            resultScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pad),
            resultHeight,

            spinner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            spinner.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 12),

            statusLabel.topAnchor.constraint(equalTo: resultScroll.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 6),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pad),
            statusLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        panel.contentView = container
    }

    // MARK: - Show / hide

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        buildIfNeeded()
        previousApp = NSWorkspace.shared.frontmostApplication

        isBusy = false
        result = nil
        speech.stop()
        isSpeaking = false
        setResult(nil)
        setStatus(nil)
        spinner.stopAnimation(nil)
        prepareForShow()
        layoutPanel()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if let focus = focusView() { panel.makeFirstResponder(focus) }
    }

    func hide() {        guard panel.isVisible else { return }
        speech.stop()
        isSpeaking = false
        panel.orderOut(nil)
        reactivatePreviousApp()
        previousApp = nil
    }

    /// The app the user was in when the panel opened. Selection actions need it
    /// to paste back into the right place.
    var targetApp: NSRunningApplication? { previousApp }

    func reactivatePreviousApp() {
        previousApp?.activate()
    }

    /// Centers on the screen under the pointer, slightly above vertical center.
    /// `NSScreen.main` would be wrong on a multi-display setup.
    func layoutPanel() {
        panel.layoutIfNeeded()
        let height = panel.contentView?.fittingSize.height ?? 64
        let size = NSSize(width: Self.width, height: height)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + visible.height * 0.62
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - Work

    /// What to leave on screen while a turn runs. Nil clears the result area,
    /// which suits a panel whose previous output is about to be replaced.
    func displayWhileWorking() -> String? { nil }

    /// Runs an async unit of work with spinner + status, keeping the panel from
    /// auto-dismissing while it is in flight.
    func runBusy(status: String, _ work: @escaping () async throws -> String) {
        guard !isBusy else { return }
        isBusy = true
        setResult(displayWhileWorking())
        setStatus(status)
        spinner.startAnimation(nil)
        layoutPanel()

        Task { @MainActor in
            defer {
                isBusy = false
                spinner.stopAnimation(nil)
            }
            do {
                let text = try await work()
                result = text
                setResult(text)
                didFinish(text)
            } catch {
                result = nil
                setResult(nil)
                setStatus(error.localizedDescription, isError: true)
                Log.error("panel work failed: \(error.localizedDescription)")
            }
            layoutPanel()
        }
    }

    /// ⇧⌘M. Panels that support switching model override this.
    func pickModel() -> Bool { false }

    /// ⇧⌘T. Panels that support choosing a reasoning level override this.
    func pickThinking() -> Bool { false }

    /// Called after a successful run so subclasses can set their own footer hint.
    func didFinish(_ text: String) {}

    /// Footer hint to restore once a transient state (speaking, copied) ends.
    func idleHint() -> String? { nil }

    /// ⌘⏎. Text to carry into a full session, or nil if the panel has nothing
    /// worth carrying over.
    func sessionSeed() -> String? { nil }

    /// Opens a throwaway zdx session and closes the panel.
    @discardableResult
    func openSession() -> Bool {
        guard let binary = zdx.binary else { return false }
        let seed = sessionSeed()
        hide()

        do {
            _ = try SessionLauncher.launch(zdx: binary, seed: seed)
        } catch {
            Log.error("could not open session: \(error.localizedDescription)")
        }
        return true
    }

    // MARK: - Speech

    /// ⌘S. Generates audio for the current result and plays it; pressing again
    /// while playing stops it.
    func speakResult() -> Bool {
        guard let result, !result.isEmpty else { return false }

        if isSpeaking {
            speech.stop()
            isSpeaking = false
            setStatus(idleHint())
            return true
        }
        guard !isBusy else { return true }

        isSpeaking = true
        setStatus("Generating speech…")
        spinner.startAnimation(nil)

        Task { @MainActor in
            defer { spinner.stopAnimation(nil) }
            do {
                let audio = try await zdx.speak(result)
                try speech.play(audio)
                setStatus("🔊 Speaking · ⌘S stop")
            } catch {
                isSpeaking = false
                setStatus(error.localizedDescription, isError: true)
                Log.error("speech failed: \(error.localizedDescription)")
                layoutPanel()
            }
        }
        return true
    }

    /// Reopens the panel still holding a result, for recovery paths where an
    /// action failed after the panel was dismissed.
    func reopen(with text: String, status: String, isError: Bool = false) {
        show()
        result = text
        setResult(text)
        setStatus(status, isError: isError)
        layoutPanel()
    }

    func copyResult() -> Bool {        guard let result, !result.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        setStatus("Copied")
        return true
    }

    // MARK: - Rendering

    func setResult(_ text: String?) {
        guard let text, !text.isEmpty else {
            resultView.string = ""
            resultScroll.isHidden = true
            separator.isHidden = true
            resultHeight.constant = 0
            return
        }

        resultView.string = text
        resultScroll.isHidden = false
        separator.isHidden = false
        resultHeight.constant = measuredHeight(for: text)
        resultView.scroll(.zero)
    }

    /// Scrolls the result area to the newest content, for panels that append
    /// rather than replace.
    func scrollResultToEnd() {
        resultView.scrollToEndOfDocument(nil)
    }

    private func measuredHeight(for text: String) -> CGFloat {
        let width = Self.width - Self.padding * 2
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: resultView.font ?? .systemFont(ofSize: 14)]
        )
        return min(max(ceil(bounding.height) + 4, 20), Self.maxResultHeight)
    }

    func setStatus(_ text: String?, isError: Bool = false) {
        statusLabel.stringValue = text ?? ""
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Never yank the panel away mid-request or mid-playback; the user would
        // lose the result they are waiting for or listening to.
        guard !isBusy, !isSpeaking else { return }
        hide()
    }
}
