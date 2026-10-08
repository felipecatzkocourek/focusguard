import Foundation

/// User-editable settings, persisted as JSON.
public struct Configuration: Codable, Equatable, Sendable {
    /// Domains blocked during a session, already normalized (see ``Domain``).
    public var blockedDomains: [String]
    /// Focus modes (by identifier) that turn blocking on.
    public var triggerFocusIdentifiers: Set<String>
    /// Settings for temporarily allowing a blocked site.
    public var friction: Friction
    /// Restart Firefox without asking when blocking starts (only if it restores its tabs).
    public var restartsFirefoxAutomatically: Bool

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
    public static let defaultTriggerFocusIdentifiers: Set<String> = ["com.apple.focus.work"]

    public init(
        blockedDomains: [String] = Configuration.defaultDomains,
        triggerFocusIdentifiers: Set<String> = Configuration.defaultTriggerFocusIdentifiers,
        friction: Friction = Friction(),
        restartsFirefoxAutomatically: Bool = true
    ) {
        self.blockedDomains = blockedDomains
        self.triggerFocusIdentifiers = triggerFocusIdentifiers
        self.friction = friction
        self.restartsFirefoxAutomatically = restartsFirefoxAutomatically
    }

    /// Decodes leniently so settings saved by an older version (missing newer keys) keep
    /// the user's sites instead of falling back to defaults.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockedDomains = try container.decodeIfPresent([String].self, forKey: .blockedDomains) ?? Self.defaultDomains
        triggerFocusIdentifiers = try container.decodeIfPresent(Set<String>.self, forKey: .triggerFocusIdentifiers)
            ?? Self.defaultTriggerFocusIdentifiers
        friction = try container.decodeIfPresent(Friction.self, forKey: .friction) ?? Friction()
        restartsFirefoxAutomatically = try container.decodeIfPresent(Bool.self, forKey: .restartsFirefoxAutomatically) ?? true
    }

    /// Whether the given active Focus (or none) should turn blocking on.
    public func shouldBlock(activeFocusIdentifier: String?) -> Bool {
        guard let activeFocusIdentifier else { return false }
        return triggerFocusIdentifiers.contains(activeFocusIdentifier)
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
