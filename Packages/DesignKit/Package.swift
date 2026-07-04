// swift-tools-version: 6.2

import PackageDescription

// ============================================================================
//  DesignKit — the ONE design language for SwiftUI (macOS/iOS).
//
//  The reusable design system: the seed color system (makePrimaryPalette),
//  neutral/semantic palettes, and the component vocabulary (Card, Metric,
//  Sparkline, RingGauge, StatusPill…). Same language + same seeds as the
//  web templates. Canonical source for AIDash's seed color system; consumed
//  by AIDashUI. See tech-context.md for layer contract + red_lines.
// ============================================================================

let package = Package(
    name: "DesignKit",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(name: "DesignKit", targets: ["DesignKit"])
    ],
    targets: [
        .target(
            name: "DesignKit",
            path: "Sources/DesignKit",
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
