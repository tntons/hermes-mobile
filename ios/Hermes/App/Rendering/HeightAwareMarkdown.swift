//
//  HeightAwareMarkdown.swift
//  Hermes
//
//  Thin wrapper around MarkdownWebView that owns the cell's `@State` height
//  and threads it back to the WebView via a per-instance closure. Earlier
//  versions used NotificationCenter with `object: nil`, which meant every
//  cell listened to every other cell's height reports — last writer wins,
//  causing the visible "cells jumping" bug when several MarkdownWebViews
//  were on screen.
//

import SwiftUI

public struct HeightAwareMarkdown: View {
    let text: String
    let isStreaming: Bool
    @State private var height: CGFloat = 60

    public init(text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
    }

    public var body: some View {
        MarkdownWebView(
            text: text,
            isStreaming: isStreaming,
            onHeightChange: { newHeight in
                // Per-instance closure — only THIS view updates its height.
                if abs(newHeight - height) > 0.5 {
                    height = newHeight
                }
            }
        )
        .frame(height: height)
    }
}
