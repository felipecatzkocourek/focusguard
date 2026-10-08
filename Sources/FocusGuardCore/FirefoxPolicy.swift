import Foundation

/// FocusGuard's part of Firefox's system-wide policy (`/Library/Preferences/org.mozilla.firefox`).
///
/// With DNS over HTTPS on, Firefox resolves names through an encrypted resolver and
/// skips `/etc/hosts` for anything it wasn't excluded from at startup. Listing the
/// blocked domains in `DNSOverHTTPS.ExcludedDomains` makes Firefox resolve just those
/// through macOS, which honors FocusGuard's block, while DNS over HTTPS stays on for
/// everything else. The setting excludes subdomains too.
public enum FirefoxPolicy {
    public static let applicationID = "org.mozilla.firefox"
    public static let dnsOverHTTPSKey = "DNSOverHTTPS"
    public static let excludedDomainsKey = "ExcludedDomains"

    /// The domains currently excluded from DNS over HTTPS in a `DNSOverHTTPS` policy value.
    public static func excludedDomains(in dnsOverHTTPS: [String: Any]?) -> [String] {
        (dnsOverHTTPS?[excludedDomainsKey] as? [String]) ?? []
    }

    /// Returns the `DNSOverHTTPS` policy value with `ExcludedDomains` set to `domains`,
    /// keeping any other keys (e.g. a provider the user configured). Returns `nil` when
    /// nothing is left, meaning the key should be removed.
    public static func dnsOverHTTPS(_ current: [String: Any]?, excluding domains: [String]) -> [String: Any]? {
        var policy = current ?? [:]
        let unique = Array(Set(domains)).sorted()
        if unique.isEmpty {
            policy.removeValue(forKey: excludedDomainsKey)
        } else {
            policy[excludedDomainsKey] = unique
        }
        return policy.isEmpty ? nil : policy
    }
}
