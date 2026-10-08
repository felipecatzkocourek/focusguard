// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusGuard",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FocusGuard", targets: ["FocusGuard"]),
        .executable(name: "focusguard-helper", targets: ["FocusGuardHelper"]),
        .library(name: "FocusGuardCore", targets: ["FocusGuardCore"]),
    ],
    targets: [
        // Pure, UI-free logic: hosts file editing, domain validation, block planning,
        // configuration and activity log. Everything here is unit-tested.
        .target(name: "FocusGuardCore"),

        // Tiny privileged CLI, the only component allowed to write /etc/hosts.
        .executableTarget(
            name: "FocusGuardHelper",
            dependencies: ["FocusGuardCore"]
        ),

        // The app: dashboard window, menu bar item, URL scheme handling (AppKit + SwiftUI).
        .executableTarget(
            name: "FocusGuard",
            dependencies: ["FocusGuardCore"]
        ),

        .testTarget(
            name: "FocusGuardCoreTests",
            dependencies: ["FocusGuardCore"]
        ),
    ]
)
