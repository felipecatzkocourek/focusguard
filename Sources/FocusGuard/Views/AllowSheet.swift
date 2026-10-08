import FocusGuardCore
import SwiftUI

/// The friction gate: before a blocked site can be used during Work, you wait out a
/// countdown and (optionally) write down why. Long enough to break the reflex, short
/// enough not to get in the way when you genuinely need a tutorial.
struct AllowSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var domain = ""
    @State private var minutes = 15
    @State private var reason = ""
    @State private var openedAt = Date()

    private var friction: Configuration.Friction { model.configuration.friction }

    private var durationChoices: [Int] {
        Array(Set(Configuration.Friction.durationChoices + [friction.defaultDurationMinutes])).sorted()
    }

    private var candidates: [String] {
        model.configuration.blockedDomains.filter { model.state.allowance(for: $0, at: .now) == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Temporarily allow a site").font(.title2.bold())
            Text("Take a breath. Is this really for work?")
                .foregroundStyle(.secondary)

            if candidates.isEmpty {
                Text("Every site is already allowed.").foregroundStyle(.secondary)
            } else {
                Form {
                    Picker("Site", selection: $domain) {
                        ForEach(candidates, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("For", selection: $minutes) {
                        ForEach(durationChoices, id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                    if friction.requiresReason {
                        TextField("Reason", text: $reason, prompt: Text("e.g. SwiftUI layout tutorial"))
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
            }

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let remaining = Double(friction.countdownSeconds) - context.date.timeIntervalSince(openedAt)
                HStack {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    if remaining > 0 {
                        ProgressView(value: 1 - remaining / Double(max(friction.countdownSeconds, 1)))
                            .frame(width: 120)
                        Text("Wait \(formatCountdown(remaining))")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Button("Allow for \(minutes) min") {
                        let chosen = domain, why = reason.trimmingCharacters(in: .whitespacesAndNewlines), duration = minutes
                        Task { await model.grantAllowance(domain: chosen, reason: why, minutes: duration) }
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(remaining > 0 || !isValid)
                }
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            openedAt = Date()
            domain = candidates.first ?? ""
            minutes = friction.defaultDurationMinutes
        }
    }

    private var isValid: Bool {
        guard candidates.contains(domain) else { return false }
        return !friction.requiresReason || reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }
}
