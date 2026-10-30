import Foundation

/// Loads and saves a `Codable` value as a JSON file, falling back to a default value
/// when the file is missing or unreadable (e.g. after a schema change). An unreadable file
/// is moved aside first, so the next save doesn't destroy it.
public struct JSONStore<Value: Codable & Sendable>: Sendable {
    public let url: URL
    private let defaultValue: @Sendable () -> Value

    public init(url: URL, default defaultValue: @escaping @Sendable () -> Value) {
        self.url = url
        self.defaultValue = defaultValue
    }

    public func load() -> Value {
        guard FileManager.default.fileExists(atPath: url.path) else { return defaultValue() }
        do {
            return try Self.decoder.decode(Value.self, from: Data(contentsOf: url))
        } catch {
            setAside(because: error)
            return defaultValue()
        }
    }

    /// Moves the file to `<name>.unreadable-<timestamp>` next to it.
    private func setAside(because error: Error) {
        let timestamp = ISO8601DateFormatter.string(
            from: Date(), timeZone: .gmt, formatOptions: [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        )
        let sideURL = url.deletingLastPathComponent()
            .appending(path: "\(url.lastPathComponent).unreadable-\(timestamp)")
        do {
            try FileManager.default.moveItem(at: url, to: sideURL)
            Log.persistence.error(
                "Set aside unreadable \(url.path, privacy: .public) as \(sideURL.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        } catch let moveError {
            Log.persistence.fault(
                "Couldn't set aside unreadable \(url.path, privacy: .public): \(String(describing: moveError), privacy: .public)"
            )
        }
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Self.encoder.encode(value).write(to: url, options: .atomic)
    }

    /// `~/Library/Application Support/FocusGuard`
    public static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "FocusGuard", directoryHint: .isDirectory)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
