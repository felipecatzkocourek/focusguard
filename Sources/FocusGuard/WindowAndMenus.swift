import AppKit
import Observation
import SwiftUI

/// Owns the dashboard window. The frame (including which monitor it's on) is saved
/// automatically, so once you drag it to your second screen it reopens there.
@MainActor
final class DashboardWindowController {
    private let window: NSWindow

    init(model: AppModel) {
        let hosting = NSHostingController(rootView: DashboardView().environment(model))
        hosting.sizingOptions = []

        window = NSWindow(contentViewController: hosting)
        window.title = "FocusGuard"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 460, height: 560)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setContentSize(NSSize(width: 520, height: 720))
        if !window.setFrameUsingName("FocusGuardDashboard") { window.center() }
        window.setFrameAutosaveName("FocusGuardDashboard")
    }

    /// `activate: false` brings the window forward without stealing keyboard focus from
    /// whatever you're doing (used when Work starts automatically).
    func show(activate: Bool) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        if activate {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
    }
}

/// Menu bar shield: shows at a glance whether blocking is on, and reopens the dashboard.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private let openDashboard: () -> Void
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    init(model: AppModel, openDashboard: @escaping () -> Void) {
        self.model = model
        self.openDashboard = openDashboard
        super.init()

        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Dashboard", action: #selector(openDashboardAction), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit FocusGuard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        observe()
    }

    private func observe() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func render() {
        let active = model.isWorkActive
        let image = NSImage(
            systemSymbolName: active ? "shield.lefthalf.filled" : "shield",
            accessibilityDescription: active ? "FocusGuard: blocking" : "FocusGuard: off"
        )
        image?.isTemplate = true
        item.button?.image = image
        statusLine.title = active ? "Work · blocking \(model.configuration.blockedDomains.count) sites" : "Off · nothing blocked"
    }

    @objc private func openDashboardAction() { openDashboard() }
}

enum MainMenu {
    /// Minimal main menu so standard shortcuts (⌘Q, ⌘W, copy/paste in text fields) work.
    @MainActor
    static func make() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About FocusGuard", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide FocusGuard", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit FocusGuard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        return main
    }
}
