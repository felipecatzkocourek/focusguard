import FocusGuardCore
import Foundation
import Observation
import ServiceManagement

/// Single source of truth for the app. It watches the system Focus, decides when a
/// blocking session starts and ends, and keeps `/etc/hosts` in sync through the helper.
@MainActor @Observable
final class AppModel {
    enum HelperStatus: Equatable {
        case checking, notInstalled, outdated, installed
    }

    private(set) var configuration: Configuration
    private(set) var state: BlockState
    private(set) var log: ActivityLog
    private(set) var focus: FocusSnapshot = .unknown
    private(set) var helperStatus: HelperStatus = .checking
    private(set) var lastError: String?
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    /// Called when a blocking session starts, so the app can bring the dashboard up.
    @ObservationIgnored var onSessionStarted: (() -> Void)?

    /// How often the Focus database and `/etc/hosts` are checked. Cheap: two small
    /// JSON files and the hosts file.
    static let pollInterval: TimeInterval = 2
    /// After a failed helper call, wait this long before retrying the same change.
    static let retryInterval: TimeInterval = 30

    @ObservationIgnored private let helper = HelperClient()
    @ObservationIgnored private let configStore: JSONStore<Configuration>
    @ObservationIgnored private let stateStore: JSONStore<BlockState>
    @ObservationIgnored private let logStore: JSONStore<ActivityLog>
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var isApplying = false
    @ObservationIgnored private var lastFailure: (hostnames: [String], date: Date)?

    init(directory: URL = JSONStore<Configuration>.applicationSupportDirectory) {
        configStore = JSONStore(url: directory.appending(path: "config.json")) { Configuration() }
        stateStore = JSONStore(url: directory.appending(path: "state.json")) { BlockState() }
        logStore = JSONStore(url: directory.appending(path: "activity.json")) { ActivityLog() }
        configuration = configStore.load()
        state = stateStore.load()
        log = logStore.load()
    }

    var isBlocking: Bool { state.isBlocking }

    /// While blocking, anything that would weaken the block (removing sites or trigger
    /// modes, lowering friction) is locked. Adding sites is always allowed.
    var isLocked: Bool { state.isBlocking }

    /// The Focus that started the current session, for display.
    var sessionFocusName: String? {
        guard state.isBlocking else { return nil }
        return focus.activeMode?.name
    }

    var triggerModeNames: [String] {
        focus.modes.filter { configuration.triggerFocusIdentifiers.contains($0.id) }.map(\.name)
    }

    // MARK: - Lifecycle

