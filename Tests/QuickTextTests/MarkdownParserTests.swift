import Foundation
import Testing
@testable import QuickText

@Suite struct MarkdownParserTests {
    /// One line per block, indented by nesting, so the tree is easy to compare.
    private func outline(_ blocks: [MarkdownBlock], indent: String = "") -> [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case let .paragraph(text):
                return [indent + "p " + String(text.characters)]
            case let .heading(level, text):
                return [indent + "h\(level) " + String(text.characters)]
            case let .code(language, text):
                return [indent + "code(\(language ?? "-")) " + text]
            case let .quote(blocks):
                return [indent + "quote"] + outline(blocks, indent: indent + "  ")
            case let .list(list):
                return list.items.flatMap { item -> [String] in
                    let marker = item.isChecked.map { $0 ? "[x]" : "[ ]" } ?? (list.isOrdered ? "\(item.ordinal)." : "-")
                    return [indent + marker] + outline(item.blocks, indent: indent + "  ")
                }
            case let .table(table):
                return [indent + "table " + table.header.map { String($0.characters) }.joined(separator: "|")]
                    + table.rows.map { indent + "  " + $0.map { String($0.characters) }.joined(separator: "|") }
            case .rule:
                return [indent + "rule"]
            }
        }
    }

    private func parse(_ markdown: String) -> [String] {
        outline(MarkdownParser.parse(markdown))
    }

    @Test func plainTextKeepsItsLineBreaks() {
        #expect(parse("Line one\nline two\n\nNext paragraph") == ["p Line one\nline two", "p Next paragraph"])
    }

    @Test func headingsAndRules() {
        #expect(parse("# Title\nIntro\n\n---\n\n### Small") == ["h1 Title", "p Intro", "rule", "h3 Small"])
    }

    @Test func inlineStylesStayOnTheRuns() throws {
        let blocks = MarkdownParser.parse("Use **bold**, `code` and [a link](https://example.com).")
        guard case let .paragraph(text) = try #require(blocks.first) else {
            Issue.record("Expected a paragraph")
            return
        }
        #expect(String(text.characters) == "Use bold, code and a link.")
        let intents = text.runs[\.inlinePresentationIntent].compactMap(\.0)
        #expect(intents.contains(.stronglyEmphasized))
        #expect(intents.contains(.code))
        #expect(text.runs[\.link].contains { $0.0 == URL(string: "https://example.com") })
    }

    @Test func nestedListsKeepTheirNumbers() {
        let markdown = """
        3. Third
        4. Fourth
           - nested a
           - nested b

        - [ ] todo
        - [x] done
        """
        #expect(parse(markdown) == [
            "3.", "  p Third",
            "4.", "  p Fourth", "  -", "    p nested a", "  -", "    p nested b",
            "[ ]", "  p todo",
            "[x]", "  p done",
        ])
    }

    @Test func quotesHoldSeveralBlocks() {
        #expect(parse("> first\n>\n> - item\n\nafter") == ["quote", "  p first", "  -", "    p item", "p after"])
    }

    @Test func codeBlocksAreLeftAsTyped() {
        let markdown = "```swift\nlet a = 1\n\nprint(a)  \n```\n\n```\nplain\n```"
        #expect(parse(markdown) == ["code(swift) let a = 1\n\nprint(a)  ", "code(-) plain"])
    }

    @Test func tablesFillEmptyCells() throws {
        let markdown = "| Name | Count |\n|:--|--:|\n| a | 1 |\n| b |  |"
        #expect(parse(markdown) == ["table Name|Count", "  a|1", "  b|"])
        guard case let .table(table) = try #require(MarkdownParser.parse(markdown).first) else {
            Issue.record("Expected a table")
            return
        }
        #expect(table.alignments == [.leading, .trailing])
    }

    @Test func lineBreaksAreAddedOutsideFencesOnly() {
        #expect(MarkdownParser.keepingLineBreaks("a\nb\n\nc") == "a  \nb\n\nc")
        #expect(MarkdownParser.keepingLineBreaks("~~~\nx\ny\n~~~\nz") == "~~~\nx\ny\n~~~\nz")
        // A ``` line inside a ~~~ fence doesn't close it.
        #expect(MarkdownParser.keepingLineBreaks("~~~\n```\nx\n~~~") == "~~~\n```\nx\n~~~")
        #expect(MarkdownParser.keepingLineBreaks("a\\\nb\r\nc") == "a\\\nb  \nc")
    }
}
