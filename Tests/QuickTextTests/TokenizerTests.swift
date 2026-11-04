import Testing
@testable import QuickText

@Suite struct TokenizerTests {
    @Test func englishWordsSpacesAndPunctuation() {
        #expect(Tokenizer.tokenize("Hello,  world!") == ["Hello", ",", "  ", "world", "!"])
    }

    @Test func contractionApostrophes() {
        #expect(Tokenizer.tokenize("don't it’s") == ["don't", " ", "it’s"])
        #expect(Tokenizer.tokenize("'quoted' dogs'") == ["'", "quoted", "'", " ", "dogs", "'"])
    }

    @Test func cjkIsOneTokenPerCharacter() {
        #expect(Tokenizer.tokenize("今天天气") == ["今", "天", "天", "气"])
        #expect(Tokenizer.tokenize("한국어") == ["한", "국", "어"])
    }

    @Test func mixedChineseAndEnglish() {
        #expect(Tokenizer.tokenize("我用Swift写code，很好") == ["我", "用", "Swift", "写", "code", "，", "很", "好"])
    }

    @Test func emojiAndCRLF() {
        #expect(Tokenizer.tokenize("hi 👋🏽\r\nok") == ["hi", " ", "👋🏽", "\r\n", "ok"])
    }

    @Test func numbersAndAccentedLetters() {
        #expect(Tokenizer.tokenize("café 3.14") == ["café", " ", "3", ".", "14"])
    }

    @Test func joiningTokensRestoresOriginal() {
        let samples = [
            "", "  leading and trailing  ", "line one\nline two\r\n\tthree",
            "我用Swift写code，很好！", "It's 5 o’clock — time 🍵.", "a--b...c???",
        ]
        for sample in samples {
            #expect(Tokenizer.tokenize(sample).joined() == sample)
        }
    }
}
