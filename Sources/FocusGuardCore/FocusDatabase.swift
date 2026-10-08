import Foundation

/// A Focus mode configured on this Mac (Work, Personal, Sleep, or a custom one).
public struct FocusMode: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Stable identifier, e.g. `com.apple.focus.work`.
    public var id: String
    /// Display name as shown in Control Center, e.g. "Work".
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Reads macOS's Focus database in `~/Library/DoNotDisturb/DB`.
///
/// Apple doesn't offer a public API that tells an app *which* Focus is on, so FocusGuard
/// reads the same JSON files Control Center writes. Those files are protected by
/// Full Disk Access and their format is undocumented, so parsing is deliberately
/// defensive: it searches for the keys it needs instead of assuming an exact layout,
/// and an unexpected layout produces a clear error instead of a wrong answer.
public enum FocusDatabase {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/DoNotDisturb/DB", directoryHint: .isDirectory)
    }

    public static var assertionsURL: URL { directory.appending(path: "Assertions.json") }
    public static var modeConfigurationsURL: URL { directory.appending(path: "ModeConfigurations.json") }

    public enum ParseError: Error, Equatable {
        case notJSON
        case unexpectedFormat
    }

    /// The identifier of the Focus that is currently on, or `nil` if none is.
    ///
    /// Each active Focus is an "assertion" record. If several are present (rare), the
    /// most recently started one wins, matching what Control Center shows.
    public static func activeModeIdentifier(assertionsJSON data: Data) throws -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { throw ParseError.notJSON }
        guard let dict = root as? [String: Any], dict["data"] != nil else { throw ParseError.unexpectedFormat }

        var best: (identifier: String, start: Double)?
        for record in findAll(key: "storeAssertionRecords", in: dict).flatMap({ ($0 as? [Any]) ?? [] }) {
            guard let record = record as? [String: Any],
                  let identifier = findAll(key: "assertionDetailsModeIdentifier", in: record).first as? String
            else { continue }
            let start = (record["assertionStartDateTimestamp"] as? Double) ?? 0
            if best == nil || start >= best!.start {
                best = (identifier, start)
            }
        }
        return best?.identifier
    }

    /// All Focus modes configured on this Mac, sorted by name.
    public static func modes(modeConfigurationsJSON data: Data) throws -> [FocusMode] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { throw ParseError.notJSON }
        guard let dict = root as? [String: Any] else { throw ParseError.unexpectedFormat }

        let configurations = findAll(key: "modeConfigurations", in: dict).compactMap { $0 as? [String: Any] }
        guard !configurations.isEmpty else { throw ParseError.unexpectedFormat }

        var modes: [String: FocusMode] = [:]
        for configuration in configurations {
            for (key, value) in configuration {
                guard let entry = value as? [String: Any], let mode = entry["mode"] as? [String: Any] else { continue }
                let identifier = (mode["modeIdentifier"] as? String) ?? key
                let name = (mode["name"] as? String) ?? identifier
                modes[identifier] = FocusMode(id: identifier, name: name)
            }
        }
        return modes.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Depth-first search for every value stored under `key`, at any nesting level.
    static func findAll(key: String, in object: Any) -> [Any] {
        var results: [Any] = []
        if let dict = object as? [String: Any] {
            for (k, v) in dict {
                if k == key { results.append(v) }
                results += findAll(key: key, in: v)
            }
        } else if let array = object as? [Any] {
            for element in array { results += findAll(key: key, in: element) }
        }
        return results
    }
}
