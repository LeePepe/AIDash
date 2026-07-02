// swift-tools-version: 6.0

import PackageDescription

// ============================================================================
//  DesignKit — the ONE design language for SwiftUI (macOS/iOS).
//
//  DesignKit   — the reusable design system: the seed color system
//                (makePrimaryPalette), neutral/semantic palettes, and the
//                component vocabulary (Card, Metric, Sparkline, RingGauge,
//                StatusPill…). Same language + same seeds as the web templates.
//  AppKitDemo  — a thin menu-bar app showing DesignKit in a real dashboard.
//                (Delete this target for a plain library, or keep it as the
//                 menu-bar form.)
// ============================================================================

let package = Package(
    name: "DesignKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DesignKit", targets: ["DesignKit"])
    ],
    targets: [
        .target(
            name: "DesignKit",
            path: "Sources/DesignKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AppKitDemo",
            dependencies: ["DesignKit"],
            path: "Sources/AppKitDemo",
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DesignKitTests",
            dependencies: ["DesignKit"],
            path: "Tests/DesignKitTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
