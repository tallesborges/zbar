import AppKit
import WebKit

/// Renders Markdown into a persistent `WKWebView`.
///
/// The document shell is loaded exactly once and every update patches `#content`
/// through JavaScript, so streaming answers don't reload the page. Content
/// height is pushed back from a `ResizeObserver` in the page rather than
/// measured on the AppKit side, since only the web layout knows how tall
/// wrapped tables, lists, and code blocks actually are.
@MainActor
final class MarkdownWebView: NSView {
    /// Reports the rendered content height, in points, whenever it changes.
    var onHeightChange: ((CGFloat) -> Void)?

    private let webView: WKWebView
    private var shellReady = false
    private var pending: (html: String, stick: Bool)?
    private var debounce: DispatchWorkItem?

    /// Coalescing window for streaming deltas. Long enough to avoid relayouts
    /// on every token, short enough to still look live.
    private static let patchInterval: TimeInterval = 0.05

    /// Vendored highlight.js. Absent only if the resource fails to load, in
    /// which case code blocks simply render unhighlighted.
    private static let highlightScript: String? = {
        guard let url = Bundle.module.url(forResource: "highlight.min", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            Log.error("highlight.js resource missing; code blocks will not be highlighted")
            return nil
        }
        return source
    }()

    override init(frame frameRect: NSRect) {
        let controller = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.suppressesIncrementalRendering = false

        webView = WKWebView(frame: frameRect, configuration: config)
        super.init(frame: frameRect)

        controller.add(ScriptProxy(self), name: "zbar")
        if let highlighter = Self.highlightScript {
            // Injected rather than embedded in the shell HTML: the minified
            // source contains markup-language definitions, and a stray
            // `</script>` in a literal would close the tag early.
            controller.addUserScript(
                WKUserScript(source: highlighter, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }

        // The page paints transparently over the panel's own backdrop, so
        // light/dark tracks the system appearance with no JS theme bridge.
        webView.underPageBackgroundColor = .windowBackgroundColor
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        webView.loadHTMLString(MarkdownRenderer.shell, baseURL: nil)
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Content

    /// Renders `markdown`, keeping the view pinned to the bottom when `stick`
    /// is set — which is what streaming answers want.
    func render(_ markdown: String, stick: Bool) {
        patch(html: MarkdownRenderer.body(for: markdown), stick: stick)
    }

    func clear() {
        patch(html: "", stick: false)
    }

    func scrollToEnd() {
        guard shellReady else { return }
        webView.evaluateJavaScript("window.zbarScrollToEnd()")
    }

    private func patch(html: String, stick: Bool) {
        pending = (html, stick)
        guard debounce == nil else { return }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.debounce = nil
                self.flush()
            }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.patchInterval, execute: work)
    }

    private func flush() {
        guard shellReady, let (html, stick) = pending else { return }
        pending = nil

        guard let literal = Self.jsString(html) else { return }
        webView.evaluateJavaScript("window.zbarSetContent(\(literal), \(stick))")
    }

    /// Encodes a Swift string as a JavaScript string literal. Going through
    /// JSON is what makes arbitrary model output safe to inject.
    private static func jsString(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8)
        else { return nil }
        return String(array.dropFirst().dropLast())
    }

    fileprivate func contentHeightChanged(_ height: CGFloat) {
        onHeightChange?(height)
    }
}

// MARK: - Navigation

extension MarkdownWebView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        shellReady = true
        flush()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // The shell is the only document this view ever loads; anything the user
        // clicks belongs in their browser, not in a 640pt panel.
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url
        else {
            decisionHandler(.allow)
            return
        }
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }
}

// MARK: - Script bridge

/// `WKUserContentController` retains its handlers, which would otherwise keep
/// the view alive through its own web view.
private final class ScriptProxy: NSObject, WKScriptMessageHandler {
    private weak var target: MarkdownWebView?

    init(_ target: MarkdownWebView) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let height = message.body as? NSNumber else { return }
        MainActor.assumeIsolated {
            target?.contentHeightChanged(CGFloat(height.doubleValue))
        }
    }
}