    func start() async {
        await refreshHelperStatus()
        await tick()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    /// Called on quit: drop temporary allowances so quitting can't be used to keep a
    /// site unblocked past its time. Blocking itself stays in place.
    func prepareForTermination() {
        pollTimer?.invalidate()
        guard state.isBlocking, !state.allowances.isEmpty else { return }
        state.allowances.removeAll()
        save()
        try? helper.blockSynchronously(
            BlockPlanner.hostnamesToBlock(configuration: configuration, state: state, at: Date())
        )
    }

    /// One polling step: read the Focus, update the session, then make `/etc/hosts` match.
    func tick() async {
        let snapshot = await Task.detached { FocusMonitor.read() }.value
        if snapshot != focus { focus = snapshot }
        updateSession()
        await reconcile()
    }

    // MARK: - Session

    /// Starts or ends the blocking session based on the active Focus.
    ///
    /// If the Focus database can't be read, the current state is kept as is. Failing
    /// closed means a broken read can never silently unblock sites.
    private func updateSession() {
        guard focus.access == .ok else { return }
        let shouldBlock = configuration.shouldBlock(activeFocusIdentifier: focus.activeModeIdentifier)
        guard shouldBlock != state.isBlocking else { return }

        let now = Date()
        state.isBlocking = shouldBlock
        Log.session.notice("Session \(shouldBlock ? "started" : "ended", privacy: .public) (Focus: \(self.focus.activeModeIdentifier ?? "none", privacy: .public))")
        if shouldBlock {
            log.record(.sessionStarted(focus: focus.activeMode?.name ?? "Focus"), at: now)
            onSessionStarted?()
        } else {
            state.allowances.removeAll()
            log.record(.sessionEnded, at: now)
        }
        save()
    }

    // MARK: - User actions

    func grantAllowance(domain: String, reason: String, minutes: Int) async {
        guard state.isBlocking, configuration.blockedDomains.contains(domain) else { return }
        let now = Date()
        state.allowances.removeAll { $0.domain == domain }
        state.allowances.append(Allowance(domain: domain, reason: reason, start: now, minutes: minutes))
        log.record(.allowanceGranted(domain: domain, reason: reason, minutes: minutes), at: now)
        save()
        await reconcile()
    }

    /// Returns the normalized domain, or `nil` if the input wasn't a valid site.
    func addDomain(_ input: String) async -> String? {
        guard let domain = configuration.addDomain(input) else { return nil }
        save()
        await syncFirefoxExclusions()
        await reconcile()
        return domain
    }

    func removeDomain(_ domain: String) async {
        guard !isLocked else { return }
        configuration.removeDomain(domain)
        save()
        await syncFirefoxExclusions()
        await reconcile()
    }

    func setTrigger(_ mode: FocusMode, enabled: Bool) async {
        guard !isLocked else { return }
        if enabled {
            configuration.triggerFocusIdentifiers.insert(mode.id)
        } else {
            configuration.triggerFocusIdentifiers.remove(mode.id)
        }
        save()
        await tick()
    }

    func updateFriction(_ update: (inout Configuration.Friction) -> Void) {
        guard !isLocked else { return }
        update(&configuration.friction)
        save()
    }

    func setRestartsFirefoxAutomatically(_ enabled: Bool) {
        guard !isLocked else { return }
        configuration.restartsFirefoxAutomatically = enabled
        save()
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            lastError = nil
        } catch {
            lastError = "Couldn't change the login item: \(error.localizedDescription)"
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func installHelper() async {
        do {
            try await helper.install()
            lastError = nil
        } catch HelperClient.Failure.installCancelled {
            // The user closed the password prompt; nothing to report.
        } catch {
            lastError = error.localizedDescription
        }
        lastFailure = nil
        await refreshHelperStatus()
        await reconcile()
    }

    func refreshHelperStatus() async {
        guard await helper.isAuthorized() else {
            helperStatus = .notInstalled
            return
        }
        helperStatus = await helper.apiLevel() >= HelperClient.requiredAPILevel ? .installed : .outdated
        await syncFirefoxExclusions()
    }

    // MARK: - Sync with /etc/hosts

    /// Expires old allowances, then makes `/etc/hosts` match the plan.
    ///
    /// It compares against the file itself rather than a cached value, so if someone
    /// edits FocusGuard's section by hand during a session it is restored within one
    /// poll interval.
    func reconcile() async {
        let now = Date()
        let expired = state.pruneExpiredAllowances(at: now)
        for allowance in expired {
            log.record(.allowanceExpired(domain: allowance.domain), at: now)
        }
        if !expired.isEmpty { save() }

        let planned = BlockPlanner.hostnamesToBlock(configuration: configuration, state: state, at: now)
        let current = (try? String(contentsOfFile: HostsFile.path, encoding: .utf8)).map(HostsFile.blockedHostnames(in:))
        guard current != planned, !isApplying else { return }
        if let lastFailure, lastFailure.hostnames == planned, now.timeIntervalSince(lastFailure.date) < Self.retryInterval {
            return
        }

        isApplying = true
        defer { isApplying = false }
        do {
            try await helper.block(planned)
            Log.hosts.notice("Applied \(planned.count) blocked hostnames (was \(current?.count ?? -1))")
            lastFailure = nil
            lastError = nil
            await clearOpenTabs(of: Set(planned).subtracting(current ?? []))
        } catch {
            lastFailure = (planned, now)
            lastError = error.localizedDescription
            Log.hosts.error("Applying hosts failed: \(error.localizedDescription, privacy: .public)")
            if case HelperClient.Failure.notInstalled = error { helperStatus = .notInstalled }
        }
    }

    // MARK: - Browsers

    /// Hostnames blocked just now that are still open in Firefox, waiting for the user to
    /// decide whether to restart it. `nil` when there's nothing to ask about.
    private(set) var firefoxRestartPrompt: FirefoxRestartPrompt?
    private(set) var firefoxPolicyInstalled = BrowserTabs.isFirefoxPolicyInstalled

    struct FirefoxRestartPrompt: Equatable {
        /// Blocked hostnames seen in Firefox's tabs; empty when they couldn't be checked.
        var hostnames: Set<String>
        var restoresTabs: Bool
    }

    /// Called when Firefox has tabs on sites that were just blocked.
    @ObservationIgnored var onFirefoxNeedsRestart: ((FirefoxRestartPrompt) -> Void)?

    /// Newly blocked sites may already be open; DNS blocking alone won't stop those tabs.
    private func clearOpenTabs(of newlyBlocked: Set<String>) async {
        guard !newlyBlocked.isEmpty else { return }
        await BrowserTabs.closeTabs(showing: newlyBlocked)

        let check = await Task.detached { BrowserTabs.firefoxTabs(showing: newlyBlocked) }.value
        let hostnames: Set<String>
        switch check {
        case .clear: return
        case .open(let open): hostnames = open
        case .unknown: hostnames = []
        }
        Log.browsers.notice("Asking to restart Firefox (open blocked: \(hostnames.sorted(), privacy: .public))")
        let restoresTabs = BrowserTabs.firefoxRestoresSession
        if configuration.restartsFirefoxAutomatically && restoresTabs {
            Log.browsers.notice("Restarting Firefox automatically")
            await restartFirefox()
            return
        }
        let prompt = FirefoxRestartPrompt(hostnames: hostnames, restoresTabs: restoresTabs)
        firefoxRestartPrompt = prompt
        onFirefoxNeedsRestart?(prompt)
    }

    func restartFirefox() async {
        firefoxRestartPrompt = nil
        await BrowserTabs.restartFirefox()
    }

    func dismissFirefoxRestart() {
        firefoxRestartPrompt = nil
    }

    /// Keeps Firefox's DNS-over-HTTPS exclusions equal to the blocked sites, so Firefox
    /// resolves them through macOS (which honors the block) even with DNS over HTTPS on.
    /// Done all the time, not only during sessions: Firefox reads policies at startup.
    func syncFirefoxExclusions() async {
        guard BrowserTabs.isFirefoxInstalled, helperStatus == .installed else { return }
        let wanted = configuration.blockedDomains.sorted()
        guard BrowserTabs.firefoxExcludedDomains != wanted else { return }
        do {
            try await helper.setFirefoxExclusions(wanted)
            Log.browsers.notice("Firefox DNS-over-HTTPS exclusions set to \(wanted, privacy: .public)")
        } catch {
            Log.browsers.error("Setting Firefox exclusions failed: \(error.localizedDescription, privacy: .public)")
            lastError = "Couldn't update Firefox's exceptions: \(error.localizedDescription)"
        }
    }

    func installFirefoxPolicy() async {
        do {
            try await helper.installFirefoxPolicy()
            lastError = nil
        } catch HelperClient.Failure.installCancelled {
            // The user closed the password prompt.
        } catch {
            lastError = error.localizedDescription
        }
        firefoxPolicyInstalled = BrowserTabs.isFirefoxPolicyInstalled
    }

    func refreshFirefoxPolicyStatus() {
        firefoxPolicyInstalled = BrowserTabs.isFirefoxPolicyInstalled
    }

    private func save() {
        do {
            try configStore.save(configuration)
            try stateStore.save(state)
            try logStore.save(log)
        } catch {
            lastError = "Couldn't save settings: \(error.localizedDescription)"
        }
    }
}
