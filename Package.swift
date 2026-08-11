// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "mdview",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0")
    ],
    targets: [
        .executableTarget(
            name: "mdview",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/mdview",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "mdviewTests",
            dependencies: ["mdview"]
        )
    ]
)
