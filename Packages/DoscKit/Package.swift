// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DoscKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DoscCore", targets: ["DoscCore"]),
        .library(name: "DoscNetworking", targets: ["DoscNetworking"]),
        .library(name: "DoscStorage", targets: ["DoscStorage"]),
        .library(name: "DoscGitHub", targets: ["DoscGitHub"]),
        .library(name: "DoscUI", targets: ["DoscUI"]),
        .library(name: "DoscFeatures", targets: ["DoscFeatures"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/appstefan/HighlightSwift", from: "1.1.0"),
    ],
    targets: [
        .target(name: "DoscCore"),
        .target(name: "DoscNetworking"),
        .target(name: "DoscStorage", dependencies: ["DoscCore"]),
        .target(name: "DoscGitHub", dependencies: ["DoscCore", "DoscNetworking"]),
        .target(
            name: "DoscUI",
            dependencies: [
                "DoscCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "HighlightSwift", package: "HighlightSwift"),
            ]
        ),
        .target(name: "DoscFeatures", dependencies: ["DoscCore", "DoscStorage", "DoscUI"]),
        .testTarget(name: "DoscCoreTests", dependencies: ["DoscCore"]),
        .testTarget(name: "DoscNetworkingTests", dependencies: ["DoscNetworking"]),
        .testTarget(name: "DoscStorageTests", dependencies: ["DoscStorage"]),
        .testTarget(
            name: "DoscGitHubTests",
            dependencies: ["DoscGitHub", "DoscNetworking"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
