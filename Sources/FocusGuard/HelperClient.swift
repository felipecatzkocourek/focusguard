import Foundation

/// Talks to the privileged helper through `sudo -n` (never prompts; the sudoers rule
/// installed by `helper/install.sh` makes it passwordless for this one binary).
struct HelperClient: Sendable {
    static let installedPath = "/Library/PrivilegedHelperTools/com.felipekocourek.focusguard.helper"
    /// The helper API this build of the app needs (see `apiLevel` in the helper).
    static let requiredAPILevel = 2

    enum Failure: LocalizedError {
        case notInstalled
        case commandFailed(String)
        case bundleResourcesMissing
        case installCancelled

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                "The FocusGuard helper isn't installed yet, so sites can't be blocked. Open the Setup tab to install it."
            case .commandFailed(let message):
                message.isEmpty ? "The helper failed." : message
            case .bundleResourcesMissing:
                "Helper files aren't in the app bundle. Build the app with scripts/build-app.sh."
            case .installCancelled:
                "Installation was cancelled."
            }
        }
    }

    var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: Self.installedPath)
    }

    /// True when the helper is installed *and* the sudoers rule lets us run it.
    func isAuthorized() async -> Bool {
        guard isInstalled else { return false }
        return (try? await runHelper(["status"])) != nil
    }

    /// The installed helper's API level. Helpers from before levels existed report 1.
    func apiLevel() async -> Int {
        guard let output = try? await runHelper(["api-level"]) else { return 1 }
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
    }

    /// Sets Firefox's DNS-over-HTTPS exclusions to exactly `domains`.
    func setFirefoxExclusions(_ domains: [String]) async throws {
        try await runHelper(["firefox-exclude"] + domains)
    }

    /// Makes FocusGuard's hosts section block exactly `hostnames` (empty clears it).
    func block(_ hostnames: [String]) async throws {
        try await runHelper(hostnames.isEmpty ? ["clear"] : ["block"] + hostnames)
    }

    /// Synchronous variant for `applicationWillTerminate`, where we can't await.
    func blockSynchronously(_ hostnames: [String]) throws {
        try Self.runSudo(hostnames.isEmpty ? ["clear"] : ["block"] + hostnames)
    }

    /// Runs the bundled `install.sh` through the standard macOS administrator prompt.
    func install() async throws {
        guard let binary = Bundle.main.url(forResource: "focusguard-helper", withExtension: nil) else {
            throw Failure.bundleResourcesMissing
        }
        try await runBundledScriptAsAdmin("install", arguments: [binary.path(), NSUserName()])
    }

    /// Installs the Firefox policy that turns off Firefox's own DNS cache.
    func installFirefoxPolicy() async throws {
        try await runBundledScriptAsAdmin("firefox-policy", arguments: ["install"])
    }

    /// Runs `<name>.sh` from the app bundle as root via the standard admin prompt.
    private func runBundledScriptAsAdmin(_ name: String, arguments: [String]) async throws {
        guard let script = Bundle.main.url(forResource: name, withExtension: "sh") else {
            throw Failure.bundleResourcesMissing
        }
        let shellCommand = ([script.path()] + arguments).map(Self.shellQuoted).joined(separator: " ")
        let appleScript = "do shell script \"\(Self.appleScriptEscaped(shellCommand))\" with administrator privileges"

        do {
            try await Task.detached {
                _ = try Self.run("/usr/bin/osascript", ["-e", appleScript])
            }.value
        } catch Failure.commandFailed(let message) where message.contains("-128") {
            throw Failure.installCancelled
        }
    }

    // MARK: - Process plumbing

    @discardableResult
    private func runHelper(_ arguments: [String]) async throws -> String {
        guard isInstalled else { throw Failure.notInstalled }
        return try await Task.detached { try Self.runSudo(arguments) }.value
    }

    @discardableResult
    private static func runSudo(_ arguments: [String]) throws -> String {
        try run("/usr/bin/sudo", ["-n", installedPath] + arguments)
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.commandFailed(message)
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
