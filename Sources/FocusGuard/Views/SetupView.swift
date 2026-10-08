import AppKit
import SwiftUI

/// One-time setup: install the helper, give FocusGuard permission to see the Focus, and
/// place the window.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var installing = false

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
                        case .notInstalled:
                            Button(installing ? "Installing…" : "Install Helper…") {
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

                step(4, "Put this window where it helps", done: false) {
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
