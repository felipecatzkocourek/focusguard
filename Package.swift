// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusGuard",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FocusGuardCore", targets: ["FocusGuardCore"]),
    ],
    targets: [
        // Pure, UI-free logic: hosts file editing, domain validation, block planning,
        // configuration and activity log. Everything here is unit-tested.
        .target(name: "FocusGuardCore"),

        .testTarget(
            name: "FocusGuardCoreTests",
            dependencies: ["FocusGuardCore"]
        ),
    ]
)
