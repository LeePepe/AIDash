// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AIDashUI",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "AIDashUI",
            targets: ["AIDashUI"]
        ),
    ],
    dependencies: [
        .package(path: "../AIDashCore"),
    ],
    targets: [
        .target(
            name: "AIDashUI",
            dependencies: [
                .product(name: "AIDashCore", package: "AIDashCore"),
            ]
        ),
    ]
)
