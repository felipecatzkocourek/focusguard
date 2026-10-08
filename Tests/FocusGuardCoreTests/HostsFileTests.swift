import Testing
@testable import FocusGuardCore

@Suite("HostsFile")
struct HostsFileTests {
    /// A realistic hosts file that already contains another tool's managed section.
    let original = """
    ##
    # Host Database
    ##
    127.0.0.1\tlocalhost
    255.255.255.255\tbroadcasthost
    ::1             localhost

    # Added by SomeLauncher
    0.0.0.0 telemetry.example.com
    # End of section

    """

    @Test func addsSectionAndKeepsEverythingElse() {
        let result = HostsFile.applying(blockedHostnames: ["youtube.com"], to: original)

        #expect(result.hasPrefix(original.trimmingCharacters(in: .newlines)))
        #expect(result.contains("0.0.0.0 telemetry.example.com"))
        #expect(result.contains("0.0.0.0 youtube.com\n:: youtube.com"))
        #expect(result.hasSuffix(HostsFile.endMarker + "\n"))
    }

    @Test func replacesExistingSectionInsteadOfDuplicating() {
        let first = HostsFile.applying(blockedHostnames: ["youtube.com"], to: original)
        let second = HostsFile.applying(blockedHostnames: ["instagram.com"], to: first)

        #expect(second.components(separatedBy: HostsFile.beginMarker).count == 2)
        #expect(!second.contains("youtube.com"))
        #expect(second.contains("0.0.0.0 instagram.com"))
    }

    @Test func emptyListRemovesSectionAndRestoresOriginal() {
        let blocked = HostsFile.applying(blockedHostnames: ["youtube.com"], to: original)
        let cleared = HostsFile.applying(blockedHostnames: [], to: blocked)

        #expect(cleared == original)
        #expect(!cleared.contains(HostsFile.beginMarker))
    }

    @Test func isIdempotent() {
        let once = HostsFile.applying(blockedHostnames: ["a.com", "b.com"], to: original)
        let twice = HostsFile.applying(blockedHostnames: ["b.com", "a.com", "a.com"], to: once)
        #expect(once == twice)
    }

    @Test func parsesBlockedHostnames() {
        let blocked = HostsFile.applying(blockedHostnames: ["www.youtube.com", "youtube.com"], to: original)
        #expect(HostsFile.blockedHostnames(in: blocked) == ["www.youtube.com", "youtube.com"])
        #expect(HostsFile.blockedHostnames(in: original).isEmpty)
    }

    @Test func handlesFileWithoutTrailingNewline() {
        let result = HostsFile.applying(blockedHostnames: ["x.com"], to: "127.0.0.1 localhost")
        #expect(result == "127.0.0.1 localhost\n\n\(HostsFile.beginMarker)\n0.0.0.0 x.com\n:: x.com\n\(HostsFile.endMarker)\n")
    }
}
