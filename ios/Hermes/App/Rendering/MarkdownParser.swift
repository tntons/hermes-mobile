//
//  MarkdownParser.swift
//  Hermes
//
//  Splits a markdown string into typed segments (prose / code / quote)
//  for the native MarkdownText renderer. Replaces the WKWebView path.
//

import Foundation

enum MarkdownSegment: Hashable {
    case prose(String)
    case code(language: String?, source: String)
    case quote(String)
}

enum MarkdownParser {
    /// Parse `text` into segments. Splits on triple-backtick code fences,
    /// treats blank-line-separated blocks as paragraphs, and lines starting
    /// with `> ` as quotes. The cache key is the text itself, so repeated
    /// re-renders during streaming are cheap.
    static func parse(_ text: String) -> [MarkdownSegment] {
        var segments: [MarkdownSegment] = []
        var remaining = Substring(text)

        while let fenceStart = remaining.range(of: "```") {
            // Prose before the fence.
            let proseChunk = remaining[..<fenceStart.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !proseChunk.isEmpty {
                segments.append(.prose(String(proseChunk)))
            }

            // Find the matching closing fence.
            let afterOpen = remaining[fenceStart.upperBound...]
            guard let fenceEnd = afterOpen.range(of: "```") else {
                // Unterminated fence — render the rest as code so we don't
                // drop content.
                let rawStartIndex = text.index(text.startIndex,
                                              offsetBy: text.distance(from: text.startIndex,
                                                                       to: fenceStart.lowerBound))
                let raw = String(text[rawStartIndex...])
                let (lang, body) = parseFenceOpen(raw)
                segments.append(.code(language: lang, source: body))
                return segments
            }

            // Inline fence on a single line is unusual but handle it.
            let openLine = afterOpen[..<afterOpen.startIndex]
                .prefix(while: { $0 != "\n" })
            let lang = String(openLine).trimmingCharacters(in: .whitespaces)
            let body = String(afterOpen[afterOpen.startIndex..<fenceEnd.lowerBound])
            segments.append(.code(
                language: lang.isEmpty ? nil : lang,
                source: body
            ))

            remaining = afterOpen[fenceEnd.upperBound...]
        }

        // Trailing prose.
        let tail = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            segments.append(.prose(String(tail)))
        }

        // Split prose into quote vs regular by line.
        return segments.flatMap { seg -> [MarkdownSegment] in
            guard case .prose(let text) = seg else { return [seg] }
            return splitProseByQuote(text)
        }
    }

    /// Parse the first line of a code block opener for an optional language tag.
    /// `text` starts with ```.
    private static func parseFenceOpen(_ text: String) -> (String?, String) {
        let afterFence = text.dropFirst(3)
        if let nl = afterFence.firstIndex(of: "\n") {
            let lang = afterFence[..<nl].trimmingCharacters(in: .whitespaces)
            let langOrNil: String? = lang.isEmpty ? nil : String(lang)
            let body = String(afterFence[afterFence.index(after: nl)...])
            return (langOrNil, body)
        }
        return (nil, String(afterFence))
    }

    private static func splitProseByQuote(_ text: String) -> [MarkdownSegment] {
        var segments: [MarkdownSegment] = []
        var buffer = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("> ") {
                if !buffer.isEmpty {
                    segments.append(.prose(buffer.trimmingCharacters(in: .whitespacesAndNewlines)))
                    buffer = ""
                }
                segments.append(.quote(String(line.dropFirst(2))))
            } else {
                buffer += line + "\n"
            }
        }
        if !buffer.isEmpty {
            segments.append(.prose(buffer.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return segments.isEmpty ? [.prose(text)] : segments
    }
}
