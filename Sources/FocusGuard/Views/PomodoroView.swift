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
                if cycle.canStop(at: now) {
                    Button("Stop", role: .destructive) { model.stopCycle() }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(4)
        }
    }

    private var title: String {
        switch cycle.state {
        case .active: "Active \(cycle.activeNumber) of \(cycle.plan.actives)"
        case .break: "Break · next: Active \(cycle.activeNumber + 1) of \(cycle.plan.actives)"
        case .idle: "Idle · next: Active \(cycle.activeNumber + 1) of \(cycle.plan.actives)"
        }
    }

    private func timer(at now: Date) -> String {
        let overtime = cycle.overtime(at: now)
        if overtime > 0 { return "+" + formatCountdown(overtime) }
        if let remaining = cycle.remaining(at: now) { return formatCountdown(remaining) }
        return formatCountdown(now.timeIntervalSince(cycle.stateStart))
    }

    @ViewBuilder private func mainButton(at now: Date) -> some View {
        if cycle.reachedPlannedLength(at: now) {
            BigButton(title: cycle.isLastActive ? "Finish Cycle" : "Start Break", action: model.endActive)
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
