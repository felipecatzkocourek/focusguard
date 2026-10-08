import FocusGuardCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let friction = model.configuration.friction
        Form {
            Section {
                if model.focus.modes.isEmpty {
                    Text(model.focus.access == .ok
                         ? "No Focus modes found."
                         : "Grant Full Disk Access in Setup to see your Focus modes.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.focus.modes) { mode in
                        Toggle(isOn: Binding(
                            get: { model.configuration.triggerFocusIdentifiers.contains(mode.id) },
                            set: { enabled in Task { await model.setTrigger(mode, enabled: enabled) } }
                        )) {
                            HStack {
                                Text(mode.name)
                                if mode.id == model.focus.activeModeIdentifier {
                                    StatusPill(text: "On now", color: .green)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Block sites while these Focus modes are on")
            } footer: {
                lockedNote
            }
            .disabled(model.isLocked)

            Section {
                Stepper(value: binding(\.countdownSeconds), in: 0...300, step: 15) {
                    LabeledContent("Wait before allowing", value: friction.countdownSeconds == 0 ? "No wait" : "\(friction.countdownSeconds) s")
                }
                Toggle("Ask for a reason", isOn: binding(\.requiresReason))
                Picker("Default duration", selection: binding(\.defaultDurationMinutes)) {
                    ForEach(Configuration.Friction.durationChoices, id: \.self) { Text("\($0) minutes").tag($0) }
                }
            } header: {
                Text("Temporary unblock")
            } footer: {
                lockedNote
            }
            .disabled(model.isLocked)

            if BrowserTabs.isFirefoxInstalled {
                Section {
                    Toggle("Restart Firefox automatically when blocking starts", isOn: Binding(
                        get: { model.configuration.restartsFirefoxAutomatically },
                        set: { model.setRestartsFirefoxAutomatically($0) }
                    ))
                } header: {
                    Text("Firefox")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tabs that are already open keep working until Firefox reconnects, and Firefox doesn't let other apps close them. Firefox is only restarted without asking when it's set to reopen previous windows and tabs; otherwise FocusGuard asks first.")
                            .foregroundStyle(.secondary)
                        lockedNote
                    }
                }
                .disabled(model.isLocked)
            }

            Section("General") {
                Toggle("Open FocusGuard when I log in", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchesAtLogin($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var lockedNote: some View {
        if model.isLocked {
            Label("Locked while blocking is on, so it can't be loosened in the moment.", systemImage: "lock.fill")
                .foregroundStyle(.secondary)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Configuration.Friction, Value>) -> Binding<Value> {
        Binding(
            get: { model.configuration.friction[keyPath: keyPath] },
            set: { newValue in model.updateFriction { $0[keyPath: keyPath] = newValue } }
        )
    }
}
