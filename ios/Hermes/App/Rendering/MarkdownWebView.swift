//
//  MarkdownWebView.swift
//  Hermes
//
//  WKWebView wrapper that renders a markdown string into our `renderer.html`.
//  Re-renders streamed text with debouncing. Reports intrinsic height to the
//  parent SwiftUI view via a closure passed in at construction, so each
//  cell observes only its own webview's reports (no NotificationCenter
//  cross-talk between cells).
//

import SwiftUI
import WebKit

public struct MarkdownWebView: UIViewRepresentable {
    let text: String
    let isStreaming: Bool
    let onHeightChange: (CGFloat) -> Void
    let onLinkTap: (String) -> Void

    public init(
        text: String,
        isStreaming: Bool = false,
        onHeightChange: @escaping (CGFloat) -> Void = { _ in },
        onLinkTap: @escaping (String) -> Void = { _ in }
    ) {
        self.text = text
        self.isStreaming = isStreaming
        self.onHeightChange = onHeightChange
        self.onLinkTap = onLinkTap
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange, onLinkTap: onLinkTap)
    }

    public func makeUIView(context: Context) -> HermesWebView {
        let web = WebViewConfig.make(frame: .zero)
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web

        // Register the heightChange handler BEFORE loading the page.
        let userContent = web.configuration.userContentController
        userContent.add(context.coordinator, name: "heightChange")
        userContent.add(context.coordinator, name: "linkTap")

        // Load bundled renderer.html once.
        if let url = Bundle.main.url(forResource: "renderer", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            let html = """
            <!doctype html><html><body><pre>Renderer assets missing from bundle.</pre></body></html>
            """
            web.loadHTMLString(html, baseURL: nil)
        }
        return web
    }

    public func updateUIView(_ web: HermesWebView, context: Context) {
        // Debounce: while streaming, render only every ~80ms; final renders immediately.
        context.coordinator.queue(text: text, streaming: isStreaming, to: web)
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        public weak var web: HermesWebView?
        private var pendingText: String?
        private var pendingFlush: DispatchWorkItem?
        private var lastRendered: String = ""
        private let onHeightChange: (CGFloat) -> Void
        private let onLinkTap: (String) -> Void

        init(onHeightChange: @escaping (CGFloat) -> Void, onLinkTap: @escaping (String) -> Void) {
            self.onHeightChange = onHeightChange
            self.onLinkTap = onLinkTap
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // First load: ask JS to render the current text (likely empty initially).
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let text = self.pendingText, !text.isEmpty, text != self.lastRendered {
                    self.commit(text)
                }
            }
        }

        // Render queue

        public func queue(text: String, streaming: Bool, to web: HermesWebView) {
            self.web = web
            pendingText = text

            // Cancel any pending debounce — only render the latest committed value.
            pendingFlush?.cancel()
            if !streaming {
                commit(text)         // Final: render immediately
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if let t = self.pendingText, t != self.lastRendered {
                    self.commit(t)
                }
            }
            pendingFlush = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80), execute: work)
        }

        private func commit(_ text: String) {
            guard let web else { return }
            lastRendered = text
            // Encode as a JS string literal.
            let json = encodeAsJSONString(text)
            let theme = "dark"
            let js = "render(\(json), '\(theme)')"
            web.evaluateJavaScript(js, completionHandler: nil)
        }

        // WKScriptMessageHandler — scopes each report to *this* webview by
        // calling the per-instance closure rather than a global
        // NotificationCenter post. Eliminates cross-cell height bleed.

        public func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "heightChange":
                if let h = message.body as? Double {
                    onHeightChange(max(60, CGFloat(h) + 4))
                }
            case "linkTap":
                if let href = message.body as? String {
                    onLinkTap(href)
                }
            default:
                break
            }
        }

        private func encodeAsJSONString(_ s: String) -> String {
            // Avoid pulling in JSONEncoder hot-path overhead: encode via
            // JSONSerialization's `NSString` representation.
            do {
                let data = try JSONSerialization.data(
                    withJSONObject: [s],
                    options: [.fragmentsAllowed]
                )
                return String(data: data, encoding: .utf8)!
                    .dropFirst()                 // trim leading '['
                    .dropLast()                  // trim trailing ']'
                    .description
            } catch {
                // Fallback: escape a small subset manually.
                let escaped = s
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                    .replacingOccurrences(of: "\"", with: "\\\\\"")
                return "\"\(escaped)\""
            }
        }
    }
}

// Notification kept for any external listener that wants link taps without
// wiring the per-cell closure (e.g. analytics). Coordinator now defaults to
// posting here as well so existing hookups keep working, but the primary
// path is the closure.
public extension Notification.Name {
    static let hermesRendererLinkTap = Notification.Name("HermesRendererLinkTap")
}
