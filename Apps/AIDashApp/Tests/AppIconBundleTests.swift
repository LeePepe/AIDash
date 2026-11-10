import Foundation
import XCTest

final class AppIconBundleTests: XCTestCase {
    private let expectedLayers: [(name: String, opacity: Double, files: [String])] = [
        ("Front Hero Layer", 1.0, ["front-light.svg", "front-dark.svg", "front-mono.svg"]),
        ("Mid Layer", 0.68, ["mid-light.svg", "mid-dark.svg", "mid-mono.svg"]),
        ("Back Layer", 0.4, ["back-light.svg", "back-dark.svg", "back-mono.svg"]),
    ]

    private var iconBundleURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AppIcon.icon", isDirectory: true)
    }

    func testManifestContainsExpectedGlassLayers() throws {
        let manifestData = try Data(contentsOf: iconBundleURL.appendingPathComponent("icon.json"))
        let manifest = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        let groups = try XCTUnwrap(manifest["groups"] as? [[String: Any]])
        let layers = try XCTUnwrap(groups.first?["layers"] as? [[String: Any]])

        XCTAssertEqual(layers.count, expectedLayers.count)
        for (layer, expected) in zip(layers, expectedLayers) {
            XCTAssertEqual(layer["name"] as? String, expected.name)
            XCTAssertEqual(layer["glass"] as? Bool, true)
            let opacity = try XCTUnwrap(layer["opacity"] as? Double)
            XCTAssertEqual(opacity, expected.opacity, accuracy: 0.001)

            let specializations = try XCTUnwrap(
                layer["image-name-specializations"] as? [[String: Any]]
            )
            XCTAssertEqual(
                specializations.map { $0["appearance"] as? String },
                [nil, "dark", "tinted"]
            )
            XCTAssertEqual(
                specializations.map { $0["value"] as? String },
                expected.files
            )
        }
    }

    func testManifestAssetsAreSafeSVGs() throws {
        let expectedFiles = expectedLayers.flatMap(\.files)

        for filename in expectedFiles {
            let assetURL = iconBundleURL
                .appendingPathComponent("Assets", isDirectory: true)
                .appendingPathComponent(filename)
            let svg = try String(contentsOf: assetURL, encoding: .utf8)

            XCTAssertTrue(svg.contains(#"viewBox="0 0 256 256""#), filename)
            for forbiddenTag in ["<script", "<image", "<foreignObject"] {
                XCTAssertFalse(
                    svg.localizedCaseInsensitiveContains(forbiddenTag),
                    "\(filename) contains \(forbiddenTag)"
                )
            }
        }
    }
}
