import Foundation
import Testing
@testable import FocusGuardCore

@Suite("JSONStore")
struct JSONStoreTests {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "JSONStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var url: URL { directory.appending(path: "activity.json") }
    var store: JSONStore<ActivityLog> { JSONStore(url: url) { ActivityLog() } }

    func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    @Test func aMissingFileLoadsTheDefaultAndCreatesNoSideFile() throws {
        #expect(store.load().events.isEmpty)
        #expect(try files().isEmpty)
    }

    @Test func anUnreadableFileIsSetAsideBeforeLoadingTheDefault() throws {
        let corrupt = Data("{\"events\": [oops".utf8)
        try corrupt.write(to: url)

        #expect(store.load().events.isEmpty)
        let sideFiles = try files().filter { $0.hasPrefix("activity.json.unreadable-") }
        #expect(sideFiles.count == 1)
        #expect(try Data(contentsOf: directory.appending(path: sideFiles[0])) == corrupt)

        var log = ActivityLog()
        log.record(.sessionEnded, at: Date())
        try store.save(log)
        #expect(try Data(contentsOf: directory.appending(path: sideFiles[0])) == corrupt)
    }

    @Test func aLogWithEventsThisBuildCantDecodeKeepsTheRestAndSavesOnlyThem() throws {
        try Data("""
        {"events":[
        {"id":"00000000-0000-0000-0000-000000000001","date":"2026-10-08T09:00:00Z","kind":{"sessionStarted":{"focus":"Work"}}},
        {"id":"00000000-0000-0000-0000-000000000002","date":"2026-10-08T09:01:00Z","kind":{"teleported":{"to":"Mars"}}},
        {"id":"00000000-0000-0000-0000-000000000003","date":"2026-10-08T09:02:00Z","kind":{"sessionEnded":{}}}
        ]}
        """.utf8).write(to: url)

        let log = store.load()
        #expect(log.events.map(\.kind) == [.sessionStarted(focus: "Work"), .sessionEnded])
        #expect(log.skipped.count == 1)
        #expect(try files() == ["activity.json"])

        try store.save(log)
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(!saved.contains("teleported"))
        #expect(store.load().events == log.events)
    }

    /// Byte for byte what v0.1.0's `JSONStore` writes for an `ActivityLog`.
    static let currentReleaseActivityJSON = """
    {
      "events" : [
        {
          "date" : "2026-10-08T09:00:00Z",
          "id" : "00000000-0000-0000-0000-000000000001",
          "kind" : {
            "sessionStarted" : {
              "focus" : "Work"
            }
          }
        },
        {
          "date" : "2026-10-08T09:05:00Z",
          "id" : "00000000-0000-0000-0000-000000000002",
          "kind" : {
            "allowanceGranted" : {
              "domain" : "youtube.com",
              "minutes" : 15,
              "reason" : "tutorial"
            }
          }
        },
        {
          "date" : "2026-10-08T10:00:00Z",
          "id" : "00000000-0000-0000-0000-000000000003",
          "kind" : {
            "sessionEnded" : {

            }
          }
        }
      ]
    }
    """

    @Test func anActivityFileFromTheCurrentReleaseLoadsAndSavesUnchanged() throws {
        try Data(Self.currentReleaseActivityJSON.utf8).write(to: url)

        let log = store.load()
        #expect(log.events.map(\.kind) == [
            .sessionStarted(focus: "Work"),
            .allowanceGranted(domain: "youtube.com", reason: "tutorial", minutes: 15),
            .sessionEnded,
        ])
        #expect(log.skipped.isEmpty)

        try store.save(log)
        #expect(try String(contentsOf: url, encoding: .utf8) == Self.currentReleaseActivityJSON)
    }
}
