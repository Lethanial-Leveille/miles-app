import Foundation

// One block level piece of a reply. Inline styling (bold, italics, links) stays inside the
// strings, because AttributedString already renders inline markdown well and blocks not at all.
enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case listItem(marker: String, depth: Int, text: String)
    case quote(String)
    case code(String)
    case table(String)
    case rule
}

// Deliberately small: it covers what Nova actually writes on the text channel, not all of
// CommonMark, and anything it does not recognize falls through as a plain paragraph.
enum MarkdownParser {

    private enum Run {
        case paragraph, quote, table
    }

    static func blocks(from source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var code: [String]? = nil
        var runKind: Run? = nil
        var runLines: [String] = []

        // Consecutive lines of the same kind become one block, so flush whenever the kind changes
        func flush() {
            if let kind = runKind, !runLines.isEmpty {
                switch kind {
                case .paragraph: blocks.append(.paragraph(runLines.joined(separator: "\n")))
                case .quote:     blocks.append(.quote(runLines.joined(separator: "\n")))
                case .table:     blocks.append(.table(alignedTable(runLines)))
                }
            }
            runKind = nil
            runLines = []
        }

        func add(_ line: String, to kind: Run) {
            if runKind != kind { flush() }
            runKind = kind
            runLines.append(line)
        }

        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Inside a fence nothing is interpreted until the closing fence
            if code != nil {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code((code ?? []).joined(separator: "\n")))
                    code = nil
                } else {
                    code?.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flush()
                code = []
            } else if trimmed.isEmpty {
                flush()
            } else if trimmed.hasPrefix("|") {
                add(trimmed, to: .table)
            } else if trimmed.hasPrefix(">") {
                add(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces), to: .quote)
            } else if isRule(trimmed) {
                // Checked before lists, since "* * *" would otherwise read as a bullet
                flush()
                blocks.append(.rule)
            } else if let block = heading(in: trimmed) ?? listItem(in: line) {
                flush()
                blocks.append(block)
            } else {
                add(trimmed, to: .paragraph)
            }
        }

        // A reply that ends inside an unclosed fence still shows its code
        if let open = code {
            blocks.append(.code(open.joined(separator: "\n")))
        }
        flush()
        return blocks
    }

    // MARK: Line recognizers

    private static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { $0 != " " }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func heading(in trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(in line: String) -> MarkdownBlock? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let columns = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let depth = columns / 2
        let body = line.dropFirst(indent.count)

        if let marker = body.first, "-*+".contains(marker), body.dropFirst().first == " " {
            return .listItem(marker: "•", depth: depth, text: body.dropFirst(2).trimmingCharacters(in: .whitespaces))
        }

        let digits = body.prefix { ("0"..."9").contains($0) }
        guard (1...3).contains(digits.count) else { return nil }
        let rest = body.dropFirst(digits.count)
        guard let punctuation = rest.first, punctuation == "." || punctuation == ")",
              rest.dropFirst().first == " "
        else { return nil }
        return .listItem(marker: "\(digits).", depth: depth, text: rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
    }

    // MARK: Tables

    // Columns padded to equal width in a monospaced font read as a table with no layout code.
    // Inline markers are dropped because the table is shown as plain monospaced text.
    private static func alignedTable(_ lines: [String]) -> String {
        let rows: [[String]] = lines.map { line in
            var cells = line.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.first == "" { cells.removeFirst() }
            if cells.last == "" { cells.removeLast() }
            return cells.map { $0.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "") }
        }

        let isDivider: ([String]) -> Bool = { cells in
            !cells.isEmpty && cells.allSatisfy { !$0.isEmpty && $0.allSatisfy { "-:".contains($0) } }
        }
        let hasHeader = rows.contains(where: isDivider)
        let content = rows.filter { !isDivider($0) }

        let columnCount = content.map(\.count).max() ?? 0
        var widths = Array(repeating: 0, count: columnCount)
        for row in content {
            for (column, cell) in row.enumerated() {
                widths[column] = max(widths[column], cell.count)
            }
        }

        var output: [String] = []
        for (index, row) in content.enumerated() {
            let padded = (0..<columnCount).map { column -> String in
                let cell = column < row.count ? row[column] : ""
                return cell + String(repeating: " ", count: widths[column] - cell.count)
            }
            output.append(trimTrailingSpaces(padded.joined(separator: "  ")))

            if index == 0 && hasHeader {
                output.append(widths.map { String(repeating: "─", count: $0) }.joined(separator: "  "))
            }
        }
        return output.joined(separator: "\n")
    }

    private static func trimTrailingSpaces(_ text: String) -> String {
        var result = text
        while result.hasSuffix(" ") { result.removeLast() }
        return result
    }
}
