import AppKit
import FocusGuardCore

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
    /// Set when macOS announces a shutdown, restart or logout, so the quit that follows
    /// never prompts.
    private var systemIsEndingSession = false

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
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWillPowerOff), name: NSWorkspace.willPowerOffNotification, object: nil
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

    /// Quitting ends the running Cycle. A quit during an Active before its planned length is
    /// held until the user gives a reason (or cancels); a shutdown or logout never asks.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if systemIsEndingSession || Self.quitIsFromSystem {
            model.endCycleBySystem()
            return .terminateNow
        }
        guard let cycle = model.cycle, !cycle.canStop(at: Date()) else {
            return model.quitCycle() ? .terminateNow : .terminateCancel
        }
        guard let reason = askReasonToQuit(during: cycle) else { return .terminateCancel }
        return model.quitCycle(reason: reason) ? .terminateNow : .terminateCancel
    }

    /// Whether the quit Apple event comes from a shutdown, restart or logout.
    private static var quitIsFromSystem: Bool {
        let systemReasons: Set<OSType> = [
            kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAEShowShutdownDialog, kAERestart, kAEShutDown,
        ]
        guard let reason = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: kAEQuitReason)?.enumCodeValue else { return false }
        return systemReasons.contains(reason)
    }

    /// The same Friction as cutting the Active short from the Pomodoro tab: the minutes left
    /// and a typed reason. Returns `nil` if the user cancels.
    private func askReasonToQuit(during cycle: PomodoroCycle) -> String? {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Why are you stopping early?"

        let alert = NSAlert()
        alert.messageText = "Quit during Active \(cycle.activeNumber) of \(cycle.plan.actives)?"
        alert.informativeText = "\(formatMinutes(cycle.remaining(at: Date()) ?? 0)) left. Quitting now cuts this Active short and ends the Cycle."
        alert.accessoryView = field
        let quit = alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        quit.isEnabled = false
        let observer = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification, object: field, queue: .main
        ) { _ in
            MainActor.assumeIsolated { quit.isEnabled = PomodoroCycle.validReason(field.stringValue) != nil }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        NSApp.activate()
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return PomodoroCycle.validReason(field.stringValue)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.prepareForTermination()
    }

    /// Firefox can't close individual tabs on request, so offer to restart it: tabs on
    /// blocked sites then reload and hit the block.
    private func askToRestartFirefox(_ prompt: AppModel.FirefoxRestartPrompt) {
        let sites = ListFormatter.localizedString(byJoining: prompt.hostnames.sorted())
        let situation = prompt.hostnames.isEmpty
            ? "Tabs that were already open on a blocked site keep working until Firefox reconnects. Restarting makes sure they're blocked too."
            : "Firefox still has \(sites) open, and open tabs keep working until Firefox reconnects."
        let alert = NSAlert()
        alert.messageText = prompt.hostnames.isEmpty ? "Restart Firefox to apply the block?" : "Restart Firefox to block \(sites)?"
        alert.informativeText = prompt.restoresTabs
            ? situation + " Firefox will reopen your windows and tabs after restarting."
            : situation + "\n\nFirefox isn't set to reopen previous windows and tabs, so restarting will close all of them. (Firefox Settings → General → Startup → Open previous windows and tabs.)"
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

    @objc private func systemWillPowerOff() {
        systemIsEndingSession = true
    }

    @objc private func systemDidWake() {
        Task { await model.tick() }
    }
}
