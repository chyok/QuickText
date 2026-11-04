import Testing
@testable import QuickText

@Suite struct TaskRunnerTests {
    private func checkResult(_ output: String, text: String) async throws -> CheckResult {
        let result = try await TaskRunner(backend: FakeBackend(output: output)).perform(.check, text: text)
        guard case let .check(check) = result else {
            Issue.record("expected a check result, got \(result)")
            return CheckResult(corrected: "", segments: [], notes: [])
        }
        return check
    }

    @Test func checkAssemblesDiff() async throws {
        let backend = FakeBackend(output: "- waht → what: spelling error\n---\nwhat are you doing")
        let result = try await TaskRunner(backend: backend).perform(.check, text: "  waht are you doing\n")
        #expect(result.copyText == "what are you doing")
        #expect(backend.calls.first?.user == "<text>\n  waht are you doing\n\n</text>")

        let check = try await checkResult("- waht → what: spelling error\n---\nwhat are you doing",
                                          text: "waht are you doing")
        #expect(check.notes == ["waht → what: spelling error"])
        #expect(check.hasChanges)
        #expect(check.changeCount == 1)
    }

    @Test func checkWithNoErrors() async throws {
        let check = try await checkResult("<text>\n✓ No errors found\n---\nAll good.\n</text>", text: "All good.")
        #expect(!check.hasChanges)
        #expect(check.notes.isEmpty)
        #expect(check.corrected == "All good.")
    }

    @Test func notesAreKeptEvenWhenTheBodyIsUnchanged() async throws {
        let check = try await checkResult("- waht → what: spelling\n---\nwaht is it", text: "waht is it")
        #expect(!check.hasChanges)
        #expect(check.notes == ["waht → what: spelling"])
    }

    @Test func notesWithoutBodyKeepTheOriginal() async throws {
        let check = try await checkResult("- waht → what: spelling\n---\n", text: "waht is it")
        #expect(check.corrected == "waht is it")
        #expect(check.segments == [DiffSegment(kind: .equal, text: "waht is it")])
        #expect(check.notes.count == 1)
    }

    @Test func emptyOutputIsAnError() async {
        for output in ["", "  \n", "<text>\n</text>"] {
            await #expect(throws: LLMError.emptyResult) {
                try await TaskRunner(backend: FakeBackend(output: output)).perform(.refine(.natural), text: "hi")
            }
        }
    }

    @Test func translationDirectionAndTitles() {
        #expect(TaskRunner.resolve(.translate, text: "你好世界", refineStyle: .natural) == .translate(.toEnglish))
        #expect(TaskRunner.resolve(.translate, text: "hello", refineStyle: .natural) == .translate(.toChinese))
        #expect(TaskRunner.resolve(.refine, text: "x", refineStyle: .formal) == .refine(.formal))
        #expect(TextAction.translate(.toEnglish).title == "Translate · ZH→EN")
        #expect(TextAction.refine(.concise).title == "Refine · Concise")
        #expect(TextAction.check.title == "Check")
        #expect(TextAction.send.title == "Send")
        #expect(TextAction.send.loadingText == "Thinking…")
    }

    @Test func promptedActionsCarryTheInjectionGuard() async throws {
        let backend = FakeBackend(output: "ok")
        let runner = TaskRunner(backend: backend)
        _ = try await runner.perform(.check, text: "a")
        _ = try await runner.perform(.refine(.polite), text: "b")
        _ = try await runner.perform(.translate(.toChinese), text: "c")
        #expect(backend.calls.count == 3)
        for call in backend.calls {
            #expect(call.system.hasSuffix("\n\n" + Prompts.injectionGuard))
            #expect(call.user.hasPrefix("<text>\n") && call.user.hasSuffix("\n</text>"))
        }
        #expect(backend.calls[1].system.contains(RefineStyle.polite.promptDescription))
        #expect(backend.calls[2].system.contains(TranslationDirection.toChinese.targetLanguage))
    }

    @Test func sendHasNoPromptAndOnlyTrimsTheOutput() async throws {
        let raw = "  What is <text> in **HTML**?\n"
        let backend = FakeBackend(output: "\n<text>\nIt's a **tag**.\n</text>\n\n")
        let result = try await TaskRunner(backend: backend).perform(.send, text: raw)
        #expect(backend.calls.first?.system == "")
        #expect(backend.calls.first?.user == raw)
        #expect(result == .text("<text>\nIt's a **tag**.\n</text>"))
    }
}
