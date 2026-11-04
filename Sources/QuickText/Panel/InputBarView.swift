import AppKit
import SwiftUI

/// Lets the window controller and the model reach the AppKit text view.
@MainActor
final class InputBridge {
    weak var textView: NSTextView?
    var hide: () -> Void = {}

    func focusAndSelectAll() {
        guard let textView, let window = textView.window else { return }
        window.makeFirstResponder(textView)
        textView.selectAll(nil)
    }
}

struct InputBarView: View {
    @ObservedObject var model: ChatModel
    @StateObject private var height = LocalState<CGFloat>(40)

    var body: some View {
        VStack(spacing: 10) {
            InputTextView(
                text: $model.input,
                height: $height.value,
                bridge: model.inputBridge,
                onSubmit: { model.run(.check) }
            )
            .frame(height: min(max(height.value, 40), 180))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.15)))

            HStack(spacing: 8) {
                Button { model.run(.check) } label: { label("Check", "⏎") }
                    .buttonStyle(.borderedProminent)
                    .help("Check (⏎ or ⌘1)")
                    .disabled(!model.canRun)
                    .fixedSize()

                HStack(spacing: 2) {
                    Button { model.run(.refine) } label: { label("Refine", "⌘2") }
                        .help("Refine (⌘2)")
                        .disabled(!model.canRun)
                    Picker("Refine style", selection: $model.refineStyle) {
                        ForEach(RefineStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .help("Refine style")
                }
                .fixedSize()

                Button { model.run(.translate) } label: { label("Translate", "⌘3") }
                    .help("Translate (⌘3)")
                    .disabled(!model.canRun)
                    .fixedSize()

                Button { model.run(.send) } label: { label("Send", "⌘4") }
                    .help("Send the text to the model as is, with no prompt (⌘4)")
                    .disabled(!model.canRun)
                    .fixedSize()

                ViewThatFits(in: .horizontal) {
                    hint("⇧⏎ New line · ⌘⏎ Repeat last")
                    hint("⇧⏎ New line")
                    Color.clear.frame(width: 0, height: 0)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(12)
    }

    private func label(_ title: String, _ shortcut: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Text(shortcut).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Plain-text, auto-growing NSTextView. ⏎ runs Check, ⇧⏎ / ⌥⏎ insert a newline.
struct InputTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let bridge: InputBridge
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .textColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.textContainer?.lineFragmentPadding = 5
        // What is sent to the model must be exactly what the user typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.frameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView
        )

        bridge.textView = textView
        context.coordinator.textView = textView
        context.coordinator.recalculateHeight()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        bridge.textView = context.coordinator.textView
        guard let textView = context.coordinator.textView else { return }
        // Never overwrite the text while an input method is composing.
        if textView.string != text && !textView.hasMarkedText() {
            textView.string = text
            context.coordinator.recalculateHeight()
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InputTextView
        weak var textView: NSTextView?

        init(_ parent: InputTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            recalculateHeight()
        }

        @objc func frameDidChange(_ notification: Notification) {
            recalculateHeight()
        }

        func recalculateHeight() {
            guard let textView, let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container).height
            let newHeight = ceil(used + textView.textContainerInset.height * 2)
            guard abs(newHeight - parent.height) > 0.5 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.height = newHeight
            }
        }

        // Not called while an input method is composing, so ⏎ / Esc go to the IME then.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) || flags.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSubmit()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.bridge.hide()
                return true
            default:
                return false
            }
        }
    }
}
