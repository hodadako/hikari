// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Lumina",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LuminaCore", targets: ["LuminaCore"])
    ],
    targets: [
        .target(
            name: "LuminaCore",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "LuminaCoreTests",
            dependencies: ["LuminaCore"]
        )
    ]
)
