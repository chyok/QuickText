import Testing
@testable import QuickText

@Suite struct LanguageDetectorTests {
    @Test func chineseGoesToEnglish() {
        #expect(LanguageDetector.direction(for: "下周三我们开会") == .toEnglish)
    }

    @Test func englishGoesToChinese() {
        #expect(LanguageDetector.direction(for: "We have a meeting next Wednesday") == .toChinese)
    }

    @Test func textWithoutCJKGoesToChinese() {
        #expect(LanguageDetector.direction(for: "123 !!! 😀") == .toChinese)
        #expect(LanguageDetector.direction(for: "") == .toChinese)
    }

    @Test func mixedTextCountsAndTies() {
        // 4 CJK vs 1 English word.
        #expect(LanguageDetector.direction(for: "我用Swift写") == .toEnglish)
        // 1 CJK vs 3 English words.
        #expect(LanguageDetector.direction(for: "this is 好 code") == .toChinese)
        // Tie: 2 CJK vs 2 words → Chinese wins.
        #expect(LanguageDetector.direction(for: "你好 hello world") == .toEnglish)
    }

    @Test func countFunctions() {
        #expect(LanguageDetector.cjkCount("你好，world") == 2)
        #expect(LanguageDetector.cjkCount("こんにちは") == 0)
        #expect(LanguageDetector.englishWordCount("don't stop-me now2go") == 6)
        #expect(LanguageDetector.englishWordCount("café") == 1)
    }

    @Test func directionLabels() {
        #expect(TranslationDirection.toEnglish.label == "ZH→EN")
        #expect(TranslationDirection.toChinese.label == "EN→ZH")
        #expect(TranslationDirection.toEnglish.targetLanguage == "English")
        #expect(TranslationDirection.toChinese.targetLanguage == "Simplified Chinese (简体中文)")
    }
}
