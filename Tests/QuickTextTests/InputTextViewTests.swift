import AppKit
import Testing
@testable import QuickText

@MainActor
@Suite struct InputTextViewTests {
    /// A text view in a window, so it has an undo manager; each edit is its own undo group, as with real key presses.
    private func makeTextView() -> (NSTextView, UndoManager) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let textView = NSTextView(frame: window.contentView!.bounds)
        textView.isRichText = false
        textView.allowsUndo = true
        window.contentView!.addSubview(textView)
        window.makeFirstResponder(textView)
        let undoManager = window.undoManager!
        undoManager.groupsByEvent = false
        return (textView, undoManager)
    }

    private func edit(_ undoManager: UndoManager, _ body: () -> Void) {
        undoManager.beginUndoGrouping()
        body()
        undoManager.endUndoGrouping()
    }

    @Test func undoAfterClearingRestoresTheSubmittedText() {
        let (textView, undoManager) = makeTextView()
        edit(undoManager) { textView.insertText("waht are you doing", replacementRange: NSRange(location: NSNotFound, length: 0)) }
        edit(undoManager) { InputTextView.replaceText(of: textView, with: "") }
        #expect(textView.string == "")

        // Assigning `string` directly made this undo crash with NSRangeException.
        undoManager.undo()
        #expect(textView.string == "waht are you doing")
        undoManager.undo()
        #expect(textView.string == "")
        undoManager.redo()
        undoManager.redo()
        #expect(textView.string == "")
    }
}
