//
//  MarkdownWebView.swift
//  Hermes
//
//  WKWebView wrapper that renders a markdown string into our `renderer.html`.
//  Re-renders streamed text with debouncing; reports intrinsic height so the
//  surrounding SwiftUI cell can size itself.
//

import SwiftUI
import WebKit

public struct MarkdownWebView: UIViewRepresentable {
    let text: String
    let isStreaming: Bool

    public init(text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

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

        // WKScriptMessageHandler

        public func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightChange", let h = message.body as? Double {
                // Re-emit via Notification so the SwiftUI cell picks it up.
                NotificationCenter.default.post(
                    name: .hermesRendererHeight,
                    object: web,
                    userInfo: ["height": h]
                )
            } else if message.name == "linkTap", let href = message.body as? String {
                NotificationCenter.default.post(
                    name: .hermesRendererLinkTap,
                    object: web,
                    userInfo: ["href": href]
                )
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
                    .replacingOccurrences(of: "\"", with: "\\\"")
                return "\"\(escaped)\""
            }
        }
    }
}

public extension Notification.Name {
    static let hermesRendererHeight = Notification.Name("HermesRendererHeight")
    static let hermesRendererLinkTap = Notification.Name("HermesRendererLinkTap")
}
