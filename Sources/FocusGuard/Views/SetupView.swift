import AppKit
import SwiftUI

/// One-time setup: install the helper, give FocusGuard permission to see the Focus, and
/// place the window.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var installing = false
    @State private var installingFirefoxPolicy = false

    private static let fullDiskAccessSettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                step(1, "Install the blocking helper", done: model.helperStatus == .installed) {
                    Text("FocusGuard blocks sites through /etc/hosts, which only an administrator can change. This installs a tiny helper once, so you won't be asked for your password every time blocking starts.")
                    HStack {
                        switch model.helperStatus {
                        case .installed:
                            Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .checking:
                            ProgressView().controlSize(.small)
                        case .notInstalled, .outdated:
                            if model.helperStatus == .outdated {
                                Text("This version of FocusGuard needs a newer helper.")
                                    .foregroundStyle(.orange)
                            }
                            Button(installing ? "Installing…" : model.helperStatus == .outdated ? "Update Helper…" : "Install Helper…") {
                                installing = true
                                Task {
                                    await model.installHelper()
                                    installing = false
                                }
                            }
                            .disabled(installing)
                        }
                        Button("Check Again") { Task { await model.refreshHelperStatus() } }
                            .buttonStyle(.link)
                    }
                }

                step(2, "Let FocusGuard see your Focus", done: model.focus.access == .ok) {
                    Text("macOS keeps the current Focus in a protected file. FocusGuard reads it to start blocking the moment you turn on a chosen Focus, from this Mac or from your iPhone (with **Share Across Devices** on). No Shortcuts automation is needed, and nothing but the Focus switch can turn blocking off.")
                    switch model.focus.access {
                    case .ok:
                        Label(
                            model.focus.activeMode.map { "Working. Current Focus: \($0.name)" } ?? "Working. No Focus is on right now.",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                    case .needsFullDiskAccess:
                        VStack(alignment: .leading, spacing: 6) {
                            Text("1. Open **Privacy & Security → Full Disk Access**.")
                            Text("2. Click **+**, choose **FocusGuard** in Applications, and turn it on.")
                            Text("3. Come back here. It's detected automatically within a few seconds.")
                        }
                        .font(.callout)
                        Button("Open Full Disk Access Settings") {
                            NSWorkspace.shared.open(Self.fullDiskAccessSettings)
                        }
                    case .unreadable(let reason):
                        Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }

                step(3, "Choose which Focus modes block", done: !model.configuration.triggerFocusIdentifiers.isEmpty) {
                    Text(model.triggerModeNames.isEmpty
                         ? "Pick them in **Settings**."
                         : "Blocking starts with: **\(ListFormatter.localizedString(byJoining: model.triggerModeNames))**. Change this in Settings.")
                }

                if BrowserTabs.isFirefoxInstalled {
                    step(4, "Make Firefox react instantly", done: model.firefoxPolicyInstalled) {
                        Text("Firefox keeps its own address cache, so on its own it notices blocking (and unblocking) only after a minute or more, or after a restart. A Firefox policy turns that cache off. Firefox will say it's *managed by your organization* because of it.")
                        Text("If you use **DNS over HTTPS** in Firefox, FocusGuard also adds your blocked sites to its exceptions automatically, so they're looked up through macOS and get blocked, while DNS over HTTPS stays on for everything else. Firefox picks up newly added sites after a restart.")
                        HStack {
                            if model.firefoxPolicyInstalled {
                                Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Button(installingFirefoxPolicy ? "Installing…" : "Install Firefox Policy…") {
                                    installingFirefoxPolicy = true
                                    Task {
                                        await model.installFirefoxPolicy()
                                        installingFirefoxPolicy = false
                                    }
                                }
                                .disabled(installingFirefoxPolicy)
                            }
                            Button("Check Again") { model.refreshFirefoxPolicyStatus() }
                                .buttonStyle(.link)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Then, in Firefox:")
                            Text("1. **Settings → General → Startup**: turn on **Open previous windows and tabs**, so FocusGuard can restart Firefox without losing your tabs.")
                            Text("2. Quit Firefox completely (**⌘Q**) and open it again once, so the policy takes effect.")
                        }
                        .font(.callout)
                    }
                }

                step(BrowserTabs.isFirefoxInstalled ? 5 : 4, "Let FocusGuard close blocked tabs", done: false) {
                    Text("When blocking starts, tabs that already have a blocked site open keep working for a while. FocusGuard closes them:")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• **Safari and Chrome:** the first time, macOS asks whether FocusGuard may control the browser. Click **Allow**. You can change this later in Privacy & Security → Automation.")
                        Text("• **Firefox:** it can't close single tabs for other apps, so FocusGuard restarts it when blocking starts. Your tabs come back, and the blocked ones stay blocked. It only does this automatically when Firefox reopens previous windows and tabs; otherwise it asks.")
                    }
                    .font(.callout)
                }

                step(BrowserTabs.isFirefoxInstalled ? 6 : 5, "Put this window where it helps", done: false) {
                    Text("Drag this window to your second monitor. FocusGuard remembers where it was and comes forward there whenever blocking starts. Turn on **Open FocusGuard when I log in** in Settings so it's always watching.")
                }
            }
            .padding(4)
        }
    }

    private func step<Content: View>(_ number: Int, _ title: String, done: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor).frame(width: 26, height: 26)
                if done {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.callout.bold()).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
