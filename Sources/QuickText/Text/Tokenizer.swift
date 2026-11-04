import Foundation

/// Splits text into word / whitespace / CJK-character / punctuation tokens.
/// Joining all tokens always gives back the original text.
enum Tokenizer {
    private enum Category { case whitespace, cjk, word, apostrophe, other }

    private static let cjkRanges: [ClosedRange<UInt32>] = [
        0x2E80...0x2FDF, 0x3040...0x30FF, 0x3100...0x312F, 0x3400...0x4DBF,
        0x4E00...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0x20000...0x3134F,
    ]

    static func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return cjkRanges.contains { $0.contains(scalar.value) }
    }

    private static func category(of character: Character) -> Category {
        if character.isWhitespace { return .whitespace }
        if isCJK(character) { return .cjk }
        if character == "'" || character == "’" { return .apostrophe }
        if character.isLetter || character.isNumber { return .word }
        return .other
    }

    static func tokenize(_ text: String) -> [String] {
        let chars = Array(text)
        var tokens: [String] = []
        var current = ""
        var currentCategory: Category?

        func flush() {
            if !current.isEmpty { tokens.append(current) }
            current = ""
            currentCategory = nil
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            let cat = category(of: c)
            switch cat {
            case .whitespace:
                if currentCategory != .whitespace { flush() }
                current.append(c)
                currentCategory = .whitespace
            case .word:
                if currentCategory != .word { flush() }
                current.append(c)
                currentCategory = .word
            case .apostrophe:
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                if currentCategory == .word, let next, category(of: next) == .word {
                    current.append(c)
                } else {
                    flush()
                    tokens.append(String(c))
                }
            case .cjk, .other:
                flush()
                tokens.append(String(c))
            }
            i += 1
        }
        flush()
        return tokens
    }
}
