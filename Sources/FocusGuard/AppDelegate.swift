import AppKit

/// App entry point. FocusGuard uses an AppKit lifecycle (with SwiftUI views inside) so it
/// has full control over the dashboard window — where it opens, that closing it only
/// hides it, and that it can come forward on its own when a blocking session starts.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    private let model = AppModel()
    private var dashboard: DashboardWindowController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()

        let dashboard = DashboardWindowController(model: model)
        self.dashboard = dashboard
        statusItem = StatusItemController(model: model) { [weak self] in self?.dashboard?.show(activate: true) }
        model.onSessionStarted = { [weak self] in self?.dashboard?.show(activate: false) }
        model.onFirefoxNeedsRestart = { [weak self] prompt in self?.askToRestartFirefox(prompt) }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil
        )

        dashboard.show(activate: true)
        Task { await model.start() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dashboard?.show(activate: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.prepareForTermination()
    }

    /// Firefox can't close individual tabs on request, so offer to restart it: tabs on
    /// blocked sites then reload and hit the block.
    private func askToRestartFirefox(_ prompt: AppModel.FirefoxRestartPrompt) {
        let sites = ListFormatter.localizedString(byJoining: prompt.hostnames.sorted())
        let alert = NSAlert()
        alert.messageText = "Restart Firefox to block \(sites)?"
        alert.informativeText = prompt.restoresTabs
            ? "Firefox still has \(sites) open, and open tabs keep working until Firefox reconnects. Firefox will reopen your windows and tabs after restarting."
            : "Firefox still has \(sites) open, and open tabs keep working until Firefox reconnects.\n\nFirefox isn't set to reopen previous windows and tabs, so restarting will close all of them. (Firefox Settings → General → Startup → Open previous windows and tabs.)"
        alert.addButton(withTitle: "Restart Firefox")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = prompt.restoresTabs ? .informational : .warning

        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await model.restartFirefox() }
        } else {
            model.dismissFirefoxRestart()
        }
    }

    @objc private func systemDidWake() {
        Task { await model.tick() }
    }
}
