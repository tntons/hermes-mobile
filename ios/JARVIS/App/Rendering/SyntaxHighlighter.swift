//
//  SyntaxHighlighter.swift
//  JARVIS
//
//  Tiny regex-based highlighter. Covers 8 common languages with 5 token
//  classes (keywords, strings, comments, numbers, default). Falls back
//  to plain monospace for unknown languages.
//

import Foundation
import SwiftUI

enum SyntaxToken: Hashable {
    case keyword
    case string
    case comment
    case number
    case `default`

    var color: Color {
        switch self {
        case .keyword: return Color(red: 0.71, green: 0.40, blue: 0.82)   // purple
        case .string:  return Color(red: 0.40, green: 0.71, blue: 0.40)   // green
        case .comment: return Color(red: 0.50, green: 0.55, blue: 0.60)   // gray
        case .number:  return Color(red: 0.85, green: 0.55, blue: 0.20)   // orange
        case .default: return .primary
        }
    }
}

enum SyntaxHighlighter {
    /// Returns an `AttributedString` with token-level foreground colors.
    static func highlight(_ source: String, language: String?) -> AttributedString {
        guard let lang = language?.lowercased(),
              let rules = rules(for: lang)
        else {
            return AttributedString(source)
        }

        var attr = AttributedString(source)
        let nsString = source as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        // Apply in a specific order so strings/comments win over keywords
        // when overlapping (e.g. a keyword inside a comment).
        let order: [SyntaxToken] = [.comment, .string, .keyword, .number]
        for token in order {
            for pattern in rules[token] ?? [] {
                applyRegex(pattern,
                            in: nsString,
                            fullRange: fullRange,
                            attr: &attr,
                            token: token)
            }
        }
        return attr
    }

    private static func applyRegex(
        _ pattern: String,
        in nsString: NSString,
        fullRange: NSRange,
        attr: inout AttributedString,
        token: SyntaxToken
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
        let matches = regex.matches(in: nsString as String, options: [], range: fullRange)
        for match in matches {
            guard let swiftRange = Range(match.range, in: source) else { continue }
            if let attrRange = Range(swiftRange, in: attr) {
                attr[attrRange].foregroundColor = token.color
            }
        }
    }

    /// Per-language regex patterns. Keys are token classes.
    private static func rules(for lang: String) -> [SyntaxToken: [String]]? {
        switch lang {
        case "swift":
            return [
                .keyword: [
                    #"\b(func|let|var|if|else|guard|return|class|struct|enum|protocol|extension|import|throw|try|catch|do|switch|case|default|for|while|in|where|self|init|deinit|nil|true|false|public|private|internal|fileprivate|open|static|final|override|async|await|actor)\b"#
                ],
                .string: [
                    #""(?:[^"\\]|\\.)*""#,
                    #"'(?:[^'\\]|\\.)*'"#
                ],
                .comment: [
                    #"//[^\n]*"#,
                    #"/\*[\s\S]*?\*/"#
                ],
                .number: [ #"\b\d+(?:\.\d+)?\b"# ]
            ]
        case "python", "py":
            return [
                .keyword: [
                    #"\b(def|class|import|from|as|if|elif|else|while|for|in|try|except|finally|with|return|yield|lambda|pass|break|continue|True|False|None|and|or|not|is|in)\b"#
                ],
                .string: [
                    #""(?:[^"\\]|\\.)*""#,
                    #"'(?:[^'\\]|\\.)*'"#,
                    #""""[\s\S]*?""""#
                ],
                .comment: [ #"#[^\n]*"# ],
                .number: [ #"\b\d+(?:\.\d+)?\b"# ]
            ]
        case "javascript", "js", "typescript", "ts":
            return [
                .keyword: [
                    #"\b(function|const|let|var|if|else|for|while|do|switch|case|default|return|break|continue|new|class|extends|super|this|import|export|from|as|async|await|try|catch|finally|throw|typeof|instanceof|in|of|null|undefined|true|false)\b"#
                ],
                .string: [
                    #""(?:[^"\\]|\\.)*""#,
                    #"'(?:[^'\\]|\\.)*'"#,
                    #"`(?:[^`\\]|\\.)*`"#
                ],
                .comment: [
                    #"//[^\n]*"#,
                    #"/\*[\s\S]*?\*/"#
                ],
                .number: [ #"\b\d+(?:\.\d+)?\b"# ]
            ]
        case "bash", "sh", "zsh":
            return [
                .keyword: [
                    #"\b(if|then|else|elif|fi|for|in|do|done|while|case|esac|function|return|export|local|readonly|declare|set|unset)\b"#
                ],
                .string: [
                    #""(?:[^"\\]|\\.)*""#,
                    #"'(?:[^'\\]|\\.)*'"#
                ],
                .comment: [ #"#[^\n]*"# ],
                .number: [ #"\b\d+\b"# ]
            ]
        case "json":
            return [
                .keyword: [
                    #"(?i)\b(true|false|null)\b"#
                ],
                .string: [ #""(?:[^"\\]|\\.)*""# ],
                .number: [ #"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"# ]
            ]
        case "go":
            return [
                .keyword: [
                    #"\b(func|package|import|var|const|type|struct|interface|map|chan|go|select|case|default|for|range|if|else|switch|break|continue|return|fallthrough|defer|go)\b"#
                ],
                .string: [
                    #"`[^`]*`"#,
                    #""(?:[^"\\]|\\.)*""#,
                    #"'(?:[^'\\]|\\.)*'"#
                ],
                .comment: [
                    #"//[^\n]*"#,
                    #"/\*[\s\S]*?\*/"#
                ],
                .number: [ #"\b\d+(?:\.\d+)?\b"# ]
            ]
        case "rust", "rs":
            return [
                .keyword: [
                    #"\b(fn|let|mut|const|static|pub|use|mod|struct|enum|trait|impl|for|in|while|loop|if|else|match|return|break|continue|self|Self|as|where|move|ref|true|false)\b"#
                ],
                .string: [ #""(?:[^"\\]|\\.)*""# ],
                .comment: [
                    #"//[^\n]*"#,
                    #"/\*[\s\S]*?\*/"#
                ],
                .number: [ #"\b\d+(?:\.\d+)?\b"# ]
            ]
        case "sql":
            return [
                .keyword: [
                    #"(?i)\b(select|from|where|insert|update|delete|join|inner|outer|left|right|on|group|by|order|having|limit|offset|union|all|distinct|as|and|or|not|null|is|in|between|like|create|table|index|primary|key|foreign|references|drop|alter)\b"#
                ],
                .string: [
                    #"'(?:[^'\\]|\\.)*'"#,
                    #""(?:[^"\\]|\\.)*""#
                ],
                .comment: [
                    #"--[^\n]*"#,
                    #"/\*[\s\S]*?\*/"#
                ],
                .number: [ #"\b\d+(?:\.\d+)?\b"# ]
            ]
        default:
            return nil
        }
    }

    /// Source string captured by the NSRegularExpression calls above.
    private static let source = ""
}
