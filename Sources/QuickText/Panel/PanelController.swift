import AppKit
import SwiftUI

final class QuickTextPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Esc when the focus is not in the text view.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 560, height: 580)
    static let minSize = NSSize(width: 420, height: 340)

    private enum Key {
        static let width = "panel.width"
        static let height = "panel.height"
        static let relX = "panel.relativeCenterX"
        static let relY = "panel.relativeCenterY"
    }

    let panel: QuickTextPanel
    let model: ChatModel
    private let defaults = UserDefaults.standard
    private var isPositioning = false
    private var keyMonitor: Any?

    init(model: ChatModel) {
        self.model = model
        panel = QuickTextPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.title = "QuickText"
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // We hide on resign-key ourselves; the system flag would bring the window back on reactivation.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = Self.minSize
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }

        let hostingView = NSHostingView(rootView: ChatView(model: model))
        panel.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        let clear = NSHostingView(rootView: ClearButton(model: model))
        clear.frame = NSRect(x: 0, y: 0, width: clear.fittingSize.width, height: 28)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = clear
        accessory.layoutAttribute = .trailing
        panel.addTitlebarAccessoryViewController(accessory)

        model.inputBridge.hide = { [weak self] in self?.hide() }
        installKeyMonitor()
    }

    var isActive: Bool {
        panel.isVisible && panel.isKeyWindow && NSApp.isActive
    }

    func toggle() {
        isActive ? hide() : show()
    }

    func show() {
        if !panel.isVisible {
            positionOnMouseScreen()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.inputBridge.focusAndSelectAll()
        // On first show SwiftUI may create the text view a little later.
        DispatchQueue.main.async { [weak self] in
            self?.model.inputBridge.focusAndSelectAll()
        }
    }

    /// Hiding the app hands focus back to the previous app.
    func hide() {
        NSApp.hide(nil)
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        panel.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveFrame()
    }

    // MARK: Position memory

    private func saveFrame() {
        guard !isPositioning, panel.isVisible, let screen = panel.screen else { return }
        let frame = panel.frame
        let visible = screen.visibleFrame
        defaults.set(Double(frame.width), forKey: Key.width)
        defaults.set(Double(frame.height), forKey: Key.height)
        defaults.set(Double((frame.midX - visible.minX) / visible.width), forKey: Key.relX)
        defaults.set(Double((frame.midY - visible.minY) / visible.height), forKey: Key.relY)
    }

    private func positionOnMouseScreen() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame

        func stored(_ key: String) -> CGFloat? {
            (defaults.object(forKey: key) as? Double).map { CGFloat($0) }
        }

        var size = NSSize(
            width: stored(Key.width) ?? Self.defaultSize.width,
            height: stored(Key.height) ?? Self.defaultSize.height
        )
        size.width = min(max(size.width, Self.minSize.width), visible.width)
        size.height = min(max(size.height, Self.minSize.height), visible.height)

        var center = NSPoint(x: visible.midX, y: visible.midY)
        if let relX = stored(Key.relX), let relY = stored(Key.relY) {
            center = NSPoint(x: visible.minX + relX * visible.width, y: visible.minY + relY * visible.height)
        }

        var origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)

        isPositioning = true
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        isPositioning = false
    }

    // MARK: In-window shortcuts

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard flags == .command else { return event }
            let windowNumber = event.windowNumber
            let keyCode = event.keyCode
            let handled = MainActor.assumeIsolated {
                guard let self, windowNumber == self.panel.windowNumber else { return false }
                return self.handleCommandKey(keyCode)
            }
            return handled ? nil : event
        }
    }

    /// Physical key codes, independent of the keyboard layout. Swallowed even when the input is empty.
    private func handleCommandKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 18, 83: model.run(.check)
        case 19, 84: model.run(.refine)
        case 20, 85: model.run(.translate)
        case 21, 86: model.run(.send)
        case 36, 76: model.repeatLast()
        default: return false
        }
        return true
    }
}
