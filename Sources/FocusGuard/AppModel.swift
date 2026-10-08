import FocusGuardCore
import Foundation
import Observation
import ServiceManagement

/// Single source of truth for the app. Views observe it; the app delegate feeds it
/// commands from the URL scheme; it keeps `/etc/hosts` in sync through the helper.
@MainActor @Observable
final class AppModel {
    enum HelperStatus: Equatable {
        case checking, notInstalled, installed
    }

    private(set) var configuration: Configuration
    private(set) var state: BlockState
    private(set) var log: ActivityLog
    private(set) var helperStatus: HelperStatus = .checking
    private(set) var lastError: String?
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    /// Called when Work turns on, so the app can bring the dashboard up.
    @ObservationIgnored var onWorkStarted: (() -> Void)?

    @ObservationIgnored private let helper = HelperClient()
    @ObservationIgnored private let configStore: JSONStore<Configuration>
    @ObservationIgnored private let stateStore: JSONStore<BlockState>
    @ObservationIgnored private let logStore: JSONStore<ActivityLog>
    @ObservationIgnored private var appliedHostnames: [String]?
    @ObservationIgnored private var expiryTimer: Timer?

    init(directory: URL = JSONStore<Configuration>.applicationSupportDirectory) {
        configStore = JSONStore(url: directory.appending(path: "config.json")) { Configuration() }
        stateStore = JSONStore(url: directory.appending(path: "state.json")) { BlockState() }
        logStore = JSONStore(url: directory.appending(path: "activity.json")) { ActivityLog() }
        configuration = configStore.load()
        state = stateStore.load()
        log = logStore.load()
    }

    var isWorkActive: Bool { state.isWorkActive }

    /// While Work is on, anything that would weaken the block (removing sites, lowering
    /// friction) is locked. Adding sites is always allowed.
    var isLocked: Bool { state.isWorkActive }

    // MARK: - Lifecycle

    func start() async {
        await refreshHelperStatus()
        await reconcile()
    }

    /// Called on quit: drop temporary allowances so quitting can't be used to keep a
    /// site unblocked past its time.
    func prepareForTermination() {
        expiryTimer?.invalidate()
        guard state.isWorkActive, !state.allowances.isEmpty else { return }
        state.allowances.removeAll()
        save()
        try? helper.blockSynchronously(
            BlockPlanner.hostnamesToBlock(configuration: configuration, state: state, at: Date())
        )
    }

    // MARK: - Commands

    func handle(_ command: FocusCommand) async {
        let now = Date()
        switch command {
        case .workOn:
            if !state.isWorkActive {
                state.isWorkActive = true
                log.record(.workStarted, at: now)
            }
            onWorkStarted?()
        case .workOff:
            guard state.isWorkActive else { break }
            state.isWorkActive = false
            state.allowances.removeAll()
            log.record(.workEnded, at: now)
        }
        save()
        await reconcile()
    }

    func grantAllowance(domain: String, reason: String, minutes: Int) async {
        guard state.isWorkActive, configuration.blockedDomains.contains(domain) else { return }
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
        await reconcile()
        return domain
    }

    func removeDomain(_ domain: String) async {
        guard !isLocked else { return }
        configuration.removeDomain(domain)
        save()
        await reconcile()
    }

    func updateFriction(_ update: (inout Configuration.Friction) -> Void) {
        guard !isLocked else { return }
        update(&configuration.friction)
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
        await refreshHelperStatus()
        appliedHostnames = nil
        await reconcile()
    }

    func refreshHelperStatus() async {
        helperStatus = await helper.isAuthorized() ? .installed : .notInstalled
    }

    // MARK: - Sync with /etc/hosts

    /// Expires old allowances, then makes `/etc/hosts` match the current plan.
    func reconcile() async {
        let now = Date()
        let expired = state.pruneExpiredAllowances(at: now)
        for allowance in expired {
            log.record(.allowanceExpired(domain: allowance.domain), at: now)
        }
        if !expired.isEmpty { save() }

        let hostnames = BlockPlanner.hostnamesToBlock(configuration: configuration, state: state, at: now)
        if hostnames != appliedHostnames {
            do {
                try await helper.block(hostnames)
                appliedHostnames = hostnames
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                if case HelperClient.Failure.notInstalled = error { helperStatus = .notInstalled }
            }
        }
        scheduleNextExpiry(after: now)
    }

    private func scheduleNextExpiry(after now: Date) {
        expiryTimer?.invalidate()
        guard let next = BlockPlanner.nextChange(state: state, at: now) else { return }
        expiryTimer = Timer.scheduledTimer(withTimeInterval: max(next.timeIntervalSince(now), 0.5), repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.reconcile() }
        }
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
