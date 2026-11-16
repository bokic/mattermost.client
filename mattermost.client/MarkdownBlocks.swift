//
//  MarkdownBlocks.swift
//  mattermost.client
//
//  Small block-level Markdown parser used by timeline message rendering.
//  Inline formatting still goes through AttributedString's inline Markdown.
//

import AppKit

enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bullet(text: String, depth: Int)
    case ordered(number: Int, text: String, depth: Int)
    case blockquote(String)
    case code(language: String?, text: String)
    case table(headers: [String], rows: [[String]])
    case horizontalRule
}

enum MarkdownBlockParser {
    static func parse(_ message: String) -> [MarkdownBlock] {
        let lines = message.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
                    .split(separator: " ")
                    .first
                    .map(String.init)
                var codeLines: [String] = []
                index += 1
                while index < lines.count,
                    !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```")
                {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(
                    .code(language: language?.isEmpty == true ? nil : language, text: codeLines.joined(separator: "\n"))
                )
                continue
            }

            if let table = parseTable(lines, start: index) {
                blocks.append(table.block)
                index += table.consumed
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    var content = candidate
                    while content.hasPrefix(">") {
                        content.removeFirst()
                        if content.hasPrefix(" ") { content.removeFirst() }
                    }
                    quoteLines.append(content)
                    index += 1
                }
                blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
                continue
            }

            if let bullet = parseBullet(line) {
                blocks.append(.bullet(text: bullet.text, depth: bullet.depth))
                index += 1
                continue
            }

            if let ordered = parseOrdered(line) {
                blocks.append(.ordered(number: ordered.number, text: ordered.text, depth: ordered.depth))
                index += 1
                continue
            }

            var paragraphLines = [line]
            index += 1
            while index < lines.count {
                let candidate = lines[index]
                if candidate.trimmingCharacters(in: .whitespaces).isEmpty
                    || isBlockStart(candidate)
                {
                    break
                }
                paragraphLines.append(candidate)
                index += 1
            }
            blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
        }

        return blocks
    }

    private static func isBlockStart(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```")
            || parseHeading(trimmed) != nil
            || isHorizontalRule(trimmed)
            || trimmed.hasPrefix(">")
            || parseBullet(line) != nil
            || parseOrdered(line) != nil
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var rest = line
        while rest.hasPrefix("#"), level < 6 {
            level += 1
            rest.removeFirst()
        }
        guard level > 0, rest.hasPrefix(" ") else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" }
            || compact.allSatisfy { $0 == "*" }
            || compact.allSatisfy { $0 == "_" }
    }

    private static func parseBullet(_ line: String) -> (depth: Int, text: String)? {
        let (indent, rest) = splitIndent(line)
        guard rest.count >= 2 else { return nil }
        let marker = rest.first
        guard marker == "-" || marker == "*" || marker == "+" else { return nil }
        let after = rest.dropFirst()
        guard after.first == " " else { return nil }
        return (indent / 2, String(after.dropFirst()))
    }

    private static func parseOrdered(_ line: String) -> (depth: Int, number: Int, text: String)? {
        let (indent, rest) = splitIndent(line)
        let characters = Array(rest)
        var cursor = 0
        while cursor < characters.count, characters[cursor].isNumber { cursor += 1 }
        guard cursor > 0, cursor < characters.count,
            characters[cursor] == "." || characters[cursor] == ")"
        else { return nil }
        let number = Int(String(characters[0..<cursor])) ?? 1
        cursor += 1
        if cursor >= characters.count {
            return (indent / 2, number, "")
        }
        guard characters[cursor] == " " else { return nil }
        return (indent / 2, number, String(characters[(cursor + 1)...]))
    }

    private static func splitIndent(_ line: String) -> (Int, String) {
        var indent = 0
        var rest = line
        while let first = rest.first, first == " " || first == "\t" {
            indent += first == "\t" ? 2 : 1
            rest.removeFirst()
        }
        return (indent, rest)
    }

