import Foundation
import Testing
@testable import QuickText

@MainActor
@Suite struct ChatModelTests {
    @Test func runClearsInputAndCardKeepsTheSource() async {
        let model = ChatModel(runner: TaskRunner(backend: FakeBackend(output: "Hello there.")), settings: nil)
        model.input = "hello  there\n"
        model.run(.refine)
        #expect(model.input == "")
        #expect(model.cards.count == 1)
        #expect(model.cards[0].source == "hello  there\n")
        #expect(model.cards[0].status == .loading)
        await model.currentTask?.value
        #expect(model.cards[0].status == .done(.text("Hello there.")))
        #expect(model.cards[0].finishedAt != nil)
    }

    @Test func blankInputDoesNothing() {
        let backend = FakeBackend(output: "x")
        let model = ChatModel(runner: TaskRunner(backend: backend), settings: nil)
        model.input = "  \n\t "
        #expect(!model.canRun)
        model.run(.check)
        model.repeatLast()
        #expect(model.cards.isEmpty)
        #expect(model.input == "  \n\t ")
        #expect(backend.calls.isEmpty)
    }

    @Test func newRequestCancelsThePreviousOne() async {
        let model = ChatModel(runner: TaskRunner(backend: FakeBackend(output: "done", delay: .milliseconds(300))),
                              settings: nil)
        model.input = "first"
        model.run(.refine)
        let first = model.currentTask
        model.input = "second"
        model.run(.refine)
        #expect(model.cards[0].status == .cancelled)
        await first?.value
        #expect(model.cards[0].status == .cancelled)
        await model.currentTask?.value
        #expect(model.cards[1].status == .done(.text("done")))

        model.input = "third"
        model.run(.refine)
        model.clear()
        #expect(model.cards.isEmpty)
    }

    @Test func sendUsesTheRawText() async {
        let backend = FakeBackend(output: "Paris")
        let model = ChatModel(runner: TaskRunner(backend: backend), settings: nil)
        model.input = " What is the capital of France?\n"
        model.run(.send)
        await model.currentTask?.value
        #expect(backend.calls.first?.system == "")
        #expect(backend.calls.first?.user == " What is the capital of France?\n")
        #expect(model.cards[0].action == .send)
        #expect(model.cards[0].status == .done(.text("Paris")))
    }

    @Test func repeatLastReusesTheLastActionKind() async {
        let model = ChatModel(runner: TaskRunner(backend: FakeBackend(output: "✓ No errors found\n---\nok")),
                              settings: nil)
        model.input = "ok"
        model.repeatLast()
        #expect(model.cards.last?.action == .check)
        await model.currentTask?.value

        model.refineStyle = .casual
        model.input = "你好"
        model.run(.translate)
        await model.currentTask?.value
        model.input = "hello"
        model.repeatLast()
        #expect(model.cards.last?.action == .translate(.toChinese))
        await model.currentTask?.value

        model.run(.refine)  // empty input: ignored
        model.input = "x"
        model.run(.refine)
        #expect(model.cards.last?.action == .refine(.casual))
        await model.currentTask?.value
    }
}
