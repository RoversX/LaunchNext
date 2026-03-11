import Foundation

enum SimpleMarkdownParser {
    nonisolated static func parse(_ source: String) -> MarkdownRenderModel {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let (fence, language) = codeFenceStart(in: trimmed) {
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let current = lines[index]
                    if current.trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                        break
                    }
                    codeLines.append(current)
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.codeBlock(UUID(), language: language, code: codeLines.joined(separator: "\n")))
                continue
            }

            if let image = parseImageLine(trimmed) {
                blocks.append(.image(UUID(), alt: image.alt, source: image.source))
                index += 1
                continue
            }

            if isDivider(trimmed) {
                blocks.append(.divider(UUID()))
                index += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(.heading(UUID(), level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isQuoteLine(trimmed) {
                var quoteLines: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isQuoteLine(current) else { break }
                    quoteLines.append(stripQuotePrefix(current))
                    index += 1
                }
                blocks.append(.quote(UUID(), text: quoteLines.joined(separator: "\n")))
                continue
            }

            if let item = parseBulletItem(trimmed) {
                var items = [item]
                index += 1
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let next = parseBulletItem(current) else { break }
                    items.append(next)
                    index += 1
                }
                blocks.append(.bulletList(UUID(), items: items))
                continue
            }

            if let item = parseOrderedItem(trimmed) {
                var items = [item]
                index += 1
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let next = parseOrderedItem(current) else { break }
                    items.append(next)
                    index += 1
                }
                blocks.append(.orderedList(UUID(), items: items))
                continue
            }

            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let current = lines[index]
                let currentTrimmed = current.trimmingCharacters(in: .whitespaces)
                if currentTrimmed.isEmpty || startsSpecialBlock(currentTrimmed) {
                    break
                }
                paragraphLines.append(currentTrimmed)
                index += 1
            }
            blocks.append(.paragraph(UUID(), text: paragraphLines.joined(separator: "\n")))
        }

        return MarkdownRenderModel(blocks: blocks, previewText: previewText(from: blocks))
    }

    nonisolated static func inlineAttributedText(from source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: source, options: options) {
            return parsed
        }
        return AttributedString(source)
    }

    nonisolated private static func previewText(from blocks: [MarkdownBlock]) -> String {
        let parts = blocks.compactMap { block -> String? in
            switch block {
            case .heading(_, _, let text),
                 .paragraph(_, let text),
                 .quote(_, let text):
                return flattenInlineMarkdown(text)
            case .bulletList(_, let items),
                 .orderedList(_, let items):
                return items.map(flattenInlineMarkdown).joined(separator: "\n")
            case .codeBlock:
                return nil
            case .image(_, let alt, _):
                return alt.isEmpty ? "Image" : alt
            case .divider:
                return nil
            }
        }

        return parts.joined(separator: "\n")
    }

    nonisolated private static func flattenInlineMarkdown(_ text: String) -> String {
        var result = text
        let patterns = [
            #"\!\[([^\]]*)\]\([^)]+\)"#: "$1",
            #"\[([^\]]+)\]\([^)]+\)"#: "$1",
            #"`([^`]+)`"#: "$1",
            #"\*\*([^*]+)\*\*"#: "$1",
            #"__([^_]+)__"#: "$1",
            #"\*([^*]+)\*"#: "$1",
            #"_([^_]+)_"#: "$1"
        ]

        for (pattern, template) in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: template,
                options: .regularExpression
            )
        }

        return result
    }

    nonisolated private static func startsSpecialBlock(_ line: String) -> Bool {
        codeFenceStart(in: line) != nil ||
        parseImageLine(line) != nil ||
        isDivider(line) ||
        parseHeading(line) != nil ||
        isQuoteLine(line) ||
        parseBulletItem(line) != nil ||
        parseOrderedItem(line) != nil
    }

    nonisolated private static func codeFenceStart(in line: String) -> (fence: String, language: String?)? {
        if line.hasPrefix("```") {
            let language = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return ("```", language.isEmpty ? nil : language)
        }
        if line.hasPrefix("~~~") {
            let language = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return ("~~~", language.isEmpty ? nil : language)
        }
        return nil
    }

    nonisolated private static func isDivider(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact == "---" || compact == "***" || compact == "___"
    }

    nonisolated private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }
        let remainder = line.dropFirst(hashes.count)
        guard remainder.first == " " else { return nil }
        let text = remainder.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (hashes.count, text)
    }

    nonisolated private static func isQuoteLine(_ line: String) -> Bool {
        line.hasPrefix(">")
    }

    nonisolated private static func stripQuotePrefix(_ line: String) -> String {
        guard line.hasPrefix(">") else { return line }
        return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    nonisolated private static func parseBulletItem(_ line: String) -> String? {
        let prefixes = ["- ", "* ", "+ "]
        for prefix in prefixes where line.hasPrefix(prefix) {
            let text = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    nonisolated private static func parseOrderedItem(_ line: String) -> String? {
        guard let range = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) else {
            return nil
        }
        let text = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    nonisolated private static func parseImageLine(_ line: String) -> (alt: String, source: String)? {
        let pattern = #"^\!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: (line as NSString).length)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges == 3,
              let altRange = Range(match.range(at: 1), in: line),
              let sourceRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        return (String(line[altRange]), String(line[sourceRange]))
    }
}
