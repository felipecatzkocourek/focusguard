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

    @Test func cycleEventsSurviveSavingAndLoading() throws {
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

    @Test func aCutShortActiveKnowsItsShortfall() {
        #expect(ActivityEvent.Kind.activeEnded(planned: 1500, actual: 600, reason: "Meeting").shortfall == 900)
        #expect(ActivityEvent.Kind.activeEnded(planned: 1500, actual: 1680).shortfall == 0)
        #expect(ActivityEvent.Kind.breakEnded(planned: 300, actual: 120).shortfall == 0)
    }

    @Test func aPhaseEndedBeforeItsPlannedLengthIsCutShort() {
        #expect(ActivityEvent.Kind.activeEnded(planned: 1500, actual: 600, reason: "Meeting").isCutShort)
        #expect(ActivityEvent.Kind.breakEnded(planned: 300, actual: 120).isCutShort)
        #expect(!ActivityEvent.Kind.activeEnded(planned: 1500, actual: 1500).isCutShort)
        #expect(!ActivityEvent.Kind.activeEnded(planned: 1500, actual: 1680).isCutShort)
        #expect(!ActivityEvent.Kind.breakEnded(planned: 300, actual: 300).isCutShort)
        #expect(!ActivityEvent.Kind.idle(duration: 60).isCutShort)
    }

    @Test func aCutShortReasonSurvivesSavingAndLoading() throws {
        var log = ActivityLog()
        log.record(.activeEnded(planned: 1500, actual: 600, reason: "Meeting moved up"), at: date(9, 10))

        let decoded = try JSONDecoder().decode(ActivityLog.self, from: JSONEncoder().encode(log))
        #expect(decoded == log)
    }

    @Test func anEndedActiveLoggedBeforeReasonsExistedStillLoads() throws {
        let json = """
        {"events":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":0,
                    "kind":{"activeEnded":{"planned":1500,"actual":1680}}}]}
        """
        let log = try JSONDecoder().decode(ActivityLog.self, from: Data(json.utf8))

        #expect(log.events.map(\.kind) == [.activeEnded(planned: 1500, actual: 1680, reason: nil)])
    }

    @Test func anEndedActiveKnowsItsOvertime() {
        #expect(ActivityEvent.Kind.activeEnded(planned: 1500, actual: 1680).overtime == 180)
        #expect(ActivityEvent.Kind.activeEnded(planned: 1500, actual: 1500).overtime == 0)
        #expect(ActivityEvent.Kind.breakEnded(planned: 300, actual: 360).overtime == 0)
    }

    @Test func logsWrittenBeforeCycleEventsStillDecode() throws {
        let json = """
        {"events":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":800000000,
        "kind":{"allowanceGranted":{"domain":"youtube.com","reason":"tutorial","minutes":15}}}]}
        """
        let log = try JSONDecoder().decode(ActivityLog.self, from: Data(json.utf8))
        #expect(log.events.map(\.kind) == [.allowanceGranted(domain: "youtube.com", reason: "tutorial", minutes: 15)])
    }

    /// Two well-formed events around an unknown kind (from a newer build) and a known kind
    /// whose payload doesn't match this build.
    static let mixedLogJSON = """
    {"events":[
    {"id":"00000000-0000-0000-0000-000000000001","date":800000000,"kind":{"sessionStarted":{"focus":"Work"}}},
    {"id":"00000000-0000-0000-0000-000000000002","date":800000060,"kind":{"teleported":{"to":"Mars"}}},
    {"id":"00000000-0000-0000-0000-000000000003","date":800000120,"kind":{"idle":{"seconds":30}}},
    {"id":"00000000-0000-0000-0000-000000000004","date":800000180,"kind":{"sessionEnded":{}}}
    ]}
    """

    @Test func skipsEventsThisBuildCantDecode() throws {
        let log = try JSONDecoder().decode(ActivityLog.self, from: Data(Self.mixedLogJSON.utf8))
        #expect(log.events.map(\.kind) == [.sessionStarted(focus: "Work"), .sessionEnded])
    }

    @Test func reportsEverySkippedEvent() throws {
        let log = try JSONDecoder().decode(ActivityLog.self, from: Data(Self.mixedLogJSON.utf8))
        #expect(log.skipped.count == 2)
        #expect(log.skipped[0].json.contains("teleported"))
        #expect(log.skipped[0].json.contains("00000000-0000-0000-0000-000000000002"))
        #expect(log.skipped[1].json.contains("\"seconds\":30"))
        #expect(log.skipped.allSatisfy { !$0.error.isEmpty })
    }

    @Test func skippedEventsAreNotSavedBack() throws {
        let log = try JSONDecoder().decode(ActivityLog.self, from: Data(Self.mixedLogJSON.utf8))
        let resaved = try JSONDecoder().decode(ActivityLog.self, from: JSONEncoder().encode(log))
        #expect(resaved.events == log.events)
        #expect(resaved.skipped.isEmpty)
    }

    @Test func dropsEventsOlderThanRetention() {
        var log = ActivityLog()
        log.record(.sessionStarted(focus: "Work"), at: date(9, day: 1).addingTimeInterval(-40 * 24 * 3600))
        log.record(.sessionStarted(focus: "Work"), at: date(9))
        #expect(log.events.count == 1)
    }
}
