import Foundation

struct DiffSegment: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case equal, delete, insert }
    var kind: Kind
    var text: String
}

enum DiffEngine {
    /// Token-level diff of `old` → `new`. Changes separated only by spaces are merged into one
    /// block, which is emitted as a delete followed by an insert.
    static func diff(old: String, new: String) -> [DiffSegment] {
        group(tokenOps(old: Tokenizer.tokenize(old), new: Tokenizer.tokenize(new)))
    }

    /// One op per token. Tokens that are neither removed nor inserted are equal on both sides.
    /// When several alignments are equally short (which spaces "match"), the standard library's
    /// choice differs between Swift versions; `group` makes the final result the same for all of them.
    static func tokenOps(old a: [String], new b: [String]) -> [DiffSegment] {
        let difference = b.difference(from: a)

        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }

        var ops: [DiffSegment] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) || j == b.count {
                ops.append(DiffSegment(kind: .delete, text: a[i]))
                i += 1
            } else if j < b.count, inserted.contains(j) || i == a.count {
                ops.append(DiffSegment(kind: .insert, text: b[j]))
                j += 1
            } else {
                ops.append(DiffSegment(kind: .equal, text: a[i]))
                i += 1
                j += 1
            }
        }
        return ops
    }

    /// Groups token ops into change blocks and merges neighbouring segments of the same kind.
    static func group(_ ops: [DiffSegment]) -> [DiffSegment] {
        var result: [DiffSegment] = []
        var blockDelete = ""
        var blockInsert = ""
        var blockHasChange = false

        func append(_ segment: DiffSegment) {
            guard !segment.text.isEmpty else { return }
            if let last = result.last, last.kind == segment.kind {
                result[result.count - 1].text += segment.text
            } else {
                result.append(segment)
            }
        }

        func flushBlock() {
            // Spaces that both sides start or end with are unchanged text, whichever spaces the diff matched.
            let shared = sharedEdgeSpaces(blockDelete, blockInsert)
            append(DiffSegment(kind: .equal, text: shared.leading))
            append(DiffSegment(kind: .delete, text: shared.old))
            append(DiffSegment(kind: .insert, text: shared.new))
            append(DiffSegment(kind: .equal, text: shared.trailing))
            blockDelete = ""
            blockInsert = ""
            blockHasChange = false
        }

        for (index, op) in ops.enumerated() {
            switch op.kind {
            case .delete:
                blockDelete += op.text
                blockHasChange = true
            case .insert:
                blockInsert += op.text
                blockHasChange = true
            case .equal:
                let isSpaceOnly = !op.text.isEmpty
                    && op.text.allSatisfy { $0.isWhitespace && !$0.isNewline }
                let nextIsChange = index + 1 < ops.count && ops[index + 1].kind != .equal
                if isSpaceOnly && blockHasChange && nextIsChange {
                    blockDelete += op.text
                    blockInsert += op.text
                } else {
                    flushBlock()
                    append(op)
                }
            }
        }
        flushBlock()
        return result
    }

    /// Splits off the spaces (not newlines) that `old` and `new` both start and end with.
    static func sharedEdgeSpaces(_ old: String, _ new: String)
        -> (leading: String, old: String, new: String, trailing: String) {
        func isSpace(_ character: Character) -> Bool { character.isWhitespace && !character.isNewline }

        let leadingCount = zip(old, new).prefix { $0 == $1 && isSpace($0) }.count
        let leading = String(old.prefix(leadingCount))
        var old = old.dropFirst(leadingCount), new = new.dropFirst(leadingCount)

        let trailingCount = zip(old.reversed(), new.reversed()).prefix { $0 == $1 && isSpace($0) }.count
        let trailing = String(old.suffix(trailingCount))
        old.removeLast(trailingCount)
        new.removeLast(trailingCount)
        return (leading, String(old), String(new), trailing)
    }

    /// Number of contiguous change groups.
    static func changeCount(_ segments: [DiffSegment]) -> Int {
        var count = 0
        var inChange = false
        for segment in segments {
            let isChange = segment.kind != .equal
            if isChange && !inChange { count += 1 }
            inChange = isChange
        }
        return count
    }
}
