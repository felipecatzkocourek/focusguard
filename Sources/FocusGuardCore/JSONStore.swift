import Foundation

/// Loads and saves a `Codable` value as a JSON file, falling back to a default value
/// when the file is missing or unreadable (e.g. after a schema change).
public struct JSONStore<Value: Codable & Sendable>: Sendable {
    public let url: URL
    private let defaultValue: @Sendable () -> Value

    public init(url: URL, default defaultValue: @escaping @Sendable () -> Value) {
        self.url = url
        self.defaultValue = defaultValue
    }

    public func load() -> Value {
        guard let data = try? Data(contentsOf: url),
              let value = try? Self.decoder.decode(Value.self, from: data)
        else { return defaultValue() }
        return value
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
