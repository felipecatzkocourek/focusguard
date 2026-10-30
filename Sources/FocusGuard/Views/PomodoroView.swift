import FocusGuardCore
import SwiftUI

/// The Pomodoro tab: build a Plan and start a Cycle, then follow it on a large timer.
struct PomodoroView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let cycle = model.cycle {
            RunningCycleView(cycle: cycle)
        } else {
            PlanEditor()
        }
    }
}

private struct PlanEditor: View {
    @Environment(AppModel.self) private var model
    @State private var activeMinutes = 25
    @State private var breakMinutes = 5
    @State private var actives = 4

    private var plan: Plan? {
        Plan(activeMinutes: activeMinutes, breakMinutes: breakMinutes, actives: actives)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionTitle("Plan")
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Stepper("Active: \(activeMinutes) min", value: $activeMinutes, in: 5...180, step: 5)
                    Stepper("Break: \(breakMinutes) min", value: $breakMinutes, in: 1...60)
                    Stepper("Actives: \(actives)", value: $actives, in: 2...12)
                }
                .padding(4)
            }
            if let plan {
                Text("\(plan.summary) → ends in \(formatDuration(plan.totalLength))")
                    .foregroundStyle(.secondary)
            }
            Button {
                if let plan { model.startCycle(plan) }
            } label: {
                Text("Start").font(.title2.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(plan == nil)
            Spacer()
        }
        .padding(4)
    }
}

private struct RunningCycleView: View {
    @Environment(AppModel.self) private var model
    let cycle: PomodoroCycle
    @State private var cuttingShort: CutShortSheet.Action?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            VStack(spacing: 24) {
                Spacer()
                Text(title).font(.title.weight(.semibold)).foregroundStyle(.secondary)
                Text(timer(at: now))
                    .font(.system(size: 96, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(cycle.overtime(at: now) > 0 ? .orange : .primary)
                if cycle.overtime(at: now) > 0 {
                    Text("Overtime").font(.title3).foregroundStyle(.orange)
                }
                Spacer()
                mainButton(at: now)
                Button("Stop", role: .destructive) {
                    if cycle.canStop(at: now) { model.stopCycle() } else { cuttingShort = .stop }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(4)
        }
        .sheet(item: $cuttingShort) { CutShortSheet(cycle: cycle, action: $0) }
    }

    private var title: String {
        switch cycle.state {
        case .active: "Active \(cycle.activeNumber) of \(cycle.plan.actives)"
        case .break: "Break · next: Active \(cycle.activeNumber + 1) of \(cycle.plan.actives)"
        case .idle: "Idle · next: Active \(cycle.activeNumber + 1) of \(cycle.plan.actives)"
        }
    }

    private func timer(at now: Date) -> String {
        // Countdowns round up so 0:00 means done; Overtime and Idle count up, so they round
        // down and don't show a second that hasn't passed yet.
        let overtime = cycle.overtime(at: now)
        if overtime > 0 { return "+" + formatCountdown(overtime.rounded(.down)) }
        if let remaining = cycle.remaining(at: now) { return formatCountdown(remaining) }
        return formatCountdown(now.timeIntervalSince(cycle.stateStart).rounded(.down))
    }

    @ViewBuilder private func mainButton(at now: Date) -> some View {
        if cycle.reachedPlannedLength(at: now) {
            BigButton(title: cycle.isLastActive ? "Finish Cycle" : "Start Break") { model.endActive() }
        } else if cycle.state == .active {
            Button(cycle.isLastActive ? "Finish Cycle Early…" : "End Active Early…") { cuttingShort = .endActive }
                .controlSize(.large)
        } else if cycle.state == .break {
            Button("End Break · Start Active \(cycle.activeNumber + 1)", action: model.endBreak)
                .controlSize(.large)
        } else if cycle.state == .idle {
            BigButton(title: "Start Active \(cycle.activeNumber + 1)", action: model.startActive)
        }
    }
}

private struct BigButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.title.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.extraLarge)
    }
}

/// The Friction for cutting an Active short (ending it or stopping the Cycle before its
/// planned length): the time left and a typed reason.
private struct CutShortSheet: View {
    enum Action: Identifiable {
        case endActive, stop
        var id: Self { self }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cycle: PomodoroCycle
    let action: Action
    @State private var reason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.bold())
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("\(formatCountdown(cycle.remaining(at: context.date) ?? 0)) left in Active \(cycle.activeNumber) of \(cycle.plan.actives). It will be logged as cut short, with your reason.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("Reason", text: $reason, prompt: Text("Why are you stopping early?"))
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Keep Going", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(confirmTitle) {
                    switch action {
                    case .endActive: model.endActive(reason: reason)
                    case .stop: model.stopCycle(reason: reason)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(PomodoroCycle.validReason(reason) == nil)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var title: String {
        switch action {
        case .endActive: cycle.isLastActive ? "Finish the Cycle early?" : "End this Active early?"
        case .stop: "Stop the Cycle early?"
        }
    }

    private var confirmTitle: String {
        switch action {
        case .endActive: cycle.isLastActive ? "Finish Cycle" : "Start Break"
        case .stop: "Stop Cycle"
        }
    }
}
