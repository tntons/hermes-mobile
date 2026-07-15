//
//  WebViewConfig.swift
//  Hermes
//
//  Configures the WKWebView subclass:
//   - hides the iOS keyboard accessory bar (prev/next/done)
//   - disables the WKWebView internal scrolling (the SwiftUI scroll owns layout)
//   - applies mobile-friendly WKWebView defaults
//

import Foundation
import WebKit

/// Subclass of `WKWebView` that hides the keyboard accessory bar (the system
/// "Previous / Next / Done" toolbar above the on-screen keyboard that pollutes
/// the chat experience). Returning `nil` from `inputAccessoryView` is the
/// documented and supported path.
public final class HermesWebView: WKWebView {
    public override var inputAccessoryView: UIView? { nil }
}

public enum WebViewConfig {
    public static func makeConfiguration() -> WKWebViewConfiguration {
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.preferredContentMode = .mobile
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = false
        return cfg
    }

    /// Returns a freshly-constructed `WKWebView` subclass with our config.
    public static func make(frame: CGRect) -> HermesWebView {
        let cfg = makeConfiguration()
        let web = HermesWebView(frame: frame, configuration: cfg)
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        return web
    }
}
