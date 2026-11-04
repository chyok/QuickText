import Foundation

struct ParsedCheckOutput: Equatable {
    var corrected: String
    var notes: [String]
}

/// One explanation line split into parts for coloring: `original → corrected: reason`.
struct ChangeNote: Equatable {
    var original: String
    var corrected: String
    var reason: String

    static func parse(_ line: String) -> ChangeNote? {
        guard let arrow = line.range(of: "→") ?? line.range(of: "->") else { return nil }
        let rest = line[arrow.upperBound...]
        // The first ": " (or full-width "："); a bare ":" only if there is neither, so "10:45" stays whole.
        guard let colon = rest.range(of: "：|: ", options: .regularExpression) ?? rest.range(of: ":") else {
            return nil
        }
        let original = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
        let corrected = rest[..<colon.lowerBound].trimmingCharacters(in: .whitespaces)
        let reason = rest[colon.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !(original.isEmpty && corrected.isEmpty), !reason.isEmpty else { return nil }
        return ChangeNote(original: original, corrected: corrected, reason: reason)
    }
}

enum CheckOutputParser {
    private static let bullets: Set<Character> = ["-", "*", "•", "·"]

    static func isNoErrorsMarker(_ line: String) -> Bool {
        line.lowercased().contains("no errors found")
    }

    /// The line without a leading bullet, trimmed.
    private static func unbulleted(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, bullets.contains(first) else { return trimmed }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    /// A line like `- waht → what: spelling`.
    private static func isBulletChange(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, bullets.contains(first) else { return false }
        return trimmed.contains("→") || trimmed.contains("->")
    }

    /// Small models sometimes revise their list mid-answer ("Wait, I need to correct my list…").
    /// Keeps only real `a → b: reason` changes from the last list the model wrote, with duplicates removed.
    static func usableNotes(_ notes: [String]) -> [String] {
        var groups: [[String]] = [[]]
        for line in notes {
            guard let note = ChangeNote.parse(line) else {
                groups.append([])  // Commentary starts a new list.
                continue
            }
            if note.original != note.corrected {
                groups[groups.count - 1].append(line)
            }
        }
        let last = groups.last { !$0.isEmpty } ?? []
        var seen = Set<String>()
        return last.filter { line in
            guard let note = ChangeNote.parse(line) else { return false }
            return seen.insert(note.original + "\u{0}" + note.corrected).inserted
        }
    }

    static func parse(_ output: String) -> ParsedCheckOutput {
        let lines = output.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        var noteLines: ArraySlice<String>
        var bodyLines: ArraySlice<String>

        if let separator = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            noteLines = lines[..<separator]
            bodyLines = lines[(separator + 1)...]
        } else {
            var start = 0
            while start < lines.count {
                let trimmed = lines[start].trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || isNoErrorsMarker(trimmed) || isBulletChange(trimmed) {
                    start += 1
                } else {
                    break
                }
            }
            noteLines = lines[..<start]
            bodyLines = lines[start...]
        }

        let notes = noteLines
            .filter { !isNoErrorsMarker($0) }
            .map(unbulleted)
            .filter { !$0.isEmpty }
        let corrected = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedCheckOutput(corrected: corrected, notes: notes)
    }
}
