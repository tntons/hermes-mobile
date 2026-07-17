//
//  MarkdownText.swift
//  Hermes
//
//  Native markdown renderer. Splits the input into typed segments
//  (prose / code / quote) via MarkdownParser and renders each in
//  pure SwiftUI. Replaces the previous WKWebView path.
//

import SwiftUI

struct MarkdownText: View {
    let text: String

    var body: some View {
        let segments = MarkdownParser.parse(text)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                view(for: segment)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for segment: MarkdownSegment) -> some View {
        switch segment {
        case .prose(let text):
            ProseText(text: text)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 2)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

/// Renders prose as `AttributedString(markdown:)` so bold / italic /
/// inline code / links get native styling. Fallback to plain `Text` if
/// AttributedString parsing fails.
private struct ProseText: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    UIApplication.shared.open(url)
                    return .handled
                })
        } else {
            Text(text)
                .textSelection(.enabled)
        }
    }
}
