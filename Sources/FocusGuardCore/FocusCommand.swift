import Foundation

/// Commands delivered to the app through its URL scheme, typically by a Shortcuts
/// automation that runs when the Work Focus turns on or off:
///
///     focusguard://work/on
///     focusguard://work/off
public enum FocusCommand: Equatable, Sendable {
    case workOn
    case workOff

    public static let scheme = "focusguard"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              url.host()?.lowercased() == "work"
        else { return nil }

        switch url.path().lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
        case "on": self = .workOn
        case "off": self = .workOff
        default: return nil
        }
    }

    public var url: URL {
        switch self {
        case .workOn: URL(string: "\(Self.scheme)://work/on")!
        case .workOff: URL(string: "\(Self.scheme)://work/off")!
        }
    }
}
