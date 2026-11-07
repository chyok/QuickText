import Foundation

/// A block of a Markdown reply. Inline styles (bold, italic, code, strikethrough, links) stay
/// on the `AttributedString` runs, where SwiftUI's `Text` renders them.
enum MarkdownBlock: Equatable {
    case paragraph(AttributedString)
    case heading(level: Int, text: AttributedString)
    case code(language: String?, text: String)
    case quote([MarkdownBlock])
    case list(MarkdownList)
    case table(MarkdownTable)
    case rule
}

struct MarkdownList: Equatable {
    struct Item: Equatable {
        var ordinal: Int
        /// `true` / `false` for a task list item (`- [x]` / `- [ ]`), `nil` otherwise.
        var isChecked: Bool?
        var blocks: [MarkdownBlock]
    }

    var isOrdered: Bool
    var items: [Item]
}

struct MarkdownTable: Equatable {
    enum Alignment: Equatable { case leading, center, trailing }

    var alignments: [Alignment]
    var header: [AttributedString]
    /// Every row has one cell per column; empty cells are empty strings.
    var rows: [[AttributedString]]
}

/// Splits Markdown into blocks. Foundation does the parsing (CommonMark plus GitHub tables and
/// strikethrough) and tags every run with the blocks it sits in; this rebuilds the block tree.
enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let document = try? AttributedString(markdown: keepingLineBreaks(markdown), options: options) else {
            return [.paragraph(AttributedString(markdown))]
        }

        var leaves: [Leaf] = []
        for (intent, range) in document.runs[\.presentationIntent] {
            let components = intent?.components ?? []
            let leaf = Leaf(
                kind: components.first?.kind ?? .paragraph,
                identity: components.first?.identity ?? -1,
                containers: components.dropFirst().reversed(),
                text: AttributedString(document[range])
            )
            if let last = leaves.last, last.identity == leaf.identity, leaf.identity != -1 {
                leaves[leaves.count - 1].text += leaf.text
            } else {
                leaves.append(leaf)
            }
        }
        return blocks(leaves[...], depth: 0)
    }

    /// Model replies use a single newline as a line break, which CommonMark would turn into a
    /// space. Ends each such line with two spaces (a hard break), leaving fenced code alone.
    static func keepingLineBreaks(_ markdown: String) -> String {
        var lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var fence: String?
        for index in lines.indices {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if let marker = ["```", "~~~"].first(where: line.hasPrefix) {
                if fence == nil {
                    fence = marker
                } else if fence == marker {
                    fence = nil
                }
                continue
            }
            let nextIsText = index + 1 < lines.count
                && !lines[index + 1].trimmingCharacters(in: .whitespaces).isEmpty
            if fence == nil, !line.isEmpty, nextIsText,
               !lines[index].hasSuffix("  "), !lines[index].hasSuffix("\\") {
                lines[index] += "  "
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Building the tree

    /// One leaf block (paragraph, heading, code block, rule or table cell) and the containers
    /// it sits in, outermost first.
    private struct Leaf {
        var kind: PresentationIntent.Kind
        var identity: Int
        var containers: [PresentationIntent.IntentType]
        var text: AttributedString
    }

    /// Builds the blocks for `leaves`, all of which share their first `depth` containers.
    private static func blocks(_ leaves: ArraySlice<Leaf>, depth: Int) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var rest = leaves
        while let first = rest.first {
            guard depth < first.containers.count else {
                if let block = leafBlock(first) { result.append(block) }
                rest = rest.dropFirst()
                continue
            }
            let container = first.containers[depth]
            let group = rest.prefix { depth < $0.containers.count && $0.containers[depth].identity == container.identity }
            rest = rest.dropFirst(group.count)

            switch container.kind {
            case .blockQuote:
                result.append(.quote(blocks(group, depth: depth + 1)))
            case .orderedList, .unorderedList:
                result.append(.list(list(group, depth: depth, isOrdered: container.kind == .orderedList)))
            case let .table(columns):
                result.append(.table(table(group, depth: depth, columns: columns)))
            default:
                // A container this view doesn't draw: show its content in place.
                result += blocks(group, depth: depth + 1)
            }
        }
        return result
    }

    private static func leafBlock(_ leaf: Leaf) -> MarkdownBlock? {
        switch leaf.kind {
        case let .header(level):
            return .heading(level: level, text: leaf.text)
        case let .codeBlock(language):
            var code = String(leaf.text.characters)
            if code.hasSuffix("\n") { code.removeLast() }
            return .code(language: language.flatMap { $0.isEmpty ? nil : $0 }, text: code)
        case .thematicBreak:
            return .rule
        default:
            return leaf.text.characters.isEmpty ? nil : .paragraph(leaf.text)
        }
    }

    private static func list(_ leaves: ArraySlice<Leaf>, depth: Int, isOrdered: Bool) -> MarkdownList {
        var items: [MarkdownList.Item] = []
        var rest = leaves
        while let first = rest.first {
            let identity = first.containers.count > depth + 1 ? first.containers[depth + 1].identity : nil
            let group = identity.map { id in rest.prefix { $0.containers.count > depth + 1 && $0.containers[depth + 1].identity == id } }
                ?? rest.prefix(1)
            rest = rest.dropFirst(group.count)

            var ordinal = items.count + 1
            if case let .listItem(value) = first.containers[safe: depth + 1]?.kind { ordinal = value }
            var item = MarkdownList.Item(ordinal: ordinal, isChecked: nil, blocks: blocks(group, depth: depth + 2))
            if case let .paragraph(text)? = item.blocks.first, let task = taskMarker(text) {
                item.isChecked = task.isChecked
                item.blocks[0] = .paragraph(task.text)
            }
            items.append(item)
        }
        return MarkdownList(isOrdered: isOrdered, items: items)
    }

    /// Splits `[ ] ` or `[x] ` off the start of a task list item.
    private static func taskMarker(_ text: AttributedString) -> (isChecked: Bool, text: AttributedString)? {
        let start = String(text.characters.prefix(4))
        guard ["[ ] ", "[x] ", "[X] "].contains(start) else { return nil }
        let rest = text[text.index(text.startIndex, offsetByCharacters: 4)...]
        return (start != "[ ] ", AttributedString(rest))
    }

    private static func table(_ leaves: ArraySlice<Leaf>, depth: Int,
                              columns: [PresentationIntent.TableColumn]) -> MarkdownTable {
        var header = Array(repeating: AttributedString(), count: columns.count)
        var rows: [Int: [AttributedString]] = [:]
        for leaf in leaves {
            guard case let .tableCell(column) = leaf.kind, column < columns.count,
                  let row = leaf.containers[safe: depth + 1] else { continue }
            switch row.kind {
            case .tableHeaderRow:
                header[column] = leaf.text
            case let .tableRow(index):
                rows[index, default: header.map { _ in AttributedString() }][column] = leaf.text
            default:
                continue
            }
        }
        // A row whose cells are all empty has no runs at all, so it never shows up here.
        let alignments: [MarkdownTable.Alignment] = columns.map {
            switch $0.alignment {
            case .center: return .center
            case .right: return .trailing
            default: return .leading
            }
        }
        return MarkdownTable(alignments: alignments, header: header,
                             rows: rows.keys.sorted().compactMap { rows[$0] })
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
