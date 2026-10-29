import Foundation
import Testing
@testable import FocusGuardCore

@Suite("ActivityLog")
struct ActivityLogTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func date(_ hour: Int, _ minute: Int = 0, day: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func sumsClosedSessions() {
        var log = ActivityLog()
        log.record(.sessionStarted(focus: "Work"), at: date(9))
        log.record(.sessionEnded, at: date(11))
        log.record(.sessionStarted(focus: "Work"), at: date(14))
        log.record(.sessionEnded, at: date(14, 30))

        #expect(log.blockingDuration(onDayOf: date(20), calendar: calendar) == 2.5 * 3600)
    }

    @Test func countsOngoingSessionUpToNow() {
        var log = ActivityLog()
        log.record(.sessionStarted(focus: "Work"), at: date(9))
        #expect(log.blockingDuration(onDayOf: date(10, 15), calendar: calendar) == 1.25 * 3600)
    }

    @Test func clipsSessionsThatCrossMidnight() {
        var log = ActivityLog()
        log.record(.sessionStarted(focus: "Work"), at: date(23, day: 7))
        log.record(.sessionEnded, at: date(1, day: 8))
        #expect(log.blockingDuration(onDayOf: date(12), calendar: calendar) == 3600)
    }

    @Test func ignoresDuplicateStarts() {
        var log = ActivityLog()
        log.record(.sessionStarted(focus: "Work"), at: date(9))
        log.record(.sessionStarted(focus: "Work"), at: date(10))
        log.record(.sessionEnded, at: date(11))
        #expect(log.blockingDuration(onDayOf: date(12), calendar: calendar) == 2 * 3600)
    }

    @Test func filtersEventsByDay() {
        var log = ActivityLog()
        log.record(.sessionStarted(focus: "Work"), at: date(9, day: 7))
        log.record(.allowanceGranted(domain: "youtube.com", reason: "tutorial", minutes: 15), at: date(10))
        #expect(log.events(on: date(12), calendar: calendar).count == 1)
    }

    @Test func pomodoroEventsSurviveSavingAndLoading() throws {
        var log = ActivityLog()
        log.record(.cycleStarted(plan: Plan(activeMinutes: 25, breakMinutes: 5, actives: 4)!), at: date(9))
        log.record(.activeEnded(planned: 1500, actual: 1680), at: date(9, 28))
        log.record(.breakEnded(planned: 300, actual: 300), at: date(9, 33))
        log.record(.idle(duration: 120), at: date(9, 35))
        log.record(.cycleEnded(.stopped), at: date(9, 40))

        let decoded = try JSONDecoder().decode(ActivityLog.self, from: JSONEncoder().encode(log))
        #expect(decoded == log)
        #expect(decoded.events(on: date(12), calendar: calendar).count == 5)
    }

    @Test func anEndedActiveKnowsItsOvertime() {
        #expect(ActivityEvent.Kind.activeEnded(planned: 1500, actual: 1680).overtime == 180)
        #expect(ActivityEvent.Kind.activeEnded(planned: 1500, actual: 1500).overtime == 0)
        #expect(ActivityEvent.Kind.breakEnded(planned: 300, actual: 360).overtime == 0)
    }

    @Test func logsWrittenBeforeThePomodoroStillDecode() throws {
        let json = """
        {"events":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":800000000,
        "kind":{"allowanceGranted":{"domain":"youtube.com","reason":"tutorial","minutes":15}}}]}
        """
        let log = try JSONDecoder().decode(ActivityLog.self, from: Data(json.utf8))
        #expect(log.events.map(\.kind) == [.allowanceGranted(domain: "youtube.com", reason: "tutorial", minutes: 15)])
    }

    @Test func dropsEventsOlderThanRetention() {
        var log = ActivityLog()
        log.record(.sessionStarted(focus: "Work"), at: date(9, day: 1).addingTimeInterval(-40 * 24 * 3600))
        log.record(.sessionStarted(focus: "Work"), at: date(9))
        #expect(log.events.count == 1)
    }
}
