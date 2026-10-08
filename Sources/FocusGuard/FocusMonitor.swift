import FocusGuardCore
import Foundation

/// What FocusGuard currently knows about the system's Focus.
struct FocusSnapshot: Equatable, Sendable {
    enum Access: Equatable, Sendable {
        /// The Focus database was read successfully.
        case ok
        /// macOS refused to let us read it: Full Disk Access hasn't been granted.
        case needsFullDiskAccess
        /// It was readable but not in a format we understand (e.g. after a macOS update).
        case unreadable(String)
    }

    var access: Access
    var activeModeIdentifier: String?
    var modes: [FocusMode]

    var activeMode: FocusMode? {
        guard let activeModeIdentifier else { return nil }
        return modes.first { $0.id == activeModeIdentifier }
            ?? FocusMode(id: activeModeIdentifier, name: activeModeIdentifier)
    }

    static let unknown = FocusSnapshot(access: .ok, activeModeIdentifier: nil, modes: [])
}

/// Reads the Focus database from disk. Kept separate from the parsing in
/// `FocusGuardCore` so the parsing stays testable without Full Disk Access.
enum FocusMonitor {
    static func read() -> FocusSnapshot {
        let assertions: Data
        let configurations: Data
        do {
            assertions = try Data(contentsOf: FocusDatabase.assertionsURL)
            configurations = try Data(contentsOf: FocusDatabase.modeConfigurationsURL)
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return FocusSnapshot(access: .needsFullDiskAccess, activeModeIdentifier: nil, modes: [])
        } catch {
            // Without Full Disk Access, macOS reports some reads as generic failures.
            let posix = (error as NSError).underlyingErrors.first as NSError?
            if posix?.domain == NSPOSIXErrorDomain, posix?.code == Int(EPERM) || posix?.code == Int(EACCES) {
                return FocusSnapshot(access: .needsFullDiskAccess, activeModeIdentifier: nil, modes: [])
            }
            return FocusSnapshot(access: .unreadable(error.localizedDescription), activeModeIdentifier: nil, modes: [])
        }

        do {
            return FocusSnapshot(
                access: .ok,
                activeModeIdentifier: try FocusDatabase.activeModeIdentifier(assertionsJSON: assertions),
                modes: try FocusDatabase.modes(modeConfigurationsJSON: configurations)
            )
        } catch {
            return FocusSnapshot(
                access: .unreadable("The Focus database has a format FocusGuard doesn't recognize (\(error))."),
                activeModeIdentifier: nil,
                modes: []
            )
        }
    }
}
