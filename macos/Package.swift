// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeBrain",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeBrain",
            path: "Sources/ClaudeBrain"
        )
    ]
)
