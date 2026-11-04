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
        let a = Tokenizer.tokenize(old)
        let b = Tokenizer.tokenize(new)
        let difference = b.difference(from: a)

        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }

        // One op per token. Tokens that are neither removed nor inserted are equal on both sides.
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

        // Group changes into blocks.
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
            append(DiffSegment(kind: .delete, text: blockDelete))
            append(DiffSegment(kind: .insert, text: blockInsert))
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
