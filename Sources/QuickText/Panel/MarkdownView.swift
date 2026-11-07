import SwiftUI

/// Renders a Markdown reply: headings, lists, quotes, code blocks, tables, rules and inline styles.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    init(_ markdown: String) {
        blocks = MarkdownParser.parse(markdown)
    }

    var body: some View {
        MarkdownBlocksView(blocks: blocks, spacing: 10, listDepth: 0)
            .font(.system(size: 14))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Gives inline code a light background; SwiftUI already sets it in a monospaced font.
    static func inline(_ text: AttributedString) -> AttributedString {
        var text = text
        let codeRanges = text.runs[\.inlinePresentationIntent]
            .filter { $0.0?.contains(.code) == true }
            .map(\.1)
        for range in codeRanges {
            text[range].backgroundColor = Color.primary.opacity(0.08)
        }
        return text
    }

    static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 20, weight: .semibold)
        case 2: return .system(size: 17, weight: .semibold)
        case 3: return .system(size: 15, weight: .semibold)
        default: return .system(size: 14, weight: .semibold)
        }
    }
}

private struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    let spacing: CGFloat
    let listDepth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, listDepth: listDepth)
            }
        }
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let listDepth: Int

    var body: some View {
        switch block {
        case let .paragraph(text):
            Text(MarkdownView.inline(text))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case let .heading(level, text):
            Text(MarkdownView.inline(text))
                .font(MarkdownView.headingFont(level))
                .padding(.top, level <= 2 ? 4 : 0)
                .fixedSize(horizontal: false, vertical: true)
        case let .code(language, text):
            CodeBlockView(language: language, code: text)
        case let .quote(blocks):
            MarkdownBlocksView(blocks: blocks, spacing: 8, listDepth: listDepth)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 3)
                }
        case let .list(list):
            ListBlockView(list: list, depth: listDepth)
        case let .table(table):
            TableBlockView(table: table)
        case .rule:
            Divider().padding(.vertical, 2)
        }
    }
}

private struct ListBlockView: View {
    let list: MarkdownList
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    marker(for: item)
                        .frame(minWidth: list.isOrdered ? 18 : 10, alignment: .trailing)
                    MarkdownBlocksView(blocks: item.blocks, spacing: 4, listDepth: depth + 1)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(for item: MarkdownList.Item) -> some View {
        if let isChecked = item.isChecked {
            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
        } else if list.isOrdered {
            Text("\(item.ordinal).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            Text(["•", "◦", "▪"][depth % 3])
                .foregroundStyle(.secondary)
        }
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(language ?? "code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                CopyButton(text: code, help: "Copy the code")
            }
            Text(code)
                .font(.system(size: 12.5, design: .monospaced))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

private struct TableBlockView: View {
    let table: MarkdownTable

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow(alignment: .firstTextBaseline) {
                ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                    Text(MarkdownView.inline(cell))
                        .fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true)
                        .gridColumnAlignment(alignment(column))
                }
            }
            Divider()
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow(alignment: .firstTextBaseline) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        // Wrap long cells instead of truncating them.
                        Text(MarkdownView.inline(cell))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        )
    }

    private func alignment(_ column: Int) -> HorizontalAlignment {
        switch table.alignments[column] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
