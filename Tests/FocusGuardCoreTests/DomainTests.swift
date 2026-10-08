import Testing
@testable import FocusGuardCore

@Suite("Domain")
struct DomainTests {
    @Test("Normalizes the many ways people type a site", arguments: [
        ("youtube.com", "youtube.com"),
        ("YouTube.com", "youtube.com"),
        ("  instagram.com  ", "instagram.com"),
        ("www.youtube.com", "youtube.com"),
        ("m.youtube.com", "youtube.com"),
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "youtube.com"),
        ("http://instagram.com:443/explore#top", "instagram.com"),
        ("user:pass@reddit.com", "reddit.com"),
        ("news.ycombinator.com", "news.ycombinator.com"),
        ("example.com.", "example.com"),
    ])
    func normalize(input: String, expected: String) {
        #expect(Domain.normalize(input) == expected)
    }

    @Test("Rejects input that is not a hostname", arguments: [
        "", "   ", "youtube", "localhost", "-bad.com", "bad-.com", "bad..com",
        "has space.com", "127.0.0.1", "example.c0m", "ex_ample.com",
        "evil.com\n0.0.0.0 apple.com", "ünïcode.com",
    ])
    func rejectsInvalid(input: String) {
        #expect(Domain.normalize(input) == nil)
    }

    @Test func rejectsOverlongLabels() {
        let label = String(repeating: "a", count: 64)
        #expect(!Domain.isValidHostname("\(label).com"))
        #expect(Domain.isValidHostname("\(label.dropLast()).com"))
    }

    @Test func expandsVariants() {
        #expect(Domain.hostnames(for: "youtube.com") == ["youtube.com", "www.youtube.com", "m.youtube.com"])
    }
}
