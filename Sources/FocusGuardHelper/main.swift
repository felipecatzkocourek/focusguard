// focusguard-helper — the only FocusGuard component that runs as root.
//
// It does exactly one thing: rewrite FocusGuard's own section of /etc/hosts. It is
// installed root-owned in /Library/PrivilegedHelperTools and a sudoers rule lets the
// installing user run it (and nothing else) without a password.
//
// Every argument is validated as a plain hostname before it gets anywhere near the
// hosts file, and lines outside FocusGuard's markers are never modified.
//
// Usage:
//   focusguard-helper block <hostname>...   Replace the section with these hostnames
//   focusguard-helper clear                 Remove the section
//   focusguard-helper status                Print the hostnames currently blocked
//   focusguard-helper version

import FocusGuardCore
import Foundation

let version = "0.1.0"
let maxHostnames = 1_000

enum HelperError: Error, CustomStringConvertible {
    case usage
    case notRoot
    case invalidHostname(String)
    case tooManyHostnames
    case io(String)

    var description: String {
        switch self {
        case .usage: "usage: focusguard-helper block <hostname>... | clear | status | version"
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
    case "version", "--version":
        print(version)
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
