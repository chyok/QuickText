import Testing
@testable import QuickText

@Suite struct DiffEngineTests {
    private func seg(_ kind: DiffSegment.Kind, _ text: String) -> DiffSegment {
        DiffSegment(kind: kind, text: text)
    }

    @Test func noChange() {
        let segments = DiffEngine.diff(old: "same text", new: "same text")
        #expect(segments == [seg(.equal, "same text")])
        #expect(DiffEngine.changeCount(segments) == 0)
    }

    @Test func singleWordReplacement() {
        let segments = DiffEngine.diff(old: "waht are you doing", new: "what are you doing")
        #expect(segments == [seg(.delete, "waht"), seg(.insert, "what"), seg(.equal, " are you doing")])
        #expect(DiffEngine.changeCount(segments) == 1)
    }

    @Test func pureInsertion() {
        let segments = DiffEngine.diff(old: "I am here", new: "I am right here")
        #expect(segments == [seg(.equal, "I am "), seg(.insert, "right "), seg(.equal, "here")])
    }

    @Test func pureDeletion() {
        let segments = DiffEngine.diff(old: "I am really here", new: "I am here")
        #expect(segments.filter { $0.kind == .insert }.isEmpty)
        #expect(segments.map(\.text).joined() == "I am really here")
        #expect(DiffEngine.changeCount(segments) == 1)
    }

    @Test func deleteComesBeforeInsert() {
        let segments = DiffEngine.diff(old: "todays", new: "today")
        #expect(segments == [seg(.delete, "todays"), seg(.insert, "today")])
    }

    @Test func phraseRewriteIsOneBlock() {
        let segments = DiffEngine.diff(old: "a lot of peoples is here", new: "many people are here")
        #expect(segments == [
            seg(.delete, "a lot of peoples is"),
            seg(.insert, "many people are"),
            seg(.equal, " here"),
        ])
        #expect(DiffEngine.changeCount(segments) == 1)
    }

    @Test func everyEquallyShortAlignmentGivesTheSameResult() {
        // "a lot of peoples is here" → "many people are here": which spaces match is a free choice,
        // and Swift versions choose differently. These are two of the valid alignments.
        let matchLastSpace: [DiffSegment] = [
            seg(.delete, "a"), seg(.insert, "many"), seg(.equal, " "),
            seg(.delete, "lot"), seg(.delete, " "), seg(.delete, "of"), seg(.insert, "people"), seg(.equal, " "),
            seg(.delete, "peoples"), seg(.delete, " "), seg(.delete, "is"), seg(.insert, "are"), seg(.equal, " "),
            seg(.equal, "here"),
        ]
        let matchFirstSpaces: [DiffSegment] = [
            seg(.delete, "a"), seg(.insert, "many"), seg(.equal, " "),
            seg(.delete, "lot"), seg(.insert, "people"), seg(.equal, " "),
            seg(.delete, "of"), seg(.insert, "are"), seg(.equal, " "),
            seg(.delete, "peoples"), seg(.delete, " "), seg(.delete, "is"), seg(.delete, " "),
            seg(.equal, "here"),
        ]
        let expected = [seg(.delete, "a lot of peoples is"), seg(.insert, "many people are"), seg(.equal, " here")]
        #expect(DiffEngine.group(matchLastSpace) == expected)
        #expect(DiffEngine.group(matchFirstSpaces) == expected)
    }

    @Test func sharedEdgeSpaces() {
        #expect(DiffEngine.sharedEdgeSpaces(" old  ", " new ") == (" ", "old ", "new", " "))
        #expect(DiffEngine.sharedEdgeSpaces("a\n", "b\n") == ("", "a\n", "b\n", ""))
        #expect(DiffEngine.sharedEdgeSpaces("", " x") == ("", "", " x", ""))
    }

    @Test func newlinesAreNeverMergedIntoABlock() {
        let segments = DiffEngine.diff(old: "teh\nwrold", new: "the\nworld")
        #expect(segments == [
            seg(.delete, "teh"), seg(.insert, "the"),
            seg(.equal, "\n"),
            seg(.delete, "wrold"), seg(.insert, "world"),
        ])
        #expect(DiffEngine.changeCount(segments) == 2)
    }

    @Test func chineseDiffsPerCharacter() {
        let segments = DiffEngine.diff(old: "我今天很高心", new: "我今天很高兴")
        #expect(segments == [seg(.equal, "我今天很高"), seg(.delete, "心"), seg(.insert, "兴")])
    }

    @Test func bothSidesRebuildAndAdjacentSegmentsAreMerged() {
        let pairs = [
            ("i has went to the store yesterday and buyed two apple",
             "I went to the store yesterday and bought two apples."),
            ("He go to school every days.\nShe like it.", "He goes to school every day.\nShe likes it."),
            ("", "new text"), ("old text", ""),
            ("我用Swift写code，很好", "我用 Swift 写代码，很好。"),
        ]
        for (old, new) in pairs {
            let segments = DiffEngine.diff(old: old, new: new)
            #expect(segments.filter { $0.kind != .insert }.map(\.text).joined() == old)
            #expect(segments.filter { $0.kind != .delete }.map(\.text).joined() == new)
            #expect(segments.allSatisfy { !$0.text.isEmpty })
            for (a, b) in zip(segments, segments.dropFirst()) {
                #expect(a.kind != b.kind)
            }
        }
    }
}
