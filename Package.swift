// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Hikari",
    // Core and transaction tests remain runnable on the host OS. The shipped
    // Hikari application target is macOS 15+ in project.yml.
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HikariCore", targets: ["HikariCore"]),
        .library(name: "HikariNativeLock", targets: ["HikariNativeLock"]),
        .executable(name: "hikari-native-tool", targets: ["HikariNativeTool"])
    ],
    targets: [
        .target(
            name: "HikariCore",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit")
            ]
        ),
        .target(name: "HikariNativeLock"),
        .executableTarget(
            name: "HikariNativeTool",
            dependencies: ["HikariNativeLock"]
        ),
        .testTarget(
            name: "HikariCoreTests",
            dependencies: ["HikariCore"]
        ),
        .testTarget(
            name: "HikariNativeLockTests",
            dependencies: ["HikariNativeLock"]
        )
    ]
)
