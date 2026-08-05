// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "zbar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "zbar",
            path: "Sources/zbar"
        )
    ]
)
