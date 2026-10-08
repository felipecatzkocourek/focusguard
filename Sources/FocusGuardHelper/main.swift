// focusguard-helper — the only FocusGuard component that runs as root.
//
// It rewrites FocusGuard's own section of /etc/hosts and keeps Firefox's list of
// domains excluded from DNS over HTTPS in sync with it. It is installed root-owned in
// /Library/PrivilegedHelperTools and a sudoers rule lets the installing user run it
// (and nothing else) without a password.
//
// Every argument is validated as a plain hostname before it is written anywhere, lines
// outside FocusGuard's markers in /etc/hosts are never modified, and in Firefox's
// policy only DNSOverHTTPS.ExcludedDomains is touched.
//
// Usage:
//   focusguard-helper block <hostname>...           Replace the section with these hostnames
//   focusguard-helper clear                         Remove the section
//   focusguard-helper status                        Print the hostnames currently blocked
//   focusguard-helper firefox-exclude <domain>...   Set Firefox's DNS-over-HTTPS exclusions
//   focusguard-helper version | api-level

import FocusGuardCore
import Foundation

let version = "0.1.0"
/// Bumped whenever a command is added, so the app can tell an outdated install apart.
let apiLevel = 2
let maxHostnames = 1_000

enum HelperError: Error, CustomStringConvertible {
    case usage
    case notRoot
    case invalidHostname(String)
    case tooManyHostnames
    case io(String)

    var description: String {
        switch self {
        case .usage: "usage: focusguard-helper block <hostname>... | clear | status | firefox-exclude <domain>... | version | api-level"
        case .notRoot: "must be run as root (via sudo)"
        case .invalidHostname(let host): "refusing invalid hostname: \(host.debugDescription)"
        case .tooManyHostnames: "refusing more than \(maxHostnames) hostnames"
        case .io(let message): message
        }
    }
}

func readHosts() throws -> String {
    do {
        return try String(contentsOfFile: HostsFile.path, encoding: .utf8)
    } catch {
        throw HelperError.io("cannot read \(HostsFile.path): \(error.localizedDescription)")
    }
}

/// Writes the new hosts file atomically: a temp file in the same directory, then rename,
/// so a crash can never leave a half-written /etc/hosts.
func writeHosts(_ contents: String) throws {
    let target = URL(filePath: HostsFile.path).resolvingSymlinksInPath()
    let temp = target.deletingLastPathComponent().appending(path: ".hosts.focusguard.tmp")
    let fm = FileManager.default
    do {
        try? fm.removeItem(at: temp)
        guard fm.createFile(
            atPath: temp.path(),
            contents: Data(contents.utf8),
            attributes: [.posixPermissions: 0o644, .ownerAccountID: 0, .groupOwnerAccountID: 0]
        ) else { throw HelperError.io("cannot create \(temp.path())") }
        guard rename(temp.path(), target.path()) == 0 else {
            throw HelperError.io("cannot replace \(target.path()): \(String(cString: strerror(errno)))")
        }
    } catch {
        try? fm.removeItem(at: temp)
        throw error
    }
}

/// Browsers and the system resolver cache lookups; flush so the change applies now.
func flushDNSCache() {
    for (tool, args) in [("/usr/bin/dscacheutil", ["-flushcache"]), ("/usr/bin/killall", ["-HUP", "mDNSResponder"])] {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = args
        try? process.run()
        process.waitUntilExit()
    }
}

func apply(_ hostnames: [String]) throws {
    guard geteuid() == 0 else { throw HelperError.notRoot }
    let current = try readHosts()
    let updated = HostsFile.applying(blockedHostnames: hostnames, to: current)
    guard updated != current else { return }
    try writeHosts(updated)
    flushDNSCache()
}

/// Writes through cfprefsd (not straight to the file) so the change is never lost to a
/// cached copy of the preferences.
func setFirefoxExclusions(_ domains: [String]) throws {
    guard geteuid() == 0 else { throw HelperError.notRoot }
    let app = FirefoxPolicy.applicationID as CFString
    let key = FirefoxPolicy.dnsOverHTTPSKey as CFString
    let current = CFPreferencesCopyValue(key, app, kCFPreferencesAnyUser, kCFPreferencesAnyHost) as? [String: Any]
    let updated = FirefoxPolicy.dnsOverHTTPS(current, excluding: domains)
    guard FirefoxPolicy.excludedDomains(in: updated) != FirefoxPolicy.excludedDomains(in: current) else { return }

    if !domains.isEmpty {
        CFPreferencesSetValue("EnterprisePoliciesEnabled" as CFString, kCFBooleanTrue, app, kCFPreferencesAnyUser, kCFPreferencesAnyHost)
    }
    CFPreferencesSetValue(key, updated as CFPropertyList?, app, kCFPreferencesAnyUser, kCFPreferencesAnyHost)
    guard CFPreferencesSynchronize(app, kCFPreferencesAnyUser, kCFPreferencesAnyHost) else {
        throw HelperError.io("cannot save Firefox policy")
    }
}

func run(_ arguments: [String]) throws {
    guard let command = arguments.first else { throw HelperError.usage }
    let rest = Array(arguments.dropFirst())

    switch command {
    case "block":
        guard rest.count <= maxHostnames else { throw HelperError.tooManyHostnames }
        for host in rest where !Domain.isValidHostname(host) {
            throw HelperError.invalidHostname(host)
        }
        try apply(rest)
    case "clear":
        guard rest.isEmpty else { throw HelperError.usage }
        try apply([])
    case "status":
        for host in HostsFile.blockedHostnames(in: try readHosts()) {
            print(host)
        }
    case "firefox-exclude":
        guard rest.count <= maxHostnames else { throw HelperError.tooManyHostnames }
        for domain in rest where !Domain.isValidHostname(domain) {
            throw HelperError.invalidHostname(domain)
        }
        try setFirefoxExclusions(rest)
    case "version", "--version":
        print(version)
    case "api-level":
        print(apiLevel)
    default:
        throw HelperError.usage
    }
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("focusguard-helper: \(error)\n".utf8))
    exit(1)
}
