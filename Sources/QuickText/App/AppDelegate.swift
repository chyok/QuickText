import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var menuBarController: MenuBarController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Writing to the stdin of a command-line tool that already exited must not crash the app.
        signal(SIGPIPE, SIG_IGN)
        // No Dock icon, even under `swift run`.
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = makeMainMenu()

        let backend = ProviderBackend { Settings.configuration() }
        let model = ChatModel(runner: TaskRunner(backend: backend), settings: .shared)
        let panelController = PanelController(model: model)
        self.panelController = panelController
        menuBarController = MenuBarController(
            openWindow: { panelController.show() },
            openSettings: { [weak self] in self?.openSettings(nil) }
        )
        // A Carbon hotkey: works without the Accessibility permission.
        KeyboardShortcuts.onKeyDown(for: .togglePanel) {
            panelController.toggle()
        }

        if Settings.shared.consumeFirstLaunch() {
            panelController.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProcessRun.terminateAll()
    }

    @objc func openSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(settings: Settings.shared))
            controller.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: controller)
            window.title = "QuickText Settings"
            window.styleMask = [.titled, .closable]
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// The app shows no menu bar (LSUIElement), but the main menu still dispatches
    /// ⌘C / ⌘V / ⌘Z / ⌘W / ⌘Q / ⌘, — without it the text view gets no edit shortcuts.
    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: "QuickText")
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit QuickText", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        return mainMenu
    }
}
