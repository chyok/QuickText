import Testing
@testable import QuickText

@Suite struct CheckOutputParserTests {
    @Test func notesThenBody() {
        let output = """
            - waht → what: spelling error
            - todays → today: "today" is the adverb
            ---
            what are you doing today
            """
        let parsed = CheckOutputParser.parse(output)
        #expect(parsed.notes == ["waht → what: spelling error", "todays → today: \"today\" is the adverb"])
        #expect(parsed.corrected == "what are you doing today")
    }

    @Test func noErrors() {
        let parsed = CheckOutputParser.parse("✓ No errors found\n---\nAll good here.")
        #expect(parsed.notes.isEmpty)
        #expect(parsed.corrected == "All good here.")
    }

    @Test func noErrorsInChineseText() {
        let parsed = CheckOutputParser.parse("✓ No errors found\n---\n今天天气很好。")
        #expect(parsed.notes.isEmpty)
        #expect(parsed.corrected == "今天天气很好。")
    }

    @Test func withoutSeparatorEverythingIsBody() {
        let parsed = CheckOutputParser.parse("\nWhat are you doing?\nSecond line.")
        #expect(parsed.notes.isEmpty)
        #expect(parsed.corrected == "What are you doing?\nSecond line.")
    }

    @Test func withoutSeparatorLeadingBulletsAreNotes() {
        let output = """
            • waht -> what: spelling
            * teh → the: typo
            what is the plan
            - not a change line
            """
        let parsed = CheckOutputParser.parse(output)
        #expect(parsed.notes == ["waht -> what: spelling", "teh → the: typo"])
        #expect(parsed.corrected == "what is the plan\n- not a change line")
    }

    @Test func crlfAndLooseSeparator() {
        let parsed = CheckOutputParser.parse("- a → b: reason\r\n  ---  \r\nfixed text\r\n")
        #expect(parsed.notes == ["a → b: reason"])
        #expect(parsed.corrected == "fixed text")
    }

    @Test func dashesInsideBodyAreKept() {
        let parsed = CheckOutputParser.parse("- x → y: r\n---\nTitle\n---\nBody")
        #expect(parsed.notes == ["x → y: r"])
        #expect(parsed.corrected == "Title\n---\nBody")
    }

    @Test func inlineDashesAreNotASeparator() {
        let parsed = CheckOutputParser.parse("--- not alone\nline --- two")
        #expect(parsed.notes.isEmpty)
        #expect(parsed.corrected == "--- not alone\nline --- two")
    }

    @Test func revisedListsKeepOnlyTheFinalRealChanges() {
        // Shapes taken from real haiku output.
        let revised = [
            "on → at: \"at\" is used with weekends in this idiom.",
            "any plan → any plans: plural after \"any\".",
            "Wait, I need to correct my list. The preposition should be \"for\".",
            "Corrected list:",
            "on → for: we say \"plans for\" an event.",
            "any plan → any plans: plural after \"any\".",
        ]
        #expect(CheckOutputParser.usableNotes(revised) == [
            "on → for: we say \"plans for\" an event.",
            "any plan → any plans: plural after \"any\".",
        ])

        let noOpsAndTrailingComment = [
            "we → We: A sentence starts with a capital letter.",
            "don't → don't: No change needed; this is correct.",
            "plan → plans: \"any\" takes a plural here.",
            "plan → plans: \"any\" takes a plural here.",
            "Correction note: the whole sentence should read differently.",
        ]
        #expect(CheckOutputParser.usableNotes(noOpsAndTrailingComment) == [
            "we → We: A sentence starts with a capital letter.",
            "plan → plans: \"any\" takes a plural here.",
        ])

        #expect(CheckOutputParser.usableNotes(["Just some commentary."]).isEmpty)
    }

    @Test func changeNoteSplitting() {
        #expect(ChangeNote.parse("waht → what: spelling error")
                == ChangeNote(original: "waht", corrected: "what", reason: "spelling error"))
        #expect(ChangeNote.parse("its -> it's：contraction")
                == ChangeNote(original: "its", corrected: "it's", reason: "contraction"))
        #expect(ChangeNote.parse(" → the: missing article")
                == ChangeNote(original: "", corrected: "the", reason: "missing article"))
        #expect(ChangeNote.parse("very → : redundant")
                == ChangeNote(original: "very", corrected: "", reason: "redundant"))
        // A colon inside the corrected words ("10:45") is not the separator; ": " after them is.
        #expect(ChangeNote.parse("Time: 10:30 → 10:45: wrong time")
                == ChangeNote(original: "Time: 10:30", corrected: "10:45", reason: "wrong time"))
        // Whichever separator comes first wins, ASCII or full-width.
        #expect(ChangeNote.parse("a → b: use b here：it is the idiom")
                == ChangeNote(original: "a", corrected: "b", reason: "use b here：it is the idiom"))
        #expect(ChangeNote.parse("的 → 地：修饰动词用「地」")
                == ChangeNote(original: "的", corrected: "地", reason: "修饰动词用「地」"))
        #expect(ChangeNote.parse("no arrow here: reason") == nil)
        #expect(ChangeNote.parse("a → b") == nil)
        #expect(ChangeNote.parse(" → : reason") == nil)
    }
}
