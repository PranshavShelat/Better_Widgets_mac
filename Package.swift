// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BetterWidgets",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "BetterWidgets",
            path: "Sources/BetterWidgets",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
