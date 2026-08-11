// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "zbar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "zbar",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/zbar",
            resources: [
                .copy("Resources/highlight.min.js")
            ]
        )
    ]
)
