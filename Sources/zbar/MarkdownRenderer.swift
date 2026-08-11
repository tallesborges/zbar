import Foundation
import Markdown

/// Markdown -> HTML for the panel's result area.
///
/// Only the body fragment is generated per render; the surrounding document is
/// loaded once by `MarkdownWebView` and reused for the life of the app, so
/// streaming updates are DOM patches rather than page loads.
enum MarkdownRenderer {
    static func body(for markdown: String) -> String {
        HTMLFormatter.format(markdown)
    }

    /// The persistent document. `#content` is the only thing ever replaced.
    static let shell = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>\(css)</style>
    </head>
    <body><div id="content"></div>
    <script>
    (function () {
      var content = document.getElementById('content');

      function report() {
        window.webkit.messageHandlers.zbar.postMessage(
          Math.ceil(content.getBoundingClientRect().height)
        );
      }

      // Fires once on observe, then on every reflow caused by a patch.
      new ResizeObserver(report).observe(content);

      window.zbarSetContent = function (html, stick) {
        content.innerHTML = html;
        if (window.hljs) {
          var blocks = content.querySelectorAll('pre code');
          for (var i = 0; i < blocks.length; i++) {
            try { window.hljs.highlightElement(blocks[i]); } catch (e) {}
          }
        }
        if (stick) window.scrollTo(0, document.body.scrollHeight);
      };

      window.zbarScrollToEnd = function () {
        window.scrollTo(0, document.body.scrollHeight);
      };
    })();
    </script>
    </body>
    </html>
    """

    private static let css = """
    :root { color-scheme: light dark; }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; background: transparent; }
    body {
      font: 14px/1.55 -apple-system, "SF Pro Text", system-ui, sans-serif;
      color: #1d1d1f;
      overscroll-behavior: none;
      -webkit-font-smoothing: antialiased;
      word-break: break-word;
    }
    /* flow-root so child margins are contained and the measured height is real. */
    #content { display: flow-root; }
    #content > *:first-child { margin-top: 0; }
    #content > *:last-child { margin-bottom: 0; }
    p, ul, ol, blockquote, table, pre { margin: 0 0 .8em; }
    h1, h2, h3, h4 { line-height: 1.3; font-weight: 650; margin: 1.2em 0 .4em; }
    h1 { font-size: 1.4em; }
    h2 { font-size: 1.25em; }
    h3 { font-size: 1.1em; }
    h4 { font-size: 1em; }
    ul, ol { padding-left: 1.4em; }
    li { margin: .15em 0; }
    /* Loose lists wrap items in <p>; keep them as tight as list text. */
    li > p { margin: 0; }
    li > p + p { margin-top: .4em; }
    a { color: #0a66ff; text-decoration: none; }
    a:hover { text-decoration: underline; }
    code {
      font: .88em ui-monospace, "SF Mono", Menlo, monospace;
      background: rgba(0,0,0,.06); padding: .12em .32em; border-radius: 4px;
    }
    pre {
      background: rgba(0,0,0,.05); padding: 10px 12px; border-radius: 8px;
      overflow-x: auto; line-height: 1.45;
    }
    pre code { background: none; padding: 0; }
    blockquote {
      border-left: 3px solid rgba(0,0,0,.15); margin-left: 0;
      padding-left: .8em; color: #555;
    }
    table { border-collapse: collapse; display: block; overflow-x: auto; width: max-content; max-width: 100%; }
    th, td { border: 1px solid rgba(0,0,0,.12); padding: 5px 10px; }
    /* Column alignment arrives as an `align` attribute, which a plain
       `text-align` rule would outrank; only default the unaligned cells. */
    th:not([align]), td:not([align]) { text-align: left; }
    th { background: rgba(0,0,0,.04); font-weight: 600; }
    hr { border: none; border-top: 1px solid rgba(0,0,0,.1); margin: 1.4em 0; }
    img { max-width: 100%; border-radius: 6px; }

    /* highlight.js tokens, GitHub-ish palette. */
    .hljs-comment, .hljs-quote, .hljs-meta { color: #6a737d; }
    .hljs-keyword, .hljs-selector-tag, .hljs-tag, .hljs-doctag { color: #d73a49; }
    .hljs-string, .hljs-regexp, .hljs-symbol, .hljs-bullet { color: #032f62; }
    .hljs-number, .hljs-literal, .hljs-built_in, .hljs-type, .hljs-selector-class { color: #005cc5; }
    .hljs-title, .hljs-name, .hljs-section, .hljs-function .hljs-title { color: #6f42c1; }
    .hljs-attr, .hljs-attribute, .hljs-variable, .hljs-property, .hljs-template-variable { color: #e36209; }
    .hljs-addition { color: #22863a; }
    .hljs-deletion { color: #b31d28; }
    .hljs-emphasis { font-style: italic; }
    .hljs-strong { font-weight: 600; }

    @media (prefers-color-scheme: dark) {
      body { color: #e8e8ea; }
      a { color: #4c9dff; }
      code, pre { background: rgba(255,255,255,.08); }
      blockquote { border-left-color: rgba(255,255,255,.2); color: #aaa; }
      th, td { border-color: rgba(255,255,255,.15); }
      th { background: rgba(255,255,255,.05); }
      hr { border-top-color: rgba(255,255,255,.12); }

      .hljs-comment, .hljs-quote, .hljs-meta { color: #8b949e; }
      .hljs-keyword, .hljs-selector-tag, .hljs-tag, .hljs-doctag { color: #ff7b72; }
      .hljs-string, .hljs-regexp, .hljs-symbol, .hljs-bullet { color: #a5d6ff; }
      .hljs-number, .hljs-literal, .hljs-built_in, .hljs-type, .hljs-selector-class { color: #79c0ff; }
      .hljs-title, .hljs-name, .hljs-section, .hljs-function .hljs-title { color: #d2a8ff; }
      .hljs-attr, .hljs-attribute, .hljs-variable, .hljs-property, .hljs-template-variable { color: #ffa657; }
      .hljs-addition { color: #7ee787; }
      .hljs-deletion { color: #ffa198; }
    }
    """
}
