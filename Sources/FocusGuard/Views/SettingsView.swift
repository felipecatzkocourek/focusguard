import FocusGuardCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let friction = model.configuration.friction
        Form {
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
                if model.isLocked {
                    Label("Locked while Work is on, so it can't be loosened in the moment.", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(model.isLocked)

            Section("General") {
                Toggle("Open FocusGuard when I log in", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchesAtLogin($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Configuration.Friction, Value>) -> Binding<Value> {
        Binding(
            get: { model.configuration.friction[keyPath: keyPath] },
            set: { newValue in model.updateFriction { $0[keyPath: keyPath] = newValue } }
        )
    }
}
