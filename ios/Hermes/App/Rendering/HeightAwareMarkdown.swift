//
//  HeightAwareMarkdown.swift
//  Hermes
//
//  A wrapper around MarkdownWebView that observes the height posted by the
//  page (`webkit.messageHandlers.heightChange`), and renders with that height.
//  This is what lets the WebView sit inside the SwiftUI scroll view without
//  needing a UIKit measure pass on each render.
//

import SwiftUI

public struct HeightAwareMarkdown: View {
    let text: String
    let isStreaming: Bool
    @State private var lastHeight: CGFloat = 60
    @State private var observer: NSObjectProtocol?

    public var body: some View {
        MarkdownWebView(text: text, isStreaming: isStreaming)
            .frame(minHeight: lastHeight)
            .onAppear {
                guard observer == nil else { return }
                observer = NotificationCenter.default.addObserver(
                    forName: .hermesRendererHeight,
                    object: nil,
                    queue: .main
                ) { note in
                    if let h = note.userInfo?["height"] as? Double {
                        lastHeight = max(60, CGFloat(h) + 4)
                    }
                }
            }
            .onDisappear {
                if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
            }
    }
}
