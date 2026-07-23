//
//  MarkdownParser.swift
//  JARVIS
//
//  Lightweight block parser for the native chat renderer. Inline formatting
//  is still handled by Foundation's AttributedString parser.
//

import Foundation

enum MarkdownSegment: Hashable {
    case prose(String)
    case heading(level: Int, text: String)
    case code(language: String?, source: String)
    case quote(String)
    case list(items: [String], ordered: Bool)
    case divider
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownSegment] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var segments: [MarkdownSegment] = []
        var proseLines: [String] = []
        var index = 0

        func flushProse() {
            let prose = proseLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !prose.isEmpty {
                segments.append(.prose(prose))
            }
            proseLines.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushProse()
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                flushProse()
                let languageText = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let language = languageText.isEmpty ? nil : languageText
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }
                segments.append(.code(language: language, source: codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = headingLine(trimmed) {
                flushProse()
                segments.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isDivider(trimmed) {
                flushProse()
                segments.append(.divider)
                index += 1
                continue
            }

            if isQuoteLine(trimmed) {
                flushProse()
                var quoteLines: [String] = []
                while index < lines.count {
                    let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isQuoteLine(quoteLine) else { break }
                    quoteLines.append(quoteText(quoteLine))
                    index += 1
                }
                segments.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            if let firstItem = listItem(trimmed) {
                flushProse()
                let ordered = firstItem.ordered
                var items = [firstItem.text]
                index += 1
                while index < lines.count,
                      let item = listItem(lines[index].trimmingCharacters(in: .whitespaces)),
                      item.ordered == ordered {
                    items.append(item.text)
                    index += 1
                }
                segments.append(.list(items: items, ordered: ordered))
                continue
            }

            proseLines.append(line)
            index += 1
        }

        flushProse()
        return segments
    }

    private static func headingLine(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), hashes < line.count else { return nil }
        let separator = line.index(line.startIndex, offsetBy: hashes)
        guard line[separator].isWhitespace else { return nil }
        let text = line[line.index(after: separator)...]
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (hashes, text)
    }

    private static func listItem(_ line: String) -> (ordered: Bool, text: String)? {
        guard let first = line.first else { return nil }
        if first == "-" || first == "*" || first == "+" {
            let content = line.dropFirst().trimmingCharacters(in: .whitespaces)
            return content.isEmpty ? nil : (false, String(content))
        }

        var digitCount = 0
        for character in line {
            guard character.isNumber else { break }
            digitCount += 1
        }
        guard digitCount > 0, digitCount + 1 < line.count else { return nil }
        let marker = line.index(line.startIndex, offsetBy: digitCount)
        guard line[marker] == "." || line[marker] == ")" else { return nil }
        let content = line[line.index(after: marker)...]
            .trimmingCharacters(in: .whitespaces)
        return content.isEmpty ? nil : (true, String(content))
    }

    private static func isQuoteLine(_ line: String) -> Bool {
        line == ">" || line.hasPrefix("> ")
    }

    private static func quoteText(_ line: String) -> String {
        String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" }
    }
}
