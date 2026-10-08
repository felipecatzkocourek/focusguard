import Compression
import Foundation
import Testing
@testable import FocusGuardCore

@Suite("FirefoxSession")
struct FirefoxSessionTests {
    let session = Data("""
    {
      "windows": [
        { "tabs": [
          { "index": 2, "entries": [
            { "url": "https://www.google.com/search?q=swiftui" },
            { "url": "https://www.youtube.com/watch?v=abc" }
          ] },
          { "index": 1, "entries": [ { "url": "https://developer.apple.com/documentation" } ] }
        ] },
        { "tabs": [
          { "entries": [ { "url": "about:newtab" }, { "url": "https://chess.com/play" } ] },
          { "index": 1, "entries": [] }
        ] }
      ]
    }
    """.utf8)

    /// Builds a mozLz4 file the same way Firefox does.
    func mozLz4(_ payload: Data) -> Data {
        var compressed = Data(count: payload.count + 1024)
        let count = compressed.withUnsafeMutableBytes { dst in
            payload.withUnsafeBytes { src in
                compression_encode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, dst.count,
                    src.bindMemory(to: UInt8.self).baseAddress!, payload.count,
                    nil, COMPRESSION_LZ4_RAW
                )
            }
        }
        var size = UInt32(payload.count).littleEndian
        return FirefoxSession.magic + Data(bytes: &size, count: 4) + compressed.prefix(count)
    }

    @Test func roundTripsMozLz4() throws {
        #expect(try FirefoxSession.decompressMozLz4(mozLz4(session)) == session)
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: FirefoxSession.DecodeError.notMozLz4) {
            try FirefoxSession.decompressMozLz4(Data("{\"windows\":[]}".utf8))
        }
    }

    @Test func readsCurrentURLOfEveryTab() throws {
        let urls = try FirefoxSession.openTabURLs(sessionJSON: session).map(\.absoluteString)
        #expect(urls == [
            "https://www.youtube.com/watch?v=abc",
            "https://developer.apple.com/documentation",
            "https://chess.com/play",
        ])
    }

    @Test func findsOpenBlockedHosts() throws {
        let urls = try FirefoxSession.openTabURLs(sessionJSON: session)
        let blocked = Set(Domain.hostnames(for: "youtube.com") + Domain.hostnames(for: "instagram.com"))
        #expect(FirefoxSession.openBlockedHostnames(in: urls, blocked: blocked) == ["www.youtube.com"])
    }
}
