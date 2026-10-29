import Foundation
import Testing
@testable import FocusGuardCore

@Suite("Pomodoro")
struct PomodoroTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let plan = Plan(activeMinutes: 25, breakMinutes: 5, actives: 3)!

    func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }
    func minutes(_ minutes: Double) -> TimeInterval { minutes * 60 }

    @Test func startingAPlannedCycleBeginsTheFirstActive() {
        let transition = PomodoroCycle.start(plan, at: t0)

        let cycle = try! #require(transition.cycle)
        #expect(cycle.state == .active)
        #expect(cycle.activeNumber == 1)
        #expect(cycle.remaining(at: at(10)) == minutes(15))
        #expect(transition.effects == [.record(.cycleStarted(plan: plan), at: t0)])
    }

    @Test func anActivePastItsPlannedLengthRunsInOvertimeSilently() throws {
        let started = try #require(PomodoroCycle.start(plan, at: t0).cycle)

        let transition = try started.handle(.tick, at: at(31))

        let cycle = try #require(transition.cycle)
        #expect(cycle.state == .active)
        #expect(cycle.remaining(at: at(31)) == 0)
        #expect(cycle.overtime(at: at(31)) == minutes(6))
        #expect(cycle.overtime(at: at(20)) == 0)
        #expect(transition.effects.isEmpty)
    }

    @Test func endingAnActiveInOvertimeStartsTheBreak() throws {
        let started = try #require(PomodoroCycle.start(plan, at: t0).cycle)

        let transition = try started.handle(.endActive, at: at(28))

        let cycle = try #require(transition.cycle)
        #expect(cycle.state == .break)
        #expect(cycle.remaining(at: at(28)) == minutes(5))
        #expect(transition.effects == [
            .record(.activeEnded(planned: minutes(25), actual: minutes(28)), at: at(28)),
        ])
    }

    @Test func endingAnActiveBeforeItsPlannedLengthIsRejected() throws {
        let started = try #require(PomodoroCycle.start(plan, at: t0).cycle)

        #expect(throws: PomodoroCycle.Rejection.reasonRequired) {
            try started.handle(.endActive, at: at(24))
        }
    }

    @Test func aBreakEndsOnItsOwnAndTheCycleWaitsInIdle() throws {
        let started = try #require(PomodoroCycle.start(plan, at: t0).cycle)
        let onBreak = try #require(try started.handle(.endActive, at: at(25)).cycle)

        let stillOnBreak = try #require(try onBreak.handle(.tick, at: at(29)).cycle)
        #expect(stillOnBreak.state == .break)

        let transition = try onBreak.handle(.tick, at: at(42))
        let idle = try #require(transition.cycle)
        #expect(idle.state == .idle)
        #expect(idle.remaining(at: at(42)) == nil)
        #expect(transition.effects == [
            .record(.breakEnded(planned: minutes(5), actual: minutes(5)), at: at(30)),
        ])
    }

    @Test func theNextActiveKeepsItsNormalLengthAfterOvertimeAndIdle() throws {
        let started = try #require(PomodoroCycle.start(plan, at: t0).cycle)
        let onBreak = try #require(try started.handle(.endActive, at: at(40)).cycle)
        let idle = try #require(try onBreak.handle(.tick, at: at(45)).cycle)

        let transition = try idle.handle(.startActive, at: at(57))

        let second = try #require(transition.cycle)
        #expect(second.state == .active)
        #expect(second.activeNumber == 2)
        #expect(second.remaining(at: at(57)) == minutes(25))
        #expect(transition.effects == [.record(.idle(duration: minutes(12)), at: at(57))])
    }

    @Test func aFullPlannedCycleEndsWhenItsLastActiveEnds() throws {
        var effects: [PomodoroCycle.Effect] = []
        var cycle = try #require(PomodoroCycle.start(plan, at: t0).cycle)

        func apply(_ input: PomodoroCycle.Input, _ minute: Double) throws -> PomodoroCycle? {
            let transition = try cycle.handle(input, at: at(minute))
            effects += transition.effects
            return transition.cycle
        }

        cycle = try #require(try apply(.endActive, 25))   // Active 1, on time
        cycle = try #require(try apply(.startActive, 32)) // Break 25–30, Idle 30–32
        cycle = try #require(try apply(.endActive, 59))   // Active 2, 2 min of Overtime
        cycle = try #require(try apply(.startActive, 64)) // Break 59–64, no Idle
        #expect(cycle.activeNumber == 3)
        let ended = try apply(.endActive, 89)             // Active 3: no Break after it

        #expect(ended == nil)
        #expect(effects == [
            .record(.activeEnded(planned: minutes(25), actual: minutes(25)), at: at(25)),
            .record(.breakEnded(planned: minutes(5), actual: minutes(5)), at: at(30)),
            .record(.idle(duration: minutes(2)), at: at(32)),
            .record(.activeEnded(planned: minutes(25), actual: minutes(27)), at: at(59)),
            .record(.breakEnded(planned: minutes(5), actual: minutes(5)), at: at(64)),
            .record(.idle(duration: 0), at: at(64)),
            .record(.activeEnded(planned: minutes(25), actual: minutes(25)), at: at(89)),
            .record(.cycleEnded(.completed), at: at(89)),
        ])
    }

    @Test func stopDuringOvertimeEndsTheActiveAndTheCycle() throws {
        let started = try #require(PomodoroCycle.start(plan, at: t0).cycle)

        let transition = try started.handle(.stop, at: at(30))

        #expect(transition.cycle == nil)
        #expect(transition.effects == [
            .record(.activeEnded(planned: minutes(25), actual: minutes(30)), at: at(30)),
            .record(.cycleEnded(.stopped), at: at(30)),
        ])
    }

    @Test func stopDuringABreakCutsItShortAndEndsTheCycle() throws {
        let started = try #require(PomodoroCycle.start(plan, at: t0).cycle)
        let onBreak = try #require(try started.handle(.endActive, at: at(25)).cycle)

        let transition = try onBreak.handle(.stop, at: at(27))

        #expect(transition.cycle == nil)
        #expect(transition.effects == [
            .record(.breakEnded(planned: minutes(5), actual: minutes(2)), at: at(27)),
            .record(.cycleEnded(.stopped), at: at(27)),
        ])
    }

    @Test func stopDuringIdleEndsTheCycle() throws {
        let started = try #require(PomodoroCycle.start(plan, at: t0).cycle)
        let onBreak = try #require(try started.handle(.endActive, at: at(25)).cycle)

        let transition = try onBreak.handle(.stop, at: at(38))

        #expect(transition.cycle == nil)
        #expect(transition.effects == [
            .record(.breakEnded(planned: minutes(5), actual: minutes(5)), at: at(30)),
            .record(.idle(duration: minutes(8)), at: at(38)),
            .record(.cycleEnded(.stopped), at: at(38)),
        ])
    }

    @Test func stopBeforeTheActiveReachesItsPlannedLengthIsRejected() throws {
        let started = try #require(PomodoroCycle.start(plan, at: t0).cycle)

        #expect(throws: PomodoroCycle.Rejection.reasonRequired) {
            try started.handle(.stop, at: at(10))
        }
    }

    @Test func stopExactlyAtThePlannedLengthNeedsNoReason() throws {
        let started = try #require(PomodoroCycle.start(plan, at: t0).cycle)

        let transition = try started.handle(.stop, at: at(25))

        #expect(transition.cycle == nil)
        #expect(transition.effects == [
            .record(.activeEnded(planned: minutes(25), actual: minutes(25)), at: at(25)),
            .record(.cycleEnded(.stopped), at: at(25)),
        ])
    }

    @Test func anActiveCanBeEndedOrStoppedOnceItReachesItsPlannedLength() throws {
        let started = try #require(PomodoroCycle.start(plan, at: t0).cycle)

        #expect(!started.reachedPlannedLength(at: at(24)))
        #expect(!started.canStop(at: at(24)))
        #expect(started.reachedPlannedLength(at: at(25)))
        #expect(started.canStop(at: at(25)))
        #expect(started.canStop(at: at(40)))
    }

    @Test func aBreakOrIdleCanAlwaysBeStopped() throws {
        let started = try #require(PomodoroCycle.start(plan, at: t0).cycle)
        let onBreak = try #require(try started.handle(.endActive, at: at(25)).cycle)
        let idle = try #require(try onBreak.handle(.tick, at: at(31)).cycle)

        #expect(!onBreak.reachedPlannedLength(at: at(26)))
        #expect(onBreak.canStop(at: at(26)))
        #expect(!idle.reachedPlannedLength(at: at(31)))
        #expect(idle.canStop(at: at(31)))
    }

    @Test func onlyTheLastActiveOfThePlanIsTheLast() throws {
        let first = try #require(PomodoroCycle.start(plan, at: t0).cycle)
        let onBreak = try #require(try first.handle(.endActive, at: at(25)).cycle)
        let idle = try #require(try onBreak.handle(.tick, at: at(30)).cycle)
        let second = try #require(try idle.handle(.startActive, at: at(30)).cycle)
        let secondBreak = try #require(try second.handle(.endActive, at: at(55)).cycle)
        let secondIdle = try #require(try secondBreak.handle(.tick, at: at(60)).cycle)
        let third = try #require(try secondIdle.handle(.startActive, at: at(60)).cycle)

        #expect(!first.isLastActive)
        #expect(!second.isLastActive)
        #expect(third.isLastActive)
    }

    @Test func aPlanKnowsItsTotalLength() {
        // 3 Actives of 25 min and the 2 Breaks of 5 min between them.
        #expect(plan.totalLength == minutes(85))
    }

    @Test func onlyABreakHasADeadlineOfItsOwn() throws {
        let started = try #require(PomodoroCycle.start(plan, at: t0).cycle)
        let onBreak = try #require(try started.handle(.endActive, at: at(27)).cycle)
        let idle = try #require(try onBreak.handle(.tick, at: at(40)).cycle)

        #expect(started.nextDeadline == nil)
        #expect(onBreak.nextDeadline == at(32))
        #expect(idle.nextDeadline == nil)
    }

    @Test func aPlanNeedsAtLeastTwoActives() {
        #expect(Plan(activeMinutes: 25, breakMinutes: 5, actives: 1) == nil)
        #expect(Plan(activeMinutes: 25, breakMinutes: 5, actives: 2) != nil)
        #expect(Plan(activeMinutes: 0, breakMinutes: 5, actives: 4) == nil)
    }

    @Test func anActiveCannotStartDuringABreak() throws {
        let started = try #require(PomodoroCycle.start(plan, at: t0).cycle)
        let onBreak = try #require(try started.handle(.endActive, at: at(25)).cycle)

        #expect(throws: PomodoroCycle.Rejection.notAllowed) {
            try onBreak.handle(.startActive, at: at(27))
        }
    }
}
