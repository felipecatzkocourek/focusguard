import Foundation
import Testing
@testable import FocusGuardCore

@Suite("BlockState")
struct BlockStateTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let plan = Plan(activeMinutes: 25, breakMinutes: 5, actives: 3)!

    func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }
    func minutes(_ minutes: Double) -> TimeInterval { minutes * 60 }

    @Test func aCycleLeftOpenIsClosedByTheSystemWhenLastSeen() throws {
        var state = BlockState(isBlocking: true)
        state.cycle = PomodoroCycle.start(plan, at: t0).cycle
        state.cycleSeenAt = at(12)

        let effects = state.closeLeftoverCycle()

        #expect(effects == [
            .record(.activeEnded(planned: minutes(25), actual: minutes(12)), at: at(12)),
            .record(.cycleEnded(.system), at: at(12)),
        ])
        #expect(state.cycle == nil)
        #expect(state.cycleSeenAt == nil)
        #expect(state.isBlocking)
    }

    @Test func withNoCycleLeftOpenThereIsNothingToClose() {
        var state = BlockState(isBlocking: true)

        let effects = state.closeLeftoverCycle()
        #expect(effects.isEmpty)
    }

    @Test func settingTheRunningCycleMarksItSeenThen() throws {
        var state = BlockState()
        let cycle = try #require(PomodoroCycle.start(plan, at: t0).cycle)

        state.setCycle(cycle, at: at(2))

        #expect(state.cycle == cycle)
        #expect(state.cycleSeenAt == at(2))
    }

    @Test func clearingTheCycleForgetsWhenItWasSeen() {
        var state = BlockState()
        state.setCycle(PomodoroCycle.start(plan, at: t0).cycle, at: t0)

        state.setCycle(nil, at: at(5))

        #expect(state.cycle == nil)
        #expect(state.cycleSeenAt == nil)
    }

    @Test func aRunningCycleIsMarkedSeenAtMostOnceAMinute() {
        var state = BlockState()
        state.cycle = PomodoroCycle.start(plan, at: t0).cycle
        state.cycleSeenAt = t0

        let movedEarly = state.markCycleSeen(at: at(0.5))
        #expect(!movedEarly)
        #expect(state.cycleSeenAt == t0)

        let movedAfterAMinute = state.markCycleSeen(at: at(1))
        #expect(movedAfterAMinute)
        #expect(state.cycleSeenAt == at(1))
    }

    @Test func withNoCycleThereIsNothingToMarkSeen() {
        var state = BlockState()

        let moved = state.markCycleSeen(at: at(5))
        #expect(!moved)
        #expect(state.cycleSeenAt == nil)
    }

    @Test func aRunningCycleSurvivesSavingAndLoading() throws {
        var state = BlockState(isBlocking: true)
        state.cycle = PomodoroCycle.start(plan, at: t0).cycle
        state.cycleSeenAt = at(3)

        let decoded = try JSONDecoder().decode(BlockState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }

    @Test func stateSavedBeforeCyclesExistedStillLoads() throws {
        let json = #"{"isBlocking":true,"allowances":[]}"#

        let state = try JSONDecoder().decode(BlockState.self, from: Data(json.utf8))
        #expect(state == BlockState(isBlocking: true))
    }
}
