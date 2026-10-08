import Foundation

/// Reads and rewrites FocusGuard's own section of `/etc/hosts`.
///
/// Other tools also manage sections of the hosts file (for example game launchers that
/// block telemetry). FocusGuard only ever touches the lines between its markers and
/// leaves everything else byte-for-byte intact.
public enum HostsFile {
    public static let path = "/etc/hosts"
    public static let beginMarker = "# BEGIN FocusGuard (managed automatically, do not edit)"
    public static let endMarker = "# END FocusGuard"

    /// Returns `contents` with FocusGuard's section replaced by one that blocks
    /// `hostnames`. An empty list removes the section entirely.
    public static func applying(blockedHostnames hostnames: [String], to contents: String) -> String {
        var lines = linesOutsideSection(of: contents)

        // Keep the file tidy: no trailing blank lines before we append.
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }

        let unique = Array(Set(hostnames)).sorted()
        if !unique.isEmpty {
            lines.append("")
            lines.append(beginMarker)
            for host in unique {
                // Block both IPv4 and IPv6, otherwise dual-stack sites still load.
                lines.append("0.0.0.0 \(host)")
                lines.append(":: \(host)")
            }
            lines.append(endMarker)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The hostnames currently blocked by FocusGuard's section of `contents`.
    public static func blockedHostnames(in contents: String) -> [String] {
        var inSection = false
        var hosts = Set<String>()
        for line in contents.components(separatedBy: "\n") {
            if line == beginMarker { inSection = true; continue }
            if line == endMarker { inSection = false; continue }
            guard inSection else { continue }
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count >= 2 { hosts.insert(String(parts[1])) }
        }
        return hosts.sorted()
    }

    private static func linesOutsideSection(of contents: String) -> [String] {
        var result: [String] = []
        var inSection = false
        var lines = contents.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }

        for line in lines {
            if line == beginMarker { inSection = true; continue }
            if line == endMarker { inSection = false; continue }
            if !inSection { result.append(line) }
        }
        return result
    }
}
