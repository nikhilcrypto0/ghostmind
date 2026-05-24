// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClueyMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClueyMac", targets: ["ClueyMac"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClueyMac",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "ClueyMac"
        )
    ]
)
