import Compression
import Foundation

/// Reads Firefox's saved session to find out which sites are open in tabs.
///
/// Firefox can't be asked to close tabs by other apps (it has no AppleScript support
/// for tabs), but it continuously saves its open windows to
/// `sessionstore-backups/recovery.jsonlz4` in the profile. That file is JSON compressed
/// with Mozilla's "mozLz4" container: an 8-byte magic, a little-endian UInt32 with the
/// decompressed size, then a raw LZ4 block.
public enum FirefoxSession {
    public enum DecodeError: Error, Equatable {
        case notMozLz4
        case decompressionFailed
        case notJSON
    }

    static let magic = Data("mozLz40\0".utf8)

    public static func decompressMozLz4(_ data: Data) throws -> Data {
        guard data.count > 12, data.prefix(8) == magic else { throw DecodeError.notMozLz4 }
        let size = data.subdata(in: 8..<12).withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard size > 0, size < 512 * 1024 * 1024 else { throw DecodeError.decompressionFailed }

        let compressed = data.subdata(in: 12..<data.count)
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { dst in
            compressed.withUnsafeBytes { src in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, size,
                    src.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
                    nil, COMPRESSION_LZ4_RAW
                )
            }
        }
        guard written == size else { throw DecodeError.decompressionFailed }
        return output
    }

    /// The URL currently shown in each open tab (the entry at the tab's history index).
    public static func openTabURLs(sessionJSON data: Data) throws -> [URL] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodeError.notJSON
        }
        var urls: [URL] = []
        for window in (root["windows"] as? [[String: Any]]) ?? [] {
            for tab in (window["tabs"] as? [[String: Any]]) ?? [] {
                guard let entries = tab["entries"] as? [[String: Any]], !entries.isEmpty else { continue }
                // `index` is 1-based; fall back to the last entry if it's missing or odd.
                let index = min(max(((tab["index"] as? Int) ?? entries.count) - 1, 0), entries.count - 1)
                if let string = entries[index]["url"] as? String, let url = URL(string: string) {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    /// Hostnames from `blocked` that are open in at least one tab.
    public static func openBlockedHostnames(in urls: [URL], blocked: Set<String>) -> Set<String> {
        Set(urls.compactMap { $0.host()?.lowercased() }.filter(blocked.contains))
    }
}
