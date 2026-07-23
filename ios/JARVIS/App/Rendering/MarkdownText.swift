//
//  MarkdownText.swift
//  JARVIS
//
//  Native block-aware Markdown renderer for conversation messages.
//

import SwiftUI

struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownParser.parse(text).enumerated()), id: \.offset) { _, segment in
                view(for: segment)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for segment: MarkdownSegment) -> some View {
        switch segment {
        case .prose(let text):
            InlineMarkdownText(text: text)
        case .heading(let level, let text):
            InlineMarkdownText(text: text)
                .font(headingFont(for: level))
                .foregroundStyle(JarvisTheme.textPrimary)
                .padding(.top, level <= 2 ? 5 : 2)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(JarvisTheme.accent.opacity(0.7))
                    .frame(width: 3)
                InlineMarkdownText(text: text)
                    .foregroundStyle(JarvisTheme.textSecondary)
            }
            .padding(.vertical, 2)
        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(JarvisTheme.accent)
                            .frame(minWidth: ordered ? 22 : 12, alignment: .trailing)
                        InlineMarkdownText(text: item)
                    }
                }
            }
        case .divider:
            Rectangle()
                .fill(JarvisTheme.border)
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .system(size: 24, weight: .bold)
        case 2: return .system(size: 20, weight: .bold)
        case 3: return .system(size: 18, weight: .semibold)
        default: return .system(size: 16, weight: .semibold)
        }
    }
}

private struct InlineMarkdownText: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.system(size: 16))
                .foregroundStyle(JarvisTheme.textPrimary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    UIApplication.shared.open(url)
                    return .handled
                })
        } else {
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(JarvisTheme.textPrimary)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }
}
