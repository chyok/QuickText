import AppKit
import KeyboardShortcuts

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let openWindow: () -> Void
    private let openSettings: () -> Void
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    init(openWindow: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.openWindow = openWindow
        self.openSettings = openSettings
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "QuickText")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "QuickText"
        }

        let menu = NSMenu()
        menu.delegate = self

        let open = NSMenuItem(title: "Open Window", action: #selector(openWindowAction), keyEquivalent: "")
        open.target = self
        open.setShortcut(for: .togglePanel)
        menu.addItem(open)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit QuickText", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem.state = LoginItem.isEnabled ? .on : .off
    }

    @objc private func openWindowAction() { openWindow() }

    @objc private func openSettingsAction() { openSettings() }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMove QuickText.app to the Applications folder and try again."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        launchAtLoginItem.state = LoginItem.isEnabled ? .on : .off
    }
}
