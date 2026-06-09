// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeQuota",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeQuota",
            path: "Sources/ClaudeQuota"
        )
    ]
)