    private static func parseTable(
        _ lines: [String],
        start: Int
    ) -> (block: MarkdownBlock, consumed: Int)? {
        guard start + 1 < lines.count else { return nil }
        let headerLine = lines[start]
        let separatorLine = lines[start + 1]
        guard headerLine.contains("|"), separatorLine.contains("|") else { return nil }

        let headers = splitTableRow(headerLine)
        let separators = splitTableRow(separatorLine)
        guard !headers.isEmpty,
            headers.count == separators.count,
            separators.allSatisfy(isTableSeparator)
        else { return nil }

        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count {
            let line = lines[index]
            guard line.contains("|"), !line.trimmingCharacters(in: .whitespaces).isEmpty else { break }
            var cells = splitTableRow(line)
            while cells.count < headers.count { cells.append("") }
            rows.append(Array(cells.prefix(headers.count)))
            index += 1
        }
        return (.table(headers: headers, rows: rows), index - start)
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ cell: String) -> Bool {
        let compact = cell.replacingOccurrences(of: ":", with: "")
        return compact.count >= 3 && compact.allSatisfy { $0 == "-" }
    }
}

enum MarkdownSyntaxHighlighter {
    enum TokenKind {
        case comment
        case string
        case number
        case keyword
    }

    private static let keywords: [String: Set<String>] = [
        "swift": [
            "let", "var", "func", "class", "struct", "enum", "protocol", "extension",
            "if", "else", "guard", "return", "for", "while", "switch", "case", "import",
            "init", "self", "nil", "true", "false", "try", "catch", "throw", "async",
            "await", "actor", "public", "private", "internal", "static", "defer",
        ],
        "javascript": [
            "const", "let", "var", "function", "return", "if", "else", "for", "while",
            "class", "new", "import", "export", "from", "async", "await", "throw",
            "try", "catch", "true", "false", "null", "undefined",
        ],
        "typescript": [
            "const", "let", "var", "function", "return", "if", "else", "for", "while",
            "class", "interface", "type", "new", "import", "export", "from", "async",
            "await", "throw", "try", "catch", "true", "false", "null", "undefined",
        ],
        "python": [
            "def", "class", "return", "if", "elif", "else", "for", "while", "import",
            "from", "as", "try", "except", "finally", "True", "False", "None", "async",
            "await", "with", "lambda", "pass", "raise", "yield",
        ],
        "bash": [
            "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case",
            "esac", "function", "export", "local", "return",
        ],
        "go": [
            "package", "import", "func", "return", "if", "else", "for", "range", "var",
            "const", "type", "struct", "interface", "go", "defer", "nil", "true", "false",
        ],
        "rust": [
            "let", "mut", "fn", "struct", "enum", "trait", "impl", "if", "else", "match",
            "for", "while", "return", "use", "pub", "const", "static", "true", "false",
        ],
        "json": ["true", "false", "null"],
    ]

    static func highlights(in code: String, language: String?) -> [(NSRange, TokenKind)] {
        let rawLanguage = (language ?? "").lowercased()
        let normalized: String
        switch rawLanguage {
        case "js", "jsx":
            normalized = "javascript"
        case "ts", "tsx":
            normalized = "typescript"
        case "sh", "shell", "zsh":
            normalized = "bash"
        case "py":
            normalized = "python"
        case "yml":
            normalized = "yaml"
        default:
            normalized = rawLanguage
        }
        let keywordSet = keywords[normalized] ?? []
        let nsCode = code as NSString
        let full = NSRange(location: 0, length: nsCode.length)
        var occupied: [NSRange] = []
        var output: [(NSRange, TokenKind)] = []

        func collect(_ pattern: String, kind: TokenKind, skipOccupied: Bool) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
                return
            }
            for match in regex.matches(in: code, options: [], range: full) {
                if skipOccupied, occupied.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    continue
                }
                occupied.append(match.range)
                output.append((match.range, kind))
            }
        }

        collect(#"(?s)/\*.*?\*/|//[^\n]*"#, kind: .comment, skipOccupied: false)
        if ["python", "bash", "yaml"].contains(normalized) {
            collect(#"#[^\n]*"#, kind: .comment, skipOccupied: true)
        }
        collect(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, kind: .string, skipOccupied: true)
        collect(#"\b\d+(?:\.\d+)?\b"#, kind: .number, skipOccupied: true)
        if !keywordSet.isEmpty {
            let words = keywordSet.map(NSRegularExpression.escapedPattern).joined(separator: "|")
            collect("\\b(?:\(words))\\b", kind: .keyword, skipOccupied: true)
        }
        return output
    }
}
