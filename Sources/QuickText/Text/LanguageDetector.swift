import Foundation

enum TranslationDirection: Equatable, Sendable {
    case toEnglish
    case toChinese

    var label: String {
        switch self {
        case .toEnglish: return "ZH→EN"
        case .toChinese: return "EN→ZH"
        }
    }

    var targetLanguage: String {
        switch self {
        case .toEnglish: return "English"
        case .toChinese: return "Simplified Chinese (简体中文)"
        }
    }
}

enum LanguageDetector {
    /// Unicode scalars in U+3400–U+9FFF.
    static func cjkCount(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { count, scalar in
            (0x3400...0x9FFF).contains(scalar.value) ? count + 1 : count
        }
    }

    /// Runs of ASCII letters [A-Za-z]+.
    static func englishWordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            let isLetter = (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
            if isLetter && !inWord { count += 1 }
            inWord = isLetter
        }
        return count
    }

    static func direction(for text: String) -> TranslationDirection {
        let cjk = cjkCount(text)
        return cjk > 0 && cjk >= englishWordCount(text) ? .toEnglish : .toChinese
    }
}
