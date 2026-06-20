// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LocalDictation",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LocalDictationCore", targets: ["LocalDictationCore"]),
        .executable(name: "LocalDictation", targets: ["LocalDictationApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.12.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "LocalDictationCore"
        ),
        .executableTarget(
            name: "LocalDictationApp",
            dependencies: [
                "LocalDictationCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .executableTarget(
            name: "LocalDictationCoreTestRunner",
            dependencies: ["LocalDictationCore"]
        )
    ]
)
