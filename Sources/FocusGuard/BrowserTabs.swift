import AppKit
import FocusGuardCore

/// Gets already-open tabs of newly blocked sites out of the way.
///
/// Blocking works at the DNS level, so a tab that's already connected can keep working
/// for a while. Safari and Chrome can be told to close those tabs over AppleScript (macOS
/// asks once for permission). Firefox can't, so we detect such tabs from its saved
/// session and offer to restart it instead.
enum BrowserTabs {
    private struct ScriptableBrowser {
        let name: String
        let bundleIdentifier: String
    }

    private static let scriptable = [
        ScriptableBrowser(name: "Safari", bundleIdentifier: "com.apple.Safari"),
        ScriptableBrowser(name: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
    ]

    static let firefoxBundleIdentifier = "org.mozilla.firefox"

    // MARK: - Safari & Chrome

    /// Closes every tab showing one of `hostnames` in Safari and Chrome, if they're running.
    /// Browsers that aren't running are never launched.
    static func closeTabs(showing hostnames: Set<String>) async {
        guard !hostnames.isEmpty else { return }
        let running = scriptable.filter { isRunning($0.bundleIdentifier) }
        for browser in running {
            let script = closeTabsScript(app: browser.name)
            await Task.detached {
                let process = Process()
                process.executableURL = URL(filePath: "/usr/bin/osascript")
                process.arguments = ["-e", script] + hostnames.sorted()
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
            }.value
        }
    }

    /// Walks tabs back to front (so indexes stay valid while closing) and closes those
    /// whose URL is on one of the hostnames passed as arguments. Matching on "://host"
    /// avoids hitting look-alikes such as notyoutube.com.
    private static func closeTabsScript(app: String) -> String {
        """
        on run hostnames
            tell application "\(app)"
                repeat with w in (every window)
                    set ts to tabs of w
                    repeat with i from (count ts) to 1 by -1
                        set u to URL of item i of ts
                        if u is not missing value then
                            repeat with h in hostnames
                                if u contains ("://" & h & "/") or u ends with ("://" & h) then
                                    close item i of ts
                                    exit repeat
                                end if
                            end repeat
                        end if
                    end repeat
                end repeat
            end tell
        end run
        """
    }

    // MARK: - Firefox

    static var isFirefoxRunning: Bool { isRunning(firefoxBundleIdentifier) }

    static var isFirefoxInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: firefoxBundleIdentifier) != nil
    }

    /// Blocked hostnames currently open in Firefox, from its most recently saved session.
    /// Firefox saves every ~15 s, so a tab opened just now may not be listed yet.
    static func firefoxTabs(showing hostnames: Set<String>) -> Set<String> {
        guard isFirefoxRunning,
              let file = newestFirefoxProfileFile("sessionstore-backups/recovery.jsonlz4"),
              let data = try? Data(contentsOf: file),
              let json = try? FirefoxSession.decompressMozLz4(data),
              let urls = try? FirefoxSession.openTabURLs(sessionJSON: json)
        else { return [] }
        return FirefoxSession.openBlockedHostnames(in: urls, blocked: hostnames)
    }

    /// Whether Firefox reopens previous windows and tabs on launch, so a restart is harmless.
    static var firefoxRestoresSession: Bool {
        guard let prefs = newestFirefoxProfileFile("prefs.js"),
              let text = try? String(contentsOf: prefs, encoding: .utf8)
        else { return false }
        return text.contains(#"user_pref("browser.startup.page", 3);"#)
    }

    /// Quits Firefox normally (it saves its session) and opens it again.
    static func restartFirefox() async {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: firefoxBundleIdentifier).first,
              let url = app.bundleURL
        else { return }
        app.terminate()
        for _ in 0..<60 where !app.isTerminated {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard app.isTerminated else { return }
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Whether FocusGuard's Firefox policy (DNS cache disabled) is in place.
    static var isFirefoxPolicyInstalled: Bool {
        guard let plist = NSDictionary(contentsOfFile: "/Library/Preferences/org.mozilla.firefox.plist"),
              plist["EnterprisePoliciesEnabled"] as? Bool == true,
              let prefs = plist["Preferences"] as? [String: Any],
              let cache = prefs["network.dnsCacheExpiration"] as? [String: Any]
        else { return false }
        return cache["Value"] as? Int == 0
    }

    // MARK: - Helpers

    private static func isRunning(_ bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// The file at `relativePath` in the Firefox profile that was used most recently.
    private static func newestFirefoxProfileFile(_ relativePath: String) -> URL? {
        let profiles = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Firefox/Profiles", directoryHint: .isDirectory)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil) else {
            return nil
        }
        return entries
            .map { $0.appending(path: relativePath) }
            .compactMap { url -> (URL, Date)? in
                guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
                return (url, date)
            }
            .max { $0.1 < $1.1 }?
            .0
    }
}
