import AppKit
import FocusGuardCore
import SwiftUI

/// One-time setup: install the helper, then create the two Shortcuts automations that
/// connect the Work Focus (on the Mac or synced from the iPhone) to FocusGuard.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var installing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                step(1, "Install the blocking helper", done: model.helperStatus == .installed) {
                    Text("FocusGuard blocks sites through /etc/hosts, which only an administrator can change. This installs a tiny helper once, so you won't be asked for your password every time Work turns on.")
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

                step(2, "Connect it to the Work Focus", done: false) {
                    Text("In Shortcuts, create two personal automations. If Focus is shared across devices, switching Work on your iPhone will trigger them on this Mac too.")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Open Shortcuts → **Automation** → **New Automation**.")
                        Text("2. Choose **Focus** → **Work** → **When Turning On**, set it to **Run Immediately**.")
                        Text("3. Add the action **Open URLs** with:")
                        URLRow(url: FocusCommand.workOn.url)
                        Text("4. Repeat with **When Turning Off** and:")
                        URLRow(url: FocusCommand.workOff.url)
                    }
                    .font(.callout)
                    Button("Open Shortcuts") {
                        NSWorkspace.shared.open(URL(filePath: "/System/Applications/Shortcuts.app"))
                    }
                }

                step(3, "Put this window where it helps", done: false) {
                    Text("Drag this window to your second monitor. FocusGuard remembers where it was and comes forward there whenever Work starts. Turn on **Open FocusGuard when I log in** in Settings so it's always ready.")
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

private struct URLRow: View {
    let url: URL
    @State private var copied = false

    var body: some View {
        HStack {
            Text(url.absoluteString)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                copied = true
            }
            .buttonStyle(.link)
        }
        .padding(.leading, 16)
    }
}
