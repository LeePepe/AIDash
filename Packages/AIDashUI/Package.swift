// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AIDashUI",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "AIDashUI",
            targets: ["AIDashUI"]
        )
    ],
    dependencies: [
        .package(path: "../AIDashCore"),
        .package(path: "../DesignKit")
    ],
    targets: [
        .target(
            name: "AIDashUI",
            dependencies: [
                .product(name: "AIDashCore", package: "AIDashCore"),
                .product(name: "DesignKit", package: "DesignKit")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AIDashUITests",
            dependencies: ["AIDashUI"]
        )
    ]
)
