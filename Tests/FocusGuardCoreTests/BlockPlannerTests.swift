import Foundation
import Testing
@testable import FocusGuardCore

@Suite("BlockPlanner")
struct BlockPlannerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let config = Configuration(blockedDomains: ["instagram.com", "youtube.com"])

    @Test func blocksNothingWhenWorkIsOff() {
        let state = BlockState(isWorkActive: false)
        #expect(BlockPlanner.hostnamesToBlock(configuration: config, state: state, at: now).isEmpty)
    }

    @Test func blocksAllVariantsWhenWorkIsOn() {
        let state = BlockState(isWorkActive: true)
        let hosts = BlockPlanner.hostnamesToBlock(configuration: config, state: state, at: now)
        #expect(hosts == [
            "instagram.com", "m.instagram.com", "m.youtube.com",
            "www.instagram.com", "www.youtube.com", "youtube.com",
        ])
    }

    @Test func activeAllowanceUnblocksOnlyThatDomain() {
        let allowance = Allowance(domain: "youtube.com", reason: "tutorial", start: now, minutes: 15)
        let state = BlockState(isWorkActive: true, allowances: [allowance])

        let hosts = BlockPlanner.hostnamesToBlock(configuration: config, state: state, at: now.addingTimeInterval(60))
        #expect(!hosts.contains("youtube.com"))
        #expect(hosts.contains("instagram.com"))
    }

    @Test func expiredAllowanceBlocksAgain() {
        let allowance = Allowance(domain: "youtube.com", reason: "tutorial", start: now, minutes: 15)
        let state = BlockState(isWorkActive: true, allowances: [allowance])

        let later = now.addingTimeInterval(15 * 60)
        #expect(BlockPlanner.hostnamesToBlock(configuration: config, state: state, at: later).contains("youtube.com"))
    }

    @Test func nextChangeIsEarliestExpiry() {
        let a = Allowance(domain: "youtube.com", reason: "", start: now, minutes: 30)
        let b = Allowance(domain: "instagram.com", reason: "", start: now, minutes: 5)
        let state = BlockState(isWorkActive: true, allowances: [a, b])

        #expect(BlockPlanner.nextChange(state: state, at: now) == b.expires)
        #expect(BlockPlanner.nextChange(state: BlockState(isWorkActive: false, allowances: [a]), at: now) == nil)
    }

    @Test func pruneRemovesOnlyExpired() {
        let short = Allowance(domain: "a.com", reason: "", start: now, minutes: 5)
        let long = Allowance(domain: "b.com", reason: "", start: now, minutes: 30)
        var state = BlockState(isWorkActive: true, allowances: [short, long])

        let expired = state.pruneExpiredAllowances(at: now.addingTimeInterval(10 * 60))
        #expect(expired == [short])
        #expect(state.allowances == [long])
    }
}

@Suite("Configuration")
struct ConfigurationTests {
    @Test func addDomainNormalizesAndDeduplicates() {
        var config = Configuration(blockedDomains: [])
        #expect(config.addDomain("https://www.Reddit.com/r/swift") == "reddit.com")
        #expect(config.addDomain("reddit.com") == "reddit.com")
        #expect(config.blockedDomains == ["reddit.com"])
    }

    @Test func addDomainRejectsGarbage() {
        var config = Configuration(blockedDomains: [])
        #expect(config.addDomain("not a site") == nil)
        #expect(config.blockedDomains.isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONStore(url: dir.appending(path: "config.json")) { Configuration() }

        var config = Configuration()
        config.friction.countdownSeconds = 90
        try store.save(config)
        #expect(store.load() == config)
    }

    @Test func missingFileFallsBackToDefault() {
        let store = JSONStore(url: URL(filePath: "/nonexistent/config.json")) { Configuration() }
        #expect(store.load() == Configuration())
    }
}
