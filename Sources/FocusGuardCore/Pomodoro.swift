import Foundation

/// The shape of a Planned Cycle: how long each Active and each Break lasts, and how many
/// Actives there are. Breaks fall only between Actives, never after the last one.
public struct Plan: Codable, Equatable, Hashable, Sendable {
    public var activeMinutes: Int
    public var breakMinutes: Int
    public var actives: Int

    /// `nil` unless both lengths are positive and there are at least two Actives.
    public init?(activeMinutes: Int, breakMinutes: Int, actives: Int) {
        guard activeMinutes > 0, breakMinutes > 0, actives >= 2 else { return nil }
        self.activeMinutes = activeMinutes
        self.breakMinutes = breakMinutes
        self.actives = actives
    }

    public var activeLength: TimeInterval { TimeInterval(activeMinutes * 60) }
    public var breakLength: TimeInterval { TimeInterval(breakMinutes * 60) }
}

/// One run of a Pomodoro Cycle as a pure state machine. It has no timers or I/O: every
/// input carries an explicit time and returns the next state plus the effects the app
/// must carry out.
public struct PomodoroCycle: Codable, Equatable, Sendable {
    /// Where the Cycle is: in one of its Phases (an Active or a Break), or Idle between them.
    public enum State: Codable, Equatable, Sendable {
        case active, `break`, idle
    }

    /// Something the app must do as a result of an input.
    public enum Effect: Equatable, Sendable {
        case record(ActivityEvent.Kind, at: Date)
    }

    /// How a Cycle ended, for the activity log.
    public enum Ending: String, Codable, Equatable, Sendable {
        /// The last Active of the Plan ended.
        case completed
        /// The user pressed Stop.
        case stopped
    }

    /// The result of an input: the new state (`nil` once the Cycle has ended) and its effects.
    public struct Transition: Equatable, Sendable {
        public var cycle: PomodoroCycle?
        public var effects: [Effect]
    }

    public private(set) var plan: Plan
    public private(set) var state: State
    public private(set) var stateStart: Date
    /// 1-based index of the current (or, during a Break or Idle, the last) Active.
    public private(set) var activeNumber: Int

    public static func start(_ plan: Plan, at now: Date) -> Transition {
        let cycle = PomodoroCycle(plan: plan, state: .active, stateStart: now, activeNumber: 1)
        return Transition(cycle: cycle, effects: [.record(.cycleStarted(plan: plan), at: now)])
    }

    /// Planned length of the current Phase; `nil` while Idle.
    public var plannedLength: TimeInterval? {
        switch state {
        case .active: plan.activeLength
        case .break: plan.breakLength
        case .idle: nil
        }
    }

    /// Time left in the current Phase, never negative; `nil` while Idle.
    public func remaining(at now: Date) -> TimeInterval? {
        plannedLength.map { max($0 - now.timeIntervalSince(stateStart), 0) }
    }

    /// How long the current Active has run past its planned length; zero in other Phases.
    public func overtime(at now: Date) -> TimeInterval {
        guard state == .active else { return 0 }
        return max(now.timeIntervalSince(stateStart) - plan.activeLength, 0)
    }

    /// When the Cycle will change on its own (the end of the current Break), so the app can
    /// schedule a tick for that moment. Actives and Idle wait for the user.
    public var nextDeadline: Date? {
        state == .break ? stateStart.addingTimeInterval(plan.breakLength) : nil
    }

    // MARK: - Inputs

    public enum Input: Equatable, Sendable {
        /// Time passing.
        case tick
        /// The user ends the current Active.
        case endActive
        /// The user starts the next Active after a Break.
        case startActive
        /// The user ends the whole Cycle.
        case stop
    }

    /// Why an input was not accepted. The state is unchanged.
    public enum Rejection: Error, Equatable, Sendable {
        /// Ending an Active before its planned length needs a reason.
        case reasonRequired
        /// The input doesn't apply to the current state.
        case notAllowed
    }

    public func handle(_ input: Input, at now: Date) throws(Rejection) -> Transition {
        // Every input first lets time pass, so a Break that has run out is over before the
        // input is considered.
        var next = self
        var effects = next.advance(to: now)
        switch input {
        case .tick:
            break
        case .startActive:
            guard next.state == .idle else { throw .notAllowed }
            effects.append(.record(.idle(duration: now.timeIntervalSince(next.stateStart)), at: now))
            next.state = .active
            next.stateStart = now
            next.activeNumber += 1
        case .endActive:
            guard next.state == .active else { throw .notAllowed }
            effects.append(try next.activeEnded(at: now))
            guard next.activeNumber < plan.actives else {
                effects.append(.record(.cycleEnded(.completed), at: now))
                return Transition(cycle: nil, effects: effects)
            }
            next.state = .break
            next.stateStart = now
        case .stop:
            let elapsed = now.timeIntervalSince(next.stateStart)
            switch next.state {
            case .active:
                effects.append(try next.activeEnded(at: now))
            case .break:
                effects.append(.record(.breakEnded(planned: plan.breakLength, actual: elapsed), at: now))
            case .idle:
                effects.append(.record(.idle(duration: elapsed), at: now))
            }
            effects.append(.record(.cycleEnded(.stopped), at: now))
            return Transition(cycle: nil, effects: effects)
        }
        return Transition(cycle: next, effects: effects)
    }

    /// The log entry for ending the current Active now, which needs no reason once its
    /// planned length is reached.
    private func activeEnded(at now: Date) throws(Rejection) -> Effect {
        let actual = now.timeIntervalSince(stateStart)
        guard actual >= plan.activeLength else { throw .reasonRequired }
        return .record(.activeEnded(planned: plan.activeLength, actual: actual, overtime: overtime(at: now)), at: now)
    }

    /// Ends a Break whose planned length has run out, as of the moment it ran out.
    private mutating func advance(to now: Date) -> [Effect] {
        guard let breakEnd = nextDeadline, now >= breakEnd else { return [] }
        state = .idle
        stateStart = breakEnd
        return [.record(.breakEnded(planned: plan.breakLength, actual: plan.breakLength), at: breakEnd)]
    }
}
