// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GhostMind",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GhostMind", targets: ["GhostMind"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "GhostMind",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "GhostMind"
        )
    ]
)
