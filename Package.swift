// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Lumina",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LuminaCore", targets: ["LuminaCore"]),
        .library(name: "LuminaNativeLock", targets: ["LuminaNativeLock"]),
        .executable(name: "lumina-native-tool", targets: ["LuminaNativeTool"])
    ],
    targets: [
        .target(
            name: "LuminaCore",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit")
            ]
        ),
        .target(name: "LuminaNativeLock"),
        .executableTarget(
            name: "LuminaNativeTool",
            dependencies: ["LuminaNativeLock"]
        ),
        .testTarget(
            name: "LuminaCoreTests",
            dependencies: ["LuminaCore"]
        ),
        .testTarget(
            name: "LuminaNativeLockTests",
            dependencies: ["LuminaNativeLock"]
        )
    ]
)
