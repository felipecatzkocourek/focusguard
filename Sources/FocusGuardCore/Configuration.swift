import Foundation

/// User-editable settings, persisted as JSON.
public struct Configuration: Codable, Equatable, Sendable {
    /// Domains blocked while Work is active, already normalized (see ``Domain``).
    public var blockedDomains: [String]
    /// Settings for temporarily allowing a blocked site.
    public var friction: Friction

    public struct Friction: Codable, Equatable, Sendable {
        /// Seconds the user has to wait before a temporary unblock can be confirmed.
        public var countdownSeconds: Int
        /// Whether the user must type a reason for the unblock.
        public var requiresReason: Bool
        /// Unblock duration preselected in the dialog, in minutes.
        public var defaultDurationMinutes: Int

        public static let durationChoices = [5, 15, 30]

        public init(countdownSeconds: Int = 60, requiresReason: Bool = true, defaultDurationMinutes: Int = 15) {
            self.countdownSeconds = countdownSeconds
            self.requiresReason = requiresReason
            self.defaultDurationMinutes = defaultDurationMinutes
        }
    }

    public static let defaultDomains = ["instagram.com", "youtube.com"]

    public init(blockedDomains: [String] = Configuration.defaultDomains, friction: Friction = Friction()) {
        self.blockedDomains = blockedDomains
        self.friction = friction
    }

    /// Adds a domain from free-form input. Returns the normalized domain, or `nil` if the
    /// input was invalid. Adding a domain that is already present is a no-op.
    @discardableResult
    public mutating func addDomain(_ input: String) -> String? {
        guard let domain = Domain.normalize(input) else { return nil }
        if !blockedDomains.contains(domain) {
            blockedDomains.append(domain)
            blockedDomains.sort()
        }
        return domain
    }

    public mutating func removeDomain(_ domain: String) {
        blockedDomains.removeAll { $0 == domain }
    }
}
