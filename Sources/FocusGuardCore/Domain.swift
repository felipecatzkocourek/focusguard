import Foundation

/// Validation and normalization for the domains a user wants to block.
///
/// The user can type anything into the "add site" field — `YouTube.com`,
/// `https://www.youtube.com/watch?v=…`, `m.instagram.com` — and we reduce it to a
/// canonical registrable-looking domain (`youtube.com`). The same validator is used by
/// the privileged helper, so nothing that isn't a plain hostname can reach `/etc/hosts`.
public enum Domain {
    /// Subdomain prefixes that are stripped on input and re-added when expanding.
    public static let variantPrefixes = ["www.", "m."]

    /// Normalizes free-form user input into a bare domain, or returns `nil` if the
    /// input is not a valid hostname.
    public static func normalize(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let schemeRange = text.range(of: "://") {
            text = String(text[schemeRange.upperBound...])
        }
        // Drop path, query, fragment, port and credentials.
        if let cut = text.firstIndex(where: { "/?#".contains($0) }) {
            text = String(text[..<cut])
        }
        if let at = text.lastIndex(of: "@") {
            text = String(text[text.index(after: at)...])
        }
        if let colon = text.firstIndex(of: ":") {
            text = String(text[..<colon])
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        for prefix in variantPrefixes where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            break
        }

        return isValidHostname(text) ? text : nil
    }

    /// Strict RFC 1123 hostname check: at least two labels, each 1–63 characters of
    /// `a-z`, `0-9` or `-`, not starting or ending with `-`, total length ≤ 253, and an
    /// alphabetic top-level label.
    public static func isValidHostname(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }

        for label in labels {
            guard (1...63).contains(label.count),
                  label.first != "-", label.last != "-",
                  label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            else { return false }
        }
        return labels.last!.allSatisfy { $0.isASCII && $0.isLetter } && labels.last!.count >= 2
    }

    /// The concrete hostnames that must be blocked for a domain: the bare domain plus
    /// its common variants (`www.`, `m.`). Hosts files have no wildcards, so each one
    /// has to be listed explicitly.
    public static func hostnames(for domain: String) -> [String] {
        [domain] + variantPrefixes.map { $0 + domain }
    }
}
