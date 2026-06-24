// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIDashCore",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
    ],
    products: [
        .library(
            name: "AIDashCore",
            targets: ["AIDashCore"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AIDashCore",
            dependencies: []
        ),
        .testTarget(
            name: "AIDashCoreTests",
            dependencies: ["AIDashCore"]
        ),
    ]
)
