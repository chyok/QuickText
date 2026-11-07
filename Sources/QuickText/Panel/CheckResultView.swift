import AppKit
import SwiftUI

struct CheckResultView: View {
    let result: CheckResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if result.hasChanges {
                Text(DiffRenderer.render(result.segments))
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(result.corrected)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !result.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(result.notes.enumerated()), id: \.offset) { _, note in
                        Text(DiffRenderer.noteLine(note))
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Divider() }
            } else if !result.hasChanges {
                Label("No errors found", systemImage: "checkmark")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
    }
}

enum DiffRenderer {
    private static let red = Color(nsColor: .systemRed)
    private static let green = Color(nsColor: .systemGreen)

    static func deleted(_ text: String) -> AttributedString {
        var s = AttributedString(text.replacingOccurrences(of: "\n", with: "↵"))
        s.foregroundColor = red
        s.backgroundColor = red.opacity(0.12)
        s.strikethroughStyle = Text.LineStyle(pattern: .solid, color: red)
        return s
    }

    static func inserted(_ text: String, bold: Bool = true) -> AttributedString {
        var s = AttributedString(bold ? text.replacingOccurrences(of: "\n", with: "↵\n") : text)
        s.foregroundColor = green
        s.backgroundColor = green.opacity(0.15)
        if bold { s.font = .system(size: 14, weight: .semibold) }
        return s
    }

    static func render(_ segments: [DiffSegment]) -> AttributedString {
        segments.reduce(into: AttributedString()) { result, segment in
            switch segment.kind {
            case .equal: result += AttributedString(segment.text)
            case .delete: result += deleted(segment.text)
            case .insert: result += inserted(segment.text)
            }
        }
    }

    /// `•  original  →  corrected: reason`, with the two sides colored like the diff.
    static func noteLine(_ line: String) -> AttributedString {
        guard let note = ChangeNote.parse(line) else {
            return AttributedString("•  " + line)
        }
        var result = AttributedString("•  ")
        result += note.original.isEmpty ? AttributedString("(nothing)") : deleted(note.original)
        result += AttributedString("  →  ")
        result += note.corrected.isEmpty ? AttributedString("(removed)") : inserted(note.corrected, bold: false)
        result += AttributedString(": " + note.reason)
        return result
    }
}
