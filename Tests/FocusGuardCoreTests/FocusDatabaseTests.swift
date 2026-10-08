import Foundation
import Testing
@testable import FocusGuardCore

@Suite("FocusDatabase")
struct FocusDatabaseTests {
    /// Trimmed-down copies of the files macOS writes in ~/Library/DoNotDisturb/DB.
    let assertionsWithWork = Data("""
    {
      "data": [{
        "storeAssertionRecords": [{
          "assertionUUID": "8B1E7A2C-0000-0000-0000-000000000001",
          "assertionStartDateTimestamp": 781000000.5,
          "assertionSource": { "assertionClientIdentifier": "com.apple.controlcenter" },
          "assertionDetails": {
            "assertionDetailsIdentifier": "com.apple.controlcenter.user-action",
            "assertionDetailsModeIdentifier": "com.apple.focus.work",
            "assertionDetailsReason": "user-action"
          }
        }],
        "storeInvalidationRecords": []
      }],
      "header": { "timestamp": 781000000.5, "version": 3 }
    }
    """.utf8)

    let assertionsNone = Data("""
    { "data": [{ "storeInvalidationRecords": [] }], "header": { "version": 3 } }
    """.utf8)

    let modeConfigurations = Data("""
    {
      "data": [{
        "modeConfigurations": {
          "com.apple.focus.work": {
            "mode": { "name": "Work", "modeIdentifier": "com.apple.focus.work", "symbolImageName": "briefcase.fill" }
          },
          "com.apple.focus.personal-time": {
            "mode": { "name": "Personal", "modeIdentifier": "com.apple.focus.personal-time" }
          },
          "com.apple.sleep.sleep-mode": {
            "mode": { "name": "Sleep", "modeIdentifier": "com.apple.sleep.sleep-mode" }
          }
        }
      }],
      "header": { "version": 3 }
    }
    """.utf8)

    @Test func readsActiveMode() throws {
        #expect(try FocusDatabase.activeModeIdentifier(assertionsJSON: assertionsWithWork) == "com.apple.focus.work")
    }

    @Test func noAssertionsMeansNoFocus() throws {
        #expect(try FocusDatabase.activeModeIdentifier(assertionsJSON: assertionsNone) == nil)
    }

    @Test func mostRecentAssertionWins() throws {
        let json = Data("""
        { "data": [{ "storeAssertionRecords": [
          { "assertionStartDateTimestamp": 100, "assertionDetails": { "assertionDetailsModeIdentifier": "com.apple.focus.work" } },
          { "assertionStartDateTimestamp": 200, "assertionDetails": { "assertionDetailsModeIdentifier": "com.apple.focus.personal-time" } }
        ] }] }
        """.utf8)
        #expect(try FocusDatabase.activeModeIdentifier(assertionsJSON: json) == "com.apple.focus.personal-time")
    }

    @Test func rejectsGarbage() {
        #expect(throws: FocusDatabase.ParseError.notJSON) {
            try FocusDatabase.activeModeIdentifier(assertionsJSON: Data("not json".utf8))
        }
        #expect(throws: FocusDatabase.ParseError.unexpectedFormat) {
            try FocusDatabase.activeModeIdentifier(assertionsJSON: Data("{\"something\": 1}".utf8))
        }
    }

    @Test func listsModesSortedByName() throws {
        let modes = try FocusDatabase.modes(modeConfigurationsJSON: modeConfigurations)
        #expect(modes.map(\.name) == ["Personal", "Sleep", "Work"])
        #expect(modes.first?.id == "com.apple.focus.personal-time")
    }

    @Test func modesRejectsUnexpectedLayout() {
        #expect(throws: FocusDatabase.ParseError.unexpectedFormat) {
            try FocusDatabase.modes(modeConfigurationsJSON: Data("{\"data\": []}".utf8))
        }
    }
}

@Suite("Triggers")
struct TriggerTests {
    @Test func blocksOnlyForTriggerModes() {
        let config = Configuration(triggerFocusIdentifiers: ["com.apple.focus.personal-time"])
        #expect(config.shouldBlock(activeFocusIdentifier: "com.apple.focus.personal-time"))
        #expect(!config.shouldBlock(activeFocusIdentifier: "com.apple.focus.work"))
        #expect(!config.shouldBlock(activeFocusIdentifier: nil))
    }

    @Test func oldConfigWithoutTriggersKeepsSites() throws {
        let json = Data("""
        { "blockedDomains": ["reddit.com"], "friction": { "countdownSeconds": 30, "requiresReason": false, "defaultDurationMinutes": 5 } }
        """.utf8)
        let config = try JSONDecoder().decode(Configuration.self, from: json)
        #expect(config.blockedDomains == ["reddit.com"])
        #expect(config.friction.countdownSeconds == 30)
        #expect(config.triggerFocusIdentifiers == Configuration.defaultTriggerFocusIdentifiers)
    }
}
