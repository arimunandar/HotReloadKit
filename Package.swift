// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HotReloadKit",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "HotReloadKit",
            type: .static,
            targets: ["HotReloadKit"]
        ),
    ],
    targets: [
        .target(
            name: "HotReloadKit",
            dependencies: []
        ),
    ]
)
