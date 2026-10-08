import Foundation

/// A friction-gated, time-limited exception for one blocked domain
/// ("I need YouTube for 15 minutes to watch a tutorial").
public struct Allowance: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var domain: String
    public var reason: String
    public var start: Date
    public var expires: Date

    public init(id: UUID = UUID(), domain: String, reason: String, start: Date, minutes: Int) {
        self.id = id
        self.domain = domain
        self.reason = reason
        self.start = start
        self.expires = start.addingTimeInterval(TimeInterval(minutes * 60))
    }

    public func isActive(at now: Date) -> Bool { now < expires }
}

/// The runtime state that survives app restarts.
public struct BlockState: Codable, Equatable, Sendable {
    /// Whether the Work Focus is on (as last reported by the Shortcuts automation).
    public var isWorkActive: Bool
    public var allowances: [Allowance]

    public init(isWorkActive: Bool = false, allowances: [Allowance] = []) {
        self.isWorkActive = isWorkActive
        self.allowances = allowances
    }

    /// Allowances that haven't expired yet.
    public func activeAllowances(at now: Date) -> [Allowance] {
        allowances.filter { $0.isActive(at: now) }
    }

    /// The allowance currently covering `domain`, if any.
    public func allowance(for domain: String, at now: Date) -> Allowance? {
        activeAllowances(at: now).first { $0.domain == domain }
    }

    /// Drops expired allowances and returns the ones that were removed.
    public mutating func pruneExpiredAllowances(at now: Date) -> [Allowance] {
        let expired = allowances.filter { !$0.isActive(at: now) }
        allowances.removeAll { !$0.isActive(at: now) }
        return expired
    }
}

/// Decides which hostnames must be in `/etc/hosts` right now.
public enum BlockPlanner {
    public static func hostnamesToBlock(configuration: Configuration, state: BlockState, at now: Date) -> [String] {
        guard state.isWorkActive else { return [] }
        let allowed = Set(state.activeAllowances(at: now).map(\.domain))
        return configuration.blockedDomains
            .filter { !allowed.contains($0) }
            .flatMap(Domain.hostnames(for:))
            .sorted()
    }

    /// When the plan will next change on its own (the earliest allowance expiry), so the
    /// app can schedule a single timer instead of polling.
    public static func nextChange(state: BlockState, at now: Date) -> Date? {
        guard state.isWorkActive else { return nil }
        return state.activeAllowances(at: now).map(\.expires).min()
    }
}
