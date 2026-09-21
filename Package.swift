// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ComposePilot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ComposePilot",
            path: "Sources/ComposePilot"
        )
    ]
)
